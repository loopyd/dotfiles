#!/usr/bin/env python3
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import sys
import subprocess
import stat

from network import decode_files, restore_files, run


SERVICE = 'svc:ninerouter'
PRIVATE_NATIVE = {
    'TCP': {'443': {'HTTPS': True}},
    'Web': {'ninerouter.tailc28ab1.ts.net:443': {
        'Handlers': {'/': {'Proxy': 'http://127.0.0.1:20128'}}
    }},
}
PRIVATE_SERVE = {'Services': {SERVICE: PRIVATE_NATIVE}}


@contextmanager
def native_lock(name='native.lock'):
    if name not in {'native.lock', 'migration.lock'}:
        raise ValueError('Unknown Tailscale coordination lock')
    path = Path.home() / '.config/tailscale' / name
    if path.parent.resolve() != path.parent:
        raise ValueError('Tailscale lock directory must not be symlinked')
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'r+') as lock:
        metadata = os.fstat(lock.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                or metadata.st_nlink != 1 or metadata.st_mode & 0o077):
            raise ValueError('Unsafe Tailscale coordination lock')
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def native(arguments):
    return run(['/usr/bin/tailscale', '--socket=/var/run/tailscale/tailscaled.sock', *arguments], capture=True)


def exact(actual, expected):
    return json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True)


def private_only(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'AllowFunnel' and child is not None:
                if not isinstance(child, dict) or any(enabled is not False for enabled in child.values()):
                    raise ValueError('Funnel is forbidden, including nested exposure')
            private_only(child)
    elif isinstance(value, list):
        for child in value:
            private_only(child)


def serve_config(value):
    private_only(value)
    if not isinstance(value, dict):
        raise ValueError('Invalid native Serve configuration')
    return {key: child for key, child in value.items()
            if key != 'AllowFunnel'
            and (key not in {'TCP', 'Web', 'Foreground'} or child not in (None, {}))}


def captured():
    expected = json.loads((Path.home() / '.config/tailscale/network.json').read_text())
    private_only(expected)
    expected['serve'] = serve_config(expected['serve'])
    service_mode = exact(expected['serve'], PRIVATE_SERVE)
    if not service_mode and not exact(expected['serve'], PRIVATE_NATIVE):
        raise ValueError('Capture must contain only the fixed private ninerouter HTTPS exposure')
    hostname = 'koija' if service_mode else 'ninerouter'
    tags = expected['tags']
    if tags is None:
        tags = []
    if (not isinstance(expected['node_id'], str) or not expected['node_id']
            or expected['dns_name'] != hostname + '.tailc28ab1.ts.net.'
            or not isinstance(tags, list) or (service_mode and not tags)
            or any(not isinstance(tag, str) or not tag.startswith('tag:') for tag in tags)
            or len(set(tags)) != len(tags)):
        raise ValueError('Capture must identify the native host for the selected private topology')
    expected['tags'] = tags
    prefs = expected['prefs']
    if (not isinstance(prefs, dict) or prefs.get('Hostname') != hostname
            or 'AdvertiseServices' not in prefs):
        raise ValueError('Capture must include the native hostname and Service advertisements')
    if service_mode:
        if prefs['AdvertiseServices'] != [SERVICE]:
            raise ValueError('Capture must include only the already provisioned ninerouter Service advertisement')
    elif prefs['AdvertiseServices'] not in (None, []):
        raise ValueError('Private native mode must not advertise Services')
    return expected


def preferences(expected):
    prefs = json.loads(native(['debug', 'prefs']).stdout)
    if any(key not in prefs or not exact(prefs[key], value) for key, value in expected['prefs'].items()):
        raise ValueError('Tailscale preferences differ from the captured configuration')


def inspect(expected):
    current = json.loads(native(['status', '--json']).stdout)
    node = current['Self']
    if (current.get('BackendState') != 'Running' or node['ID'] != expected['node_id']
            or node.get('DNSName') != expected['dns_name']
            or sorted(node.get('Tags') or []) != sorted(expected['tags'])
            or current['CurrentTailnet']['MagicDNSSuffix'] != 'tailc28ab1.ts.net'):
        raise ValueError('Native Tailscale identity, DNS or tags differ from the capture')
    if 'https' not in (node.get('CapMap') or {}):
        raise ValueError('HTTPS must already be enabled by the tailnet administrator')
    preferences(expected)
    return serve_config(json.loads(native(['serve', 'status', '--json']).stdout))


def empty_exposure(actual):
    for key, value in actual.items():
        if key == 'Services':
            if value is None:
                continue
            if not isinstance(value, dict) or not set(value).issubset({SERVICE}):
                return False
            for service in value.values():
                if not isinstance(service, dict):
                    return False
                for field, setting in service.items():
                    if field in {'TCP', 'Web'} and setting in (None, {}):
                        continue
                    if field == 'Tun' and setting is False:
                        continue
                    return False
        elif key not in {'TCP', 'Web', 'AllowFunnel', 'Foreground'} or value not in (None, {}):
            return False
    return True


def check():
    expected = captured()
    if not exact(inspect(expected), expected['serve']):
        raise ValueError('Tailscale private exposure differs from the captured configuration')
    print('Native Tailscale identity, preferences and private HTTPS exposure match')


def preflight():
    expected = captured()
    actual = inspect(expected)
    if not exact(actual, expected['serve']) and not empty_exposure(actual):
        raise ValueError('Existing exposure differs; refusing to replace it')
    print('Native Tailscale private HTTPS preflight passed')


def apply():
    with native_lock():
        apply_locked()


def apply_locked():
    expected = captured()
    actual = inspect(expected)
    if not exact(actual, expected['serve']):
        if not empty_exposure(actual):
            raise ValueError('Existing exposure differs; refusing to replace it')
        if not exact(captured(), expected) or not exact(inspect(expected), actual):
            raise ValueError('Native configuration changed immediately before Serve')
        if 'Services' in expected['serve']:
            native(['serve', '--service=' + SERVICE, '--bg', '--https=443', 'http://127.0.0.1:20128'])
        else:
            native(['serve', '--bg', '--https=443', '--yes', 'http://127.0.0.1:20128'])
    check()


def identity(home):
    if os.geteuid() != 0:
        raise ValueError('Identity restoration requires root')
    if subprocess.run(['systemctl', 'is-active', '--quiet', 'tailscaled.service']).returncode == 0:
        raise ValueError('Stop tailscaled before restoring identity; never duplicate a running node')
    source = home / '.config/tailscale/identity.json'
    restore_files(Path('/var/lib/tailscale'), decode_files(json.loads(source.read_text())))
    print('Protected Tailscale identity restored without replacing existing files')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['check', 'preflight', 'apply', 'identity'])
    parser.add_argument('--home', type=Path, default=Path.home())
    args = parser.parse_args()
    if args.command == 'identity':
        identity(args.home)
    else:
        {'check': check, 'preflight': preflight, 'apply': apply}[args.command]()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Tailscale operation failed; verify native identity, private HTTPS capture and required privileges. Private details withheld.', file=sys.stderr)
        raise SystemExit(1)
