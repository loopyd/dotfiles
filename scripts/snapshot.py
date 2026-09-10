#!/usr/bin/env python3
import argparse
import datetime
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import tomllib
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape


MARKER = re.compile(r'@@DOTFILES:([A-Z0-9_]+)@@')
TOKEN = re.compile(r'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|hf_[A-Za-z0-9]{25,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[\w-]{30,}|AKIA[A-Z0-9]{16}|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,})\b')
SENSITIVE = re.compile(r'api.?key|password|passwd|secret|authorization|credential|license|_key$|token$|^email$', re.I)
ASSIGNMENT = re.compile(r'''(?im)^[ \t]*(?:export[ \t]+)?["']?([\w.-]*(?:key|token|secret|password|passwd|email|authorization))["']?[ \t]*[=:][ \t]*["']?([^\r\n"'#;]+)''')
URL_CREDENTIAL = re.compile(r'\b[a-z][a-z0-9+.-]*://[^\s/"\']+:[^\s@"\']+@[^\s"\']+')
TABLES = ('settings', 'providerNodes', 'providerConnections', 'combos', 'apiKeys', 'proxyPools')
NOISE = {'node_modules', '__pycache__', '.git', '.venv', 'venv', 'cache', 'caches', 'logs', 'log', 'tmp', 'temp', 'backups', 'backup', 'sessions', 'history', 'crashpad', 'crash reports', 'gpucache', 'code cache', 'service worker', 'storage', 'workspacestorage', 'globalstorage', 'extensions', 'plugins', 'databases', 'downloads', 'compiled', 'lazy', 'site-packages', 'mcp-oauth-locks', '.system', 'sample libraries', 'firmware', 'dev_flash', 'dev_hdd0', 'dev_hdd1', 'dev_bdvd'}
PRIVATE_CONFIG = {'gh', 'google-chrome', 'chromium', 'mozilla', 'discord', 'dconf', 'dotfiles', 'evolution', 'goa-1.0', 'tailscale', 'electron', 'cinnamon-session', 'pi-hashline-edit-pro', 'sticky'}
EXTENSIONS = {'.conf', '.toml', '.json', '.ini', '.yaml', '.yml', '.xml', '.desktop', '.list', '.rc', '.lua', '.vim', '.fish', '.sh', '.bash', '.css', '.svg', '.env', '.sql', '.txt', '.md', '.rules', '.service', '.socket', '.timer', '.target', '.path', '.dirs', '.locale', '.lst', '.properties', '.settings', '.config', '.py', '.js', '.mjs'}
ROOT_FILES = ('.bashrc', '.bash_profile', '.bash_logout', '.profile', '.zshrc', '.zprofile', '.gitconfig', '.tmux.conf', '.asoundrc', '.gtkrc-2.0', '.gtkrc-xfce', '.nvidia-settings-rc', '.inputrc', '.Xresources', '.xprofile', 'Documents/patchbay_persist.xml', 'Documents/pipewirepatch.qpwgraph')


def private_material(text, documentation=False):
    header = r'-----BEGIN [A-Z ]*(?:PRIVATE KEY|PRIVATE KEY BLOCK)-----'
    if not re.search(header, text):
        return False
    if not documentation:
        return True
    normalized = text.replace('\\n', '\n').replace('\\r', '\r')
    return bool(re.search(header + r'(?:\s|(?:Version|Comment):[^\n]*\n)*[A-Za-z0-9+/=]{32,}', normalized))


def private_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        output.write(text)
    path.chmod(0o600)


def safe_value(value):
    if not isinstance(value, str) or not value:
        return False
    return not (value.startswith(('@@', '<', 'os.', 'process.', 'env.')) or re.fullmatch(r'\$(?:[A-Z_][A-Z0-9_]*|\{[A-Z_][A-Z0-9_]*\})', value))


