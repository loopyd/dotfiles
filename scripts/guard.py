#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from snapshot import MARKER, TOKEN, URL_CREDENTIAL, private_material


FORBIDDEN_PARTS = {'.ssh', '.gnupg', '.aws', '.azure', '.kube', '.pki', 'keyrings', 'globalStorage', 'workspaceStorage', 'mcp-oauth-locks'}
FORBIDDEN_NAMES = {'auth.json', '.netrc', '.npmrc', '.pypirc', 'jwt-secret', 'Cookies', 'Login Data', 'Web Data', 'shadow', 'gshadow', 'passwd'}
ASSIGNMENT = re.compile(r'''(?im)(?:^|[\s{,])(?:["']?)([A-Za-z_][\w.-]*(?:password|passwd|token|api_key|apiKey|secret|authorization)|password|passwd|token|api_key|apiKey|secret|authorization)["']?\s*[:=]\s*(?:["']([^"'\n]+)["']|([^\s,;}]+))''')


def paths(staged):
    command = ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z'] if staged else ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard']
    return sorted(set(subprocess.check_output(command).decode().split('\0')) - {''})


def findings(name, raw):
    path = Path(name.removesuffix('.tmpl'))
    relative = str(path).removeprefix('root/home/user/')
    parts = Path(relative).parts
    issues = []
    public_key = False
    if path.parent == Path('root/etc/apt/keyrings') and path.suffix == '.gpg':
        with tempfile.TemporaryDirectory(prefix='dotfiles-gpg-') as directory:
            try:
                result = subprocess.run(['gpg', '--batch', '--no-options', '--homedir', directory, '--list-packets'], input=raw, capture_output=True, timeout=15)
                public_key = result.returncode == 0 and b':public key packet:' in result.stdout and b':secret' not in result.stdout
            except (FileNotFoundError, subprocess.TimeoutExpired):
                pass
    if (any(part in FORBIDDEN_PARTS for part in parts) and not public_key) or path.name in FORBIDDEN_NAMES:
        issues.append('account/credential store')
    if relative.startswith(('.config/gh/', '.config/google-chrome/', '.config/mozilla/', '.config/discord/', '.local/state/', '.local/bin/', '.codex/sessions/', '.codex/memories/')):
        issues.append('excluded runtime/account/bin path')
    if path.suffix in {'.pem', '.p12', '.pfx', '.kdbx', '.jks', '.keystore', '.sqlite', '.sqlite3', '.db', '.jsonl'} or path.name == '.env' or path.name.startswith(('.env.', 'id_rsa', 'id_ed25519')):
        issues.append('secret/database/history file')
    try:
        text = raw.decode('utf-8')
    except UnicodeError:
        if not public_key and path.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp', '.ico'}:
            issues.append('unreviewed binary')
        return issues
    scanned = MARKER.sub('TEMPLATE', text)
    if TOKEN.search(scanned):
        issues.append('credential token literal')
    if private_material(scanned, documentation=path.suffix == '.md'):
        issues.append('private key material')
    if URL_CREDENTIAL.search(scanned):
        issues.append('URL with embedded credentials')
    for match in ASSIGNMENT.finditer(scanned):
        value = (match.group(2) or match.group(3)).strip()
        if value in {'TEMPLATE', 'true', 'false', 'none', 'null', '0', '1'} or value.startswith(('$', '<', 'os.', 'process.', 'env.', 'None', 'False', 'True')):
            continue
        if path.suffix == '.md' and value.lower().startswith(('your-', 'your_', 'sk-your-')):
            continue
        configuration = str(path).startswith('root/home/user/')
        if len(value) >= 8 and re.fullmatch(r'[A-Za-z0-9_./+=:@-]+', value) and (configuration or re.search(r'[0-9/+=@]', value)):
            issues.append('literal credential assignment')
    if re.search(r'(?im)^\s*(?:email|user(?:name)?)\s*[=:]\s*["\']?[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', scanned):
        issues.append('personal account assignment')
    return sorted(set(issues))


def main():
    parser = argparse.ArgumentParser(description='Scan complete staged blobs without printing secret values.')
    parser.add_argument('--staged', action='store_true')
    parser.add_argument('--values', type=Path)
    args = parser.parse_args()
    known = []
    if args.values:
        known = [value for key, value in json.loads(args.values.read_text()).items() if key.startswith('SECRET_') and isinstance(value, str) and len(value) >= 12]
    failures = []
    names = paths(args.staged)
    for name in names:
        path = Path(name)
        if not args.staged and not path.exists() and not path.is_symlink():
            continue
        if args.staged:
            raw = subprocess.check_output(['git', 'show', ':' + name])
            mode = subprocess.check_output(['git', 'ls-files', '-s', '--', name], text=True).split()[0]
            symlink = mode == '120000'
        else:
            raw = path.read_bytes() if not path.is_symlink() else str(path.readlink()).encode()
            symlink = path.is_symlink()
        issues = findings(name, raw)
        if symlink:
            issues.append('host symlink must be represented by renderer manifest')
        if any(value.encode() in raw or json.dumps(value)[1:-1].encode() in raw for value in known):
            issues.append('known private value')
        if issues:
            failures.append({'file': name, 'findings': sorted(set(issues))})
    print(json.dumps({'files_scanned': len(names), 'findings': failures}, indent=2))
    raise SystemExit(bool(failures))


if __name__ == '__main__':
    main()
