#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def fingerprint(path):
    if path.is_symlink():
        return {'link': os.readlink(path)}
    if path.is_file():
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        return {'sha256': digest.hexdigest()}
    raise ValueError('Unsupported payload type: ' + str(path))


def allowed(path, roots):
    if not path.is_absolute() or '..' in path.parts or path.parent.resolve() != path.parent:
        raise ValueError('Unsafe payload path: ' + str(path))
    if not any(path == root or path.is_relative_to(root) for root in roots):
        raise ValueError('Payload outside component roots')


def run(arguments):
    subprocess.run(arguments, check=True)


def privileged(arguments):
    return arguments if os.geteuid() == 0 else ['sudo', '--', *arguments]


def apt_plan(packages):
    installed = []
    for package in packages:
        result = subprocess.run(['dpkg-query', '-W', '-f=${db:Status-Status}', package], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout == 'installed':
            installed.append(package)
    if not installed:
        return []
    result = subprocess.run(['apt-get', '-s', 'remove', '--no-auto-remove', '--', *installed], capture_output=True, text=True, env=dict(os.environ, LC_ALL='C'))
    if result.returncode:
        raise ValueError('APT removal simulation failed')
    removed = {line.split()[1].split(':')[0] for line in result.stdout.splitlines() if line.startswith('Remv ')}
    if not removed.issubset(set(installed)):
        raise ValueError('Removal would affect other packages; refusing dependency cascade')
    return installed


def main():
    parser = argparse.ArgumentParser(description='Record and remove only verified component payloads; never purge user data')
    parser.add_argument('action', choices=['record', 'verify', 'remove'])
    parser.add_argument('component')
    parser.add_argument('--path', type=Path, action='append', default=[])
    parser.add_argument('--package', action='append', default=[])
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.component):
        raise ValueError('Invalid component name')
    roots = args.path
    for root in roots:
        if str(root) in {'/', '/usr', '/usr/local', '/opt', str(Path.home()), str(Path.home() / '.local')}:
            raise ValueError('Refusing broad installation root')
        allowed(root, roots)
    receipt = Path.home() / '.local/state/dotfiles/lifecycle' / (args.component + '.json')
    inputs = {}
    if args.component == 'tools':
        for path in [Path(__file__).resolve().parents[1] / 'templates/packages.json', Path.home() / '.config/mise/config.toml']:
            inputs[str(path)] = fingerprint(path)
    if args.action == 'record':
        files = {}
        for root in roots:
            candidates = root.rglob('*') if root.is_dir() and not root.is_symlink() else [root]
            for path in candidates:
                if path.is_file() or path.is_symlink():
                    allowed(path, roots)
                    files[str(path)] = fingerprint(path)
        data = {'component': args.component, 'files': files, 'packages': args.package, 'inputs': inputs}
        receipt.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if receipt.is_symlink():
            raise ValueError('Refusing symlink receipt')
        descriptor = os.open(receipt, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(data, stream, indent=2)
        print('Recorded component payload: ' + args.component)
        return
    if not receipt.is_file() or receipt.is_symlink():
        raise ValueError('No installation receipt; refusing to remove an unmanaged installation. Install through this command first or review manually.')
    data = json.loads(receipt.read_text())
    if data['component'] != args.component or not set(data['packages']).issubset(args.package):
        raise ValueError('Receipt does not match component selection')
    if data.get('inputs', {}) != inputs:
        raise ValueError('Tool selection changed since install; refusing removal against a different manifest/configuration')
    files = [Path(name) for name in data['files']]
    for path in files:
        allowed(path, roots)
        if path.exists() or path.is_symlink():
            if fingerprint(path) != data['files'][str(path)]:
                raise ValueError('Payload changed since installation; preserve and review: ' + str(path))
    packages = apt_plan(data['packages'])
    if args.action == 'verify':
        print('Verified payload and dependency-safe removal plan: ' + args.component)
        return
    if packages:
        run(privileged(['apt-get', 'remove', '-y', '--no-auto-remove', '--', *packages]))
    for path in files:
        if path.exists() or path.is_symlink():
            command = ['rm', '-f', '--', str(path)]
            run(command if os.access(path.parent, os.W_OK) else privileged(command))
    receipt.unlink()
    print('Recorded files removed; directories and persistent data retained')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print('Lifecycle operation failed: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
