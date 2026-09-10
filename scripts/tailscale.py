#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import sys
import subprocess

from network import decode_files, restore_files, run


def captured():
    return json.loads((Path.home() / '.config/tailscale/network.json').read_text())


def preferences(expected):
    prefs = json.loads(run(['tailscale', 'debug', 'prefs'], capture=True).stdout)
    if any(prefs.get(key) != value for key, value in expected['prefs'].items()):
        raise ValueError('Tailscale preferences differ from the captured configuration')


def check():
    expected = captured()
    current = json.loads(run(['tailscale', 'status', '--json'], capture=True).stdout)
    if current.get('BackendState') != 'Running' or current['Self']['ID'] != expected['node_id']:
        raise ValueError('Tailscale identity does not match the captured node')
    actual = json.loads(run(['tailscale', 'serve', 'status', '--json'], capture=True).stdout)
    if actual != expected['serve']:
        raise ValueError('Tailscale exposure differs from the captured configuration')
    preferences(expected)
    print('Tailscale identity and all captured Serve/Funnel exposure match')


def apply():
    expected = captured()
    current = json.loads(run(['tailscale', 'status', '--json'], capture=True).stdout)
    if current.get('BackendState') != 'Running' or current['Self']['ID'] != expected['node_id']:
        raise ValueError('Restore the original node identity before exposing services')
    preferences(expected)
    actual = json.loads(run(['tailscale', 'serve', 'status', '--json'], capture=True).stdout)
    if actual == expected['serve']:
        check()
        return
    if actual:
        raise ValueError('Existing exposure differs; refusing to replace it')
    serve = expected['serve']
    if set(serve) != {'TCP', 'Web', 'AllowFunnel'} or len(serve['Web']) != 1:
        raise ValueError('Unsupported exposure; restore identity state instead')
    address, definition = next(iter(serve['Web'].items()))
    port = address.rsplit(':', 1)[1]
    if definition.get('Handlers', {}).keys() != {'/'} or serve['TCP'] != {port: {'HTTPS': True}} or serve['AllowFunnel'] != {address: True}:
        raise ValueError('Unsupported Funnel configuration')
    target = definition['Handlers']['/']['Proxy']
    if target != 'http://127.0.0.1:20128':
        raise ValueError('Unexpected upstream; refusing exposure change')
    run(['tailscale', 'funnel', '--bg', '--https=' + port, target])
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
    parser.add_argument('command', choices=['check', 'apply', 'identity'])
    parser.add_argument('--home', type=Path, default=Path.home())
    args = parser.parse_args()
    if args.command == 'identity':
        identity(args.home)
    else:
        {'check': check, 'apply': apply}[args.command]()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Tailscale operation failed; verify node identity, existing exposure and required privileges. Private details withheld.', file=sys.stderr)
        raise SystemExit(1)