class Scrubber:
    def __init__(self, home):
        self.home = home
        self.values = {'HOME': str(home), 'USER': home.name, 'UID': str(os.getuid()), 'GID': str(os.getgid())}
        self.secrets = {}
        self.local = {}
        self.label = ''

    def remember(self, value, label, key=None):
        if not safe_value(value) or value == str(self.home):
            return
        name = 'SECRET_' + re.sub(r'[^A-Z0-9]+', '_', label.upper()).strip('_')[:65]
        original = name
        suffix = 1
        while name in self.values and self.values[name] != value:
            suffix += 1
            name = original + '_' + str(suffix)
        self.values[name] = value
        if len(value) < 8:
            if key:
                self.local.setdefault(self.label, []).append((key, value, name))
        else:
            self.secrets[value] = name

    def structured(self, value, path):
        if isinstance(value, dict):
            for key, item in value.items():
                if (SENSITIVE.search(key) or key == 'key' and 'apiKeys' in path) and isinstance(item, str):
                    self.remember(item, path + '_' + key, key)
                self.structured(item, path + '_' + key)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                self.structured(item, path + '_' + str(index))

    def inspect(self, text, label):
        self.label = label
        try:
            for element in ET.fromstring(text).iter():
                for key, value in element.attrib.items():
                    if SENSITIVE.search(key):
                        self.remember(value, label + '_' + key, key)
                if SENSITIVE.search(element.attrib.get('name', element.tag)):
                    self.remember(element.attrib.get('val', element.text or ''), label + '_' + element.attrib.get('name', element.tag))
        except ET.ParseError:
            pass
        for loader in (json.loads, tomllib.loads):
            try:
                self.structured(loader(text), label)
                break
            except (ValueError, TypeError):
                pass
        for match in ASSIGNMENT.finditer(text):
            self.remember(match.group(2).strip().rstrip(','), label + '_' + match.group(1), match.group(1))
        for match in TOKEN.finditer(text):
            self.remember(match.group(), label + '_credential')
        for match in URL_CREDENTIAL.finditer(text):
            self.remember(match.group(), label + '_url')
        for match in re.finditer(r"(?i)\bPASSWORD\s+'([^']+)'", text):
            self.remember(match.group(1), label + '_database_password')

    def scrub(self, text, label):
        for key, value, name in self.local.get(label, []):
            pattern = r'''(["']?''' + re.escape(key) + r'''["']?\s*[=:]\s*["']?)''' + re.escape(value) + r'''(?=["'\s,}]|$)'''
            text = re.sub(pattern, lambda match: match.group(1) + '@@DOTFILES:' + name + '@@', text)
        for value, name in sorted(self.secrets.items(), key=lambda entry: len(entry[0]), reverse=True):
            marker = '@@DOTFILES:' + name + '@@'
            text = text.replace(json.dumps(value, ensure_ascii=False)[1:-1], marker)
            text = text.replace(escape(value, {'"': '&quot;', "'": '&apos;'}), marker)
            text = text.replace(value, marker)
        text = text.replace(str(self.home), '@@DOTFILES:HOME@@')
        text = text.replace('/run/user/' + str(os.getuid()), '/run/user/@@DOTFILES:UID@@')
        if label in {'.config/hindsight/compose.yaml', '.config/9router/compose.yaml'}:
            text = text.replace(str(os.getuid()) + ':' + str(os.getgid()), '@@DOTFILES:UID@@:@@DOTFILES:GID@@')
            text = text.replace('uid=' + str(os.getuid()), 'uid=@@DOTFILES:UID@@')
            text = text.replace('gid=' + str(os.getgid()), 'gid=@@DOTFILES:GID@@')
        return text


