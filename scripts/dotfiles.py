#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import tomllib
from xml.sax.saxutils import escape

from snapshot import MARKER, private_write
from network import decode_tables, restore_tables
from scope import game_document, game_path


def beneath(root, relative):
    if game_path(relative):
        raise ValueError('Game configuration is outside dotfiles scope')
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Unsafe manifest path: ' + relative)
    target = root / path
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Path escapes root through a symlink: ' + relative)
    return target


def materialize(text, values, target):
    def replace(match):
        value = values[match.group(1)]
        if not isinstance(value, str) or '\x00' in value or (target.suffix not in {'.json', '.toml'} and ('\n' in value or '\r' in value)):
            raise ValueError('Values must be single-line strings: ' + match.group(1))
        if target.suffix in {'.json', '.toml'}:
            return json.dumps(value, ensure_ascii=False)[1:-1]
        if target.suffix == '.sql':
            return value.replace("'", "''")
        if target.suffix in {'.xml', '.svg'}:
            return escape(value, {'"': '&quot;', "'": '&apos;'})
        return value
    rendered = MARKER.sub(replace, text)
    if MARKER.search(rendered):
        raise ValueError('Unresolved template variable: ' + str(target))
    if target.suffix == '.json' and '/.config/Code/User/' not in str(target):
        json.loads(rendered)
    elif target.suffix == '.toml':
        tomllib.loads(rendered)
    return rendered


def restore_router(home, backup, port):
    with socket.socket() as probe:
        probe.settimeout(1)
        if probe.connect_ex(('127.0.0.1', port)) == 0:
            raise ValueError('Stop 9router before restoring its configuration tables')
    database = home / '.9router/db/data.sqlite'
    if not database.exists():
        raise ValueError('Initialize 9router once, then stop it before database restore')
    tables = decode_tables(json.loads((home / '.config/9router/restore.json').read_text()))
    connection = sqlite3.connect(database)
    saved = backup / '9router.sqlite'
    saved.touch(mode=0o600)
    with sqlite3.connect(saved) as destination:
        connection.backup(destination)
    connection.close()
    restore_tables(database, tables)


def main():
    parser = argparse.ArgumentParser(description='Preview or render captured configuration; never start services or install packages.')
    parser.add_argument('action', choices=['install', 'update', 'uninstall', 'check'])
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--values', type=Path, default=Path.home() / '.config/dotfiles/values.json')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--restore-router', action='store_true')
    parser.add_argument('--router-port', type=int, default=20128)
    args = parser.parse_args()
    args.apply = args.action in {'install', 'update'} and not args.dry_run
    if args.restore_router and not args.apply:
        parser.error('--restore-router requires a non-dry install or update')
    if args.action == 'uninstall':
        print('Configuration renderer has no installed runtime; user configuration and rollback backups are preserved.')
        return
    if not 1 <= args.router_port <= 65535:
        raise ValueError('Router port must be between 1 and 65535')
    root = args.repo.resolve()
    home = args.home.resolve()
    if args.values.resolve().is_relative_to(root):
        raise ValueError('The private values file must be outside the repository')
    manifest = json.loads((root / 'templates/manifest.json').read_text())
    if manifest.get('format') != 1:
        raise ValueError('Unsupported manifest format')
    values = json.loads(args.values.read_text()) if args.values.exists() else {}
    values.update(HOME=str(home), USER=home.name, UID=str(os.getuid()), GID=str(os.getgid()))
    plans = []
    missing = set()
    targets = set()
    for entry in manifest['files']:
        source = beneath(root, entry['source'])
        target = beneath(home, entry['target'])
        if target in targets or target.is_symlink():
            raise ValueError('Duplicate or symlink target: ' + entry['target'])
        targets.add(target)
        text = source.read_bytes().decode('utf-8')
        if game_document(entry['target'], text):
            raise ValueError('Game launchers are outside dotfiles scope')
        if entry['mode'] not in {'0600', '0644', '0700', '0755'}:
            raise ValueError('Unsupported file mode: ' + entry['source'])
        if hashlib.sha256(text.encode()).hexdigest() != entry['sha256']:
            raise ValueError('Manifest hash drift: ' + entry['source'])
        missing.update(name for name in MARKER.findall(text) if not isinstance(values.get(name), str))
        plans.append((entry, target, text))
    print(json.dumps({'files': len(plans), 'unit_links': len(manifest['symlinks']), 'missing_values': sorted(missing), 'apply': args.apply}, indent=2))
    if missing:
        raise ValueError('Missing private values; no files written')
    rendered = [(entry, target, materialize(text, values, target)) for entry, target, text in plans]
    link_plans = []
    for entry in manifest['symlinks']:
        target = beneath(home, entry['target'])
        resolved = (target.parent / entry['link']).resolve()
        if game_path(resolved.relative_to(home) if resolved.is_relative_to(home) else resolved):
            raise ValueError('Game unit destinations are outside dotfiles scope')
        if not str(entry['target']).startswith('.config/systemd/user/') or not resolved.is_relative_to(home / '.config/systemd/user'):
            raise ValueError('Only internal user-unit links may be restored')
        if target.exists() and not target.is_symlink():
            raise ValueError('Refusing to replace a regular file with a unit link')
        link_plans.append((entry, target))
    if not args.apply:
        return
    backup = home / '.local/state/dotfiles' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup.mkdir(parents=True, mode=0o700)
    for relative in ('.local/share/hindsight/postgres', '.local/share/hindsight/cache', '.local/state/hindsight'):
        beneath(home, relative).mkdir(parents=True, exist_ok=True, mode=0o700)
    changed = []
    try:
        for entry, target, text in rendered:
            existed = target.exists()
            saved = backup / entry['target']
            if existed:
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved)
            changed.append((target, saved if existed else None))
            private_write(target, text)
            target.chmod(int(entry['mode'], 8))
        for entry, target in link_plans:
            if target.is_symlink():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(entry['link'])
            changed.append((target, None))
        if args.restore_router:
            restore_router(home, backup, args.router_port)
    except Exception:
        for target, saved in reversed(changed):
            if saved is None:
                target.unlink(missing_ok=True)
            else:
                shutil.copy2(saved, target)
        raise
    print('Rendered configuration; rollback copies: ' + str(backup))
    print('No packages installed or services started. Reload the user systemd manager after review.')


if __name__ == '__main__':
    main()
