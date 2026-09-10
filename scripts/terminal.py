#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def check(name):
    root = Path.home() / '.config' / name
    path = root / ('config.toml' if name == 'herdr' else 'alacritty.toml')
    text = path.read_text()
    if '@@DOTFILES:' in text:
        raise ValueError('Configuration has unresolved markers')
    data = tomllib.loads(text)
    if name == 'herdr':
        if not (Path.home() / '.config/systemd/user/herdr.service').is_file():
            raise ValueError('Render the herdr unit first')
    else:
        for imported in data.get('general', {}).get('import', []):
            target = Path(imported).expanduser()
            if not target.is_absolute():
                target = root / target
            tomllib.loads(target.read_text())
    print(name + ' configuration and references validated')


def plugins(dry_run):
    home = Path.home()
    archive = home / '.config/herdr/restore/plugins.json'
    if dry_run:
        archive = ROOT / 'root/home/user/.config/herdr/restore/plugins.json.tmpl'
    desired = json.loads(archive.read_text().replace('@@DOTFILES:HOME@@', str(home)))
    registry = home / '.config/herdr/plugins.json'
    current = json.loads(registry.read_text()) if registry.exists() else []
    present = {entry['plugin_id']: entry for entry in current}
    binary = str(home / '.local/bin/herdr')
    for entry in desired:
        identity = entry['plugin_id']
        source = entry['source']
        if 'pi-herd' in identity:
            print('SKIP retired Pi plugin: ' + identity + ' (existing installation unchanged)')
            continue
        installed = present.get(identity)
        if installed and Path(installed['manifest_path']).is_file():
            print('PRESERVE installed plugin: ' + identity)
            continue
        if source['kind'] == 'github':
            repository = source['owner'] + '/' + source['repo']
            revision = source['resolved_commit']
            if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository) or not re.fullmatch(r'[0-9a-f]{40}', revision):
                raise ValueError('Invalid plugin source')
            command = [binary, 'plugin', 'install', repository, '--ref', revision, '--yes']
        elif source['kind'] == 'local':
            path = Path(entry['plugin_root'])
            if not path.is_absolute():
                raise ValueError('Local plugin needs an absolute source path')
            if not path.is_dir() and not dry_run:
                print('MANUAL: restore source checkout for ' + identity + ' at ' + str(path))
                continue
            command = [binary, 'plugin', 'link', str(path), '--enabled' if entry['enabled'] else '--disabled']
        else:
            raise ValueError('Unknown plugin source')
        print(('DRY-RUN: ' if dry_run else 'RUN: ') + shlex.join(command))
        if not dry_run:
            subprocess.run(command, check=True)
            if not entry['enabled'] and source['kind'] == 'github':
                subprocess.run([binary, 'plugin', 'disable', identity], check=True)


def main():
    parser = argparse.ArgumentParser(description='Validate terminal settings and restore registered herdr plugin sources')
    parser.add_argument('command', choices=['check-herdr', 'check-alacritty', 'plugins'])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'plugins':
            plugins(args.dry_run)
        else:
            check(args.command.removeprefix('check-'))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        print('Terminal setup validation failed; check rendered configuration and plugin source availability. Private details withheld.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
