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
import time

from network import decode_files, restore_files, run


SERVICE = 'svc:ninerouter'
PRIVATE_NATIVE = {
    'TCP': {'443': {'HTTPS': True}},
    'Web': {'ninerouter.tailc28ab1.ts.net:443': {
        'Handlers': {'/': {'Proxy': 'http://127.0.0.1:20128'}}
    }},
}
PRIVATE_ROUTER = {'Services': {SERVICE: PRIVATE_NATIVE}}
PRIVATE_SERVE = {'Services': {
    SERVICE: PRIVATE_NATIVE,
    'svc:hindsight': {
        'TCP': {'443': {'HTTPS': True}},
        'Web': {'hindsight.tailc28ab1.ts.net:443': {
            'Handlers': {'/': {'Proxy': 'http://127.0.0.1:9999'}}
        }},
    },
}}


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


def native(arguments, timeout=None, deadline=None):
    if deadline is not None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Native Tailscale readiness deadline expired')
        timeout = remaining if timeout is None else min(timeout, remaining)
    return run(['/usr/bin/tailscale', '--socket=/var/run/tailscale/tailscaled.sock', *arguments], capture=True, timeout=timeout)


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
    service_mode = any(exact(expected['serve'], allowed) for allowed in (PRIVATE_ROUTER, PRIVATE_SERVE))
    if not service_mode and not exact(expected['serve'], PRIVATE_NATIVE):
        raise ValueError('Capture must contain only the approved private HTTPS exposures')
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
        if prefs['AdvertiseServices'] != sorted(expected['serve']['Services']):
            raise ValueError('Capture must advertise exactly the approved private Services')
    elif prefs['AdvertiseServices'] not in (None, []):
        raise ValueError('Private native mode must not advertise Services')
    return expected


def preferences(expected, deadline=None, allow_missing=False):
    prefs = json.loads(native(['debug', 'prefs'], deadline=deadline).stdout)
    for key, value in expected['prefs'].items():
        if key == 'AdvertiseServices' and 'Services' in expected['serve']:
            actual = prefs.get(key) or []
            if (not isinstance(actual, list) or any(not isinstance(name, str) for name in actual)
                    or len(actual) != len(set(actual))):
                raise ValueError('Invalid native Service advertisements')
            if allow_missing and set(actual).issubset(value):
                continue
            if sorted(actual) == value:
                continue
        if key not in prefs or not exact(prefs[key], value):
            raise ValueError('Tailscale preferences differ from the captured configuration')
    return prefs


def inspect(expected, deadline=None, allow_missing=False):
    current = json.loads(native(['status', '--json'], deadline=deadline).stdout)
    node = current['Self']
    if (current.get('BackendState') != 'Running' or node['ID'] != expected['node_id']
            or node.get('DNSName') != expected['dns_name']
            or sorted(node.get('Tags') or []) != sorted(expected['tags'])
            or current['CurrentTailnet']['MagicDNSSuffix'] != 'tailc28ab1.ts.net'):
        raise ValueError('Native Tailscale identity, DNS or tags differ from the capture')
    if 'https' not in (node.get('CapMap') or {}):
        raise ValueError('HTTPS must already be enabled by the tailnet administrator')
    preferences(expected, deadline=deadline, allow_missing=allow_missing)
    return serve_config(json.loads(native(['serve', 'status', '--json'], deadline=deadline).stdout))


def empty_exposure(actual):
    for key, value in actual.items():
        if key == 'Services':
            if value is None:
                continue
            if not isinstance(value, dict) or not set(value).issubset(PRIVATE_SERVE['Services']):
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


def compatible_exposure(actual, expected):
    if 'Services' not in expected:
        return exact(actual, expected) or empty_exposure(actual)
    if set(actual) - {'Services'}:
        return False
    services = actual.get('Services') or {}
    if not isinstance(services, dict) or not set(services).issubset(expected['Services']):
        return False
    return all(exact(service, expected['Services'][name])
               or empty_exposure({'Services': {name: service}})
               for name, service in services.items())