def reason(path, is_dir=False):
    parts = path.parts
    lowered = [part.lower() for part in parts]
    name = path.name.lower()
    if str(path).startswith('.config/go/telemetry') or str(path) == '.config/uv/uv-receipt.json':
        return 'tool telemetry/installation receipt'
    if str(path) in {'.config/herdr/plugins.json', '.config/herdr/release-notes.json'}:
        return 'herdr live registry/cache (registry archived separately for native restoration)'
    blocked = NOISE - {'plugins'} if parts[:4] == ('.config', 'nvim', 'lua', 'plugins') else NOISE
    if any(part in blocked for part in lowered):
        return 'runtime/cache/dependency'
    if parts[0] == '.config' and len(parts) > 1 and lowered[1] in PRIVATE_CONFIG:
        return 'account/session store'
    if parts[0] == '.config' and len(parts) > 2 and parts[1] == 'Code' and parts[2] != 'User':
        return 'editor runtime'
    if parts[:4] == ('.config', 'Code', 'User', 'mcp'):
        return 'installed MCP package'
    if is_dir:
        return None
    if any(word in name for word in ('history', 'recent', 'session', 'cookie', 'usage', 'license', 'request-details', 'login data', 'model_catalog', 'models_cache')):
        return 'history/identity/runtime'
    if name in {'auth.json', 'installation_id', 'machine-id', 'jwt-secret', '.netrc', '.npmrc', '.pypirc'} or name.startswith(('id_rsa', 'id_ed25519')):
        return 'credential store'
    if path.suffix.lower() in {'.db', '.sqlite', '.sqlite3', '.jsonl', '.bak', '.save', '.log', '.pem', '.p12', '.pfx', '.kdbx', '.rk', '.key', '.gpg'} or re.search(r'\.(?:bak|save|backup)[.-]', name):
        return 'database/secret/backup'
    if path.suffix and path.suffix.lower() not in EXTENSIONS and str(path) not in ROOT_FILES:
        return 'not configuration text'
    return None


def router_export(home):
    database = home / '.9router/db/data.sqlite'
    if not database.is_file():
        return None
    connection = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute('BEGIN')
    tables = {}
    for table in TABLES:
        records = []
        for row in connection.execute('SELECT * FROM "' + table + '"'):
            record = dict(row)
            for key in ('data', 'models'):
                if key in record and isinstance(record[key], str):
                    record[key] = json.loads(record[key])
            if isinstance(record.get('data'), dict):
                record['data'] = {key: value for key, value in record['data'].items() if key not in {'accessToken', 'refreshToken', 'idToken', 'cookies', 'cookie', 'expiresAt', 'lastError', 'lastErrorType'} and not key.startswith('modelLock_')}
            records.append(record)
        tables[table] = records
    connection.close()
    return json.dumps({'format': 1, 'tables': tables, 'oauth_requires_login': True}, indent=2) + '\n'


