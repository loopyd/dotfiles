#!/usr/bin/env python3
"""Restore checksum-pinned Codex plugins and review their exact hook definitions."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import time
import tomllib


REPO = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_lock(path):
    lock = json.loads(path.read_text())
    require(lock.get('format') == 1 and lock.get('plugins'), 'Invalid Codex plugin lock')
    return lock


def run(home, arguments):
    environment = dict(os.environ, CODEX_HOME=str(home / '.codex'))
    result = subprocess.run(['codex', *arguments], env=environment, capture_output=True, text=True, timeout=60)
    require(result.returncode == 0, 'Codex plugin command failed: ' + ' '.join(arguments))
    return result.stdout


def configuration(home):
    path = home / '.codex/config.toml'
    return tomllib.loads(path.read_text()) if path.exists() else {}


def cache_root(home, plugin):
    return home / '.codex/plugins/cache' / plugin['marketplace'] / plugin['name'] / plugin['version']


def verify_files(home, plugin):
    root = cache_root(home, plugin)
    require(root.is_dir() and not root.is_symlink(), 'Pinned plugin file root missing or unsafe')
    actual = {str(path.relative_to(root)) for path in root.rglob('*') if path.is_file() or path.is_symlink()}
    require(actual == set(plugin['files']), 'Pinned plugin file inventory changed')
    for relative, expected in plugin['files'].items():
        path = root / relative
        require(not path.is_symlink() and path.is_file() and path.resolve().is_relative_to(root.resolve()),
                'Pinned plugin file missing or unsafe: ' + relative)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == expected, 'Pinned plugin file changed: ' + relative)


def verify_configuration(home, plugin):
    config = configuration(home)
    expected = {'source_type': 'git', 'source': plugin['source'], 'ref': plugin['revision']}
    require(config.get('marketplaces', {}).get(plugin['marketplace']) == expected, 'Marketplace does not match the configured source pin')
    require(config.get('plugins', {}).get(plugin['id'], {}).get('enabled') is True, 'Pinned plugin is not enabled')


def sync(home, lock, dry_run=False):
    for plugin in lock['plugins']:
        if dry_run:
            print('Would install ' + plugin['id'] + ' at ' + plugin['revision'])
            continue
        existing = configuration(home).get('marketplaces', {}).get(plugin['marketplace'])
        expected = {'source_type': 'git', 'source': plugin['source'], 'ref': plugin['revision']}
        require(existing is None or existing == expected, 'Existing marketplace differs from the pin; preserve and review it before replacement')
        run(home, ['plugin', 'marketplace', 'add', plugin['source'], '--ref', plugin['revision'], '--json'])
        run(home, ['plugin', 'add', plugin['id'], '--json'])
        verify_configuration(home, plugin)
        verify_files(home, plugin)
        print('Installed and verified ' + plugin['id'] + ' ' + plugin['version'])


def rpc(home, requests):
    """Use the same hooks/list and config/batchWrite API as Codex's /hooks UI."""
    environment = dict(os.environ, CODEX_HOME=str(home / '.codex'))
    with subprocess.Popen(['codex', 'app-server', '--stdio'], env=environment,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        pending = b''

        def call(request_id, method, params):
            nonlocal pending
            process.stdin.write((json.dumps({'id': request_id, 'method': method, 'params': params}) + '\n').encode())
            process.stdin.flush()
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if b'\n' not in pending:
                    if not select.select([process.stdout], [], [], 1)[0]:
                        continue
                    chunk = os.read(process.stdout.fileno(), 65536)
                    require(chunk, 'Codex app-server closed during hook review')
                    pending += chunk
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    response = json.loads(line)
                    if response.get('id') != request_id:
                        continue
                    require('error' not in response, 'Codex app-server rejected ' + method)
                    return response.get('result')
            raise ValueError('Codex app-server timeout: ' + method)

        try:
            call(0, 'initialize', {'clientInfo': {'name': 'dotfiles-context-gardener', 'version': '1.0.0'},
                                   'capabilities': {'experimentalApi': True}})
            process.stdin.write(b'{"method":"initialized"}\n')
            process.stdin.flush()
            return [call(index, method, params) for index, (method, params) in enumerate(requests, 1)]
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def reviewed_hook_state(plugin, hooks):
    found = {hook['key']: hook for hook in hooks if hook.get('pluginId') == plugin['id']}
    expected = {plugin['id'] + ':' + hook['suffix']: hook['hash'] for hook in plugin['hooks']}
    require(found.keys() == expected.keys(), 'Pinned plugin hook set changed or failed to load')
    for key, expected_hash in expected.items():
        hook = found[key]
        require(hook.get('enabled') and not hook.get('isManaged') and hook.get('currentHash') == expected_hash,
                'Hook definition changed or disabled: ' + key)
    return {key: {'trusted_hash': digest} for key, digest in expected.items()}


def trust(home, lock, cwd):
    for plugin in lock['plugins']:
        verify_files(home, plugin)
        verify_configuration(home, plugin)
    params = {'cwds': [str(cwd.resolve())]}
    listing = rpc(home, [('hooks/list', params)])[0]['data'][0]
    require(not listing['errors'], 'Codex reported hook configuration errors')
    state = {}
    for plugin in lock['plugins']:
        state.update(reviewed_hook_state(plugin, listing['hooks']))
    rpc(home, [('config/batchWrite', {'edits': [{'keyPath': 'hooks.state', 'value': state, 'mergeStrategy': 'upsert'}],
                                     'reloadUserConfig': True})])
    hooks = rpc(home, [('hooks/list', params)])[0]['data'][0]['hooks']
    for plugin in lock['plugins']:
        reviewed_hook_state(plugin, hooks)
    require(all(hook['trustStatus'] == 'trusted' for hook in hooks if hook['key'] in state), 'Hook trust did not persist')
    print('Reviewed and trusted ' + str(len(state)) + ' pinned plugin hooks')


def check(home, lock):
    config = configuration(home)
    for plugin in lock['plugins']:
        verify_configuration(home, plugin)
        verify_files(home, plugin)
        state = config.get('hooks', {}).get('state', {})
        require(all(state.get(plugin['id'] + ':' + hook['suffix'], {}).get('trusted_hash') == hook['hash']
                    and state.get(plugin['id'] + ':' + hook['suffix'], {}).get('enabled', True)
                    for hook in plugin['hooks']), 'Pinned plugin hooks need review: run codex_plugins.py trust or open /hooks')
        print('Pinned source, cached files and hook trust verified: ' + plugin['id'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['sync', 'check', 'trust'])
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--lock', type=Path, default=REPO / 'templates/codex-plugins.json')
    parser.add_argument('--cwd', type=Path, default=Path.cwd())
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    require(not args.dry_run or args.action == 'sync', '--dry-run is only valid for sync')
    lock = load_lock(args.lock)
    if args.action == 'sync':
        sync(args.home, lock, args.dry_run)
    elif args.action == 'trust':
        trust(args.home, lock, args.cwd)
    else:
        check(args.home, lock)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