def check():
    expected = captured()
    if not exact(inspect(expected), expected['serve']):
        raise ValueError('Tailscale private exposure differs from the captured configuration')
    print('Native Tailscale identity, preferences and private HTTPS exposure match')


def preflight(expected=None, deadline=None):
    if expected is None:
        expected = captured()
    actual = inspect(expected, deadline=deadline, allow_missing=True)
    if not compatible_exposure(actual, expected['serve']):
        raise ValueError('Existing exposure differs; refusing to replace it')
    print('Native Tailscale private HTTPS preflight passed')


def wait():
    expected = captured()
    deadline = time.monotonic() + 120
    print('Waiting up to 120 seconds for native Tailscale readiness', flush=True)
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            current = json.loads(native(['status', '--json'], timeout=min(5, remaining)).stdout)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            current = {}
        state = current.get('BackendState')
        if state in {'NeedsLogin', 'NeedsMachineAuth', 'Stopped'}:
            raise ValueError('Native Tailscale requires administrator action before startup')
        node = current.get('Self') or {}
        tailnet = current.get('CurrentTailnet') or {}
        if (state == 'Running' and node.get('Online') and node.get('ID')
                and node.get('DNSName') and node.get('CapMap')
                and tailnet.get('MagicDNSSuffix')):
            try:
                preflight(expected, deadline=deadline)
            except subprocess.TimeoutExpired as error:
                raise TimeoutError('Native Tailscale preflight readiness timed out') from error
            return
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(2, remaining))
    raise TimeoutError('Native Tailscale readiness timed out after 120 seconds')


def apply():
    with native_lock():
        apply_locked()


def apply_locked():
    expected = captured()
    actual = inspect(expected, allow_missing=True)
    advertised = sorted(preferences(expected, allow_missing=True).get('AdvertiseServices') or [])
    missing = set(expected['serve'].get('Services', {})) - set(advertised)
    if not exact(actual, expected['serve']) or missing:
        if not compatible_exposure(actual, expected['serve']):
            raise ValueError('Existing exposure differs; refusing to replace it')
        if (not exact(captured(), expected) or not exact(inspect(expected, allow_missing=True), actual)
                or sorted(preferences(expected, allow_missing=True).get('AdvertiseServices') or []) != advertised):
            raise ValueError('Native configuration changed immediately before Serve')
        if 'Services' in expected['serve']:
            for name, service in expected['serve']['Services'].items():
                if (not exact(captured(), expected) or not exact(inspect(expected, allow_missing=True), actual)
                        or sorted(preferences(expected, allow_missing=True).get('AdvertiseServices') or []) != advertised):
                    raise ValueError('Native configuration changed immediately before Serve')
                if exact((actual.get('Services') or {}).get(name), service) and name not in missing:
                    continue
                endpoint = next(iter(service['Web'].values()))['Handlers']['/']['Proxy']
                native(['serve', '--service=' + name, '--bg', '--https=443', endpoint])
                updated = inspect(expected, allow_missing=True)
                current_advertised = sorted(preferences(expected, allow_missing=True).get('AdvertiseServices') or [])
                intended = {'Services': {**(actual.get('Services') or {}), name: service}}
                if not exact(updated, intended) or current_advertised != sorted(set(advertised) | {name}):
                    raise ValueError('Unexpected native configuration after Serve')
                actual = updated
                advertised = current_advertised
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
    parser.add_argument('command', choices=['check', 'preflight', 'wait', 'apply', 'identity'])
    parser.add_argument('--home', type=Path, default=Path.home())
    args = parser.parse_args()
    if args.command == 'identity':
        identity(args.home)
    else:
        {'check': check, 'preflight': preflight, 'wait': wait, 'apply': apply}[args.command]()


if __name__ == '__main__':
    try:
        main()
    except TimeoutError:
        print('Native Tailscale readiness timed out; dependent services were not started.', file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print('Tailscale operation failed; verify native identity, private HTTPS capture and required privileges. Private details withheld.', file=sys.stderr)
        raise SystemExit(1)