def capture(args):
    home = args.home.resolve()
    output = args.output.resolve()
    values_path = args.values.resolve()
    if values_path.is_relative_to(output) or home == output:
        raise ValueError('Private values must be outside the snapshot')
    if any((parent / '.git').exists() for parent in values_path.parents):
        raise ValueError('Private values must be outside Git working trees')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Use an empty output directory')
    scrubber = Scrubber(home)
    collected = {}
    private_network = {'.config/9router/identity.json', '.config/9router/restore.json', '.config/tailscale/identity.json'}
    existing_values = json.loads(values_path.read_text()) if values_path.exists() else {}
    network_keys = {'SECRET_ROUTER_IDENTITY', 'SECRET_ROUTER_TABLES', 'SECRET_TAILSCALE_IDENTITY'}
    preserve_network = network_keys.issubset(existing_values)
    if preserve_network:
        scrubber.values.update({key: existing_values[key] for key in network_keys})
        for relative in private_network | {'.config/tailscale/network.json', '.config/tailscale/default.env'}:
            template = Path(__file__).resolve().parents[1] / 'root/home/user' / (relative + '.tmpl')
            collected[relative] = (template.read_text(), False)
    exclusions = Counter()
    links = []
    roots = ['.config', '.agents', '.codex/skills', '.codex/rules', '.local/bin', '.local/share/applications', '.local/share/desktop-directories']
    fixed = [*ROOT_FILES, '.codex/config.toml', '.codex/hooks.json', '.codex/AGENTS.md', '.hindsight/config', '.hindsight/coding-agent.json', '.cargo/env', '.rustup/settings.toml']
    candidates = [home / name for name in fixed if (home / name).exists()]
    for prefix in roots:
        base = home / prefix
        if not base.exists():
            continue
        for directory, directories, files in os.walk(base, followlinks=False):
            parent = Path(directory)
            directories[:] = sorted(name for name in directories if not (parent / name).is_symlink() and not reason((parent / name).relative_to(home), is_dir=True))
            candidates.extend(parent / name for name in sorted(files))
    for source in sorted(set(candidates)):
        relative = source.relative_to(home)
        if str(relative) in private_network:
            exclusions['private network bundle (preserved only as template)'] += 1
            continue
        excluded = reason(relative)
        if source.is_symlink():
            if str(relative).startswith('.config/systemd/user/') and '.wants/' in str(relative) and source.resolve().is_relative_to(home / '.config/systemd/user'):
                links.append({'target': str(relative), 'link': os.path.relpath(source.resolve(), source.parent)})
            exclusions['symlink (recorded when owned user unit)'] += 1
            continue
        if excluded:
            exclusions[excluded] += 1
            continue
        if not source.is_file() or source.stat().st_size > 2 * 1024**2:
            exclusions['nonregular or over 2 MiB'] += 1
            continue
        try:
            raw = source.read_bytes()
            text = raw.decode('utf-8')
            if '\x00' in text or any(ord(character) < 8 for character in text):
                raise UnicodeError
        except (UnicodeError, OSError):
            exclusions['binary/unreadable'] += 1
            continue
        if str(relative).startswith('.local/bin/') and not text.startswith('#!'):
            exclusions['installed executable'] += 1
            continue
        if str(relative).startswith('.local/bin/') and source.name not in {'9router-local', 'env', 'env.fish', 'archon'}:
            exclusions['installed console entrypoint'] += 1
            continue
        if private_material(text, documentation=source.suffix == '.md'):
            exclusions['private key block'] += 1
            continue
        scrubber.inspect(text, str(relative))
        collected[str(relative)] = (text, bool(source.stat().st_mode & stat.S_IXUSR))
    exported = None if preserve_network else router_export(home)
    if exported:
        scrubber.inspect(exported, '.config/9router/restore.json')
        collected['.config/9router/restore.json'] = (exported, False)
    entries = []
    for relative, (text, executable) in sorted(collected.items()):
        if relative.startswith('.local/bin/'):
            template = 'templates/commands/' + Path(relative).name + '.tmpl'
        else:
            template = 'root/home/user/' + relative + '.tmpl'
        sanitized = scrubber.scrub(text, relative)
        scan_text = MARKER.sub('TEMPLATE_VALUE', sanitized)
        if TOKEN.search(scan_text) or URL_CREDENTIAL.search(scan_text):
            raise ValueError('Unresolved secret pattern in ' + relative)
        destination = output / template
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(sanitized)
        entries.append({'source': template, 'target': relative, 'mode': '0700' if executable else '0600', 'sha256': hashlib.sha256(sanitized.encode()).hexdigest()})
    used = set()
    for entry in entries:
        used.update(MARKER.findall((output / entry['source']).read_text()))
    private_values = {name: value for name, value in scrubber.values.items() if name in used}
    if values_path.exists():
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        private_write(values_path.parent / 'backups' / (stamp + '.json'), values_path.read_text())
    private_write(values_path, json.dumps(private_values, indent=2) + '\n')
    (output / 'templates').mkdir(parents=True, exist_ok=True)
    example = {name: None for name in sorted(used) if name not in {'HOME', 'USER', 'UID', 'GID'}}
    (output / 'templates/values.example.json').write_text(json.dumps(example, indent=2) + '\n')
    manifest = {'format': 1, 'files': entries, 'symlinks': links, 'excluded_file_counts': dict(exclusions), 'excluded_roots': ['.9router/auth', '.9router/db (configuration tables exported separately)', '.9router/logs', '.9router/runtime', '.codex/auth.json', '.codex/sessions', '.codex/memories', '.codex/plugins/cache', '.local/state', '.local/share/hindsight', '.local/share/keyrings', '.local/share/mise', '.local/share/uv', '.hindsight/coding-agents (installed runtime)', '.ssh', '.gnupg', '.cache', '.pi (retired harness)']}
    (output / 'templates/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'templates': len(entries), 'variables': len(example), 'unit_links': len(links), 'excluded_file_counts': dict(exclusions), 'private_values': str(values_path)}, indent=2))


def main():
    parser = argparse.ArgumentParser(description='Capture configuration as secret-free templates; never copy runtime/account databases.')
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--values', type=Path, required=True)
    capture(parser.parse_args())


if __name__ == '__main__':
    main()
