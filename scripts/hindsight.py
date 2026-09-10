#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request


def require(condition, message):
    if not condition:
        raise ValueError(message)


def configuration():
    home = Path.home()
    root = home / '.config/hindsight'
    credentials = json.loads((root / 'credentials.json').read_text())
    plugin = json.loads((home / '.hindsight/coding-agent.json').read_text())
    cli = tomllib.loads((home / '.hindsight/config').read_text())
    environment = dict(line.split('=', 1) for line in (root / 'server.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    key = credentials['api_key']
    dashboard_key = credentials['dashboard_access_key']
    require(all(isinstance(value, str) and len(value) >= 32 and '@@DOTFILES:' not in value for value in [key, dashboard_key]), 'Render private credentials first')
    require(key != dashboard_key, 'API and dashboard keys must be distinct')
    require(key == plugin.get('apiToken') == cli.get('api_key') == environment.get('HINDSIGHT_API_TENANT_API_KEY') == environment.get('HINDSIGHT_API_MCP_AUTH_TOKEN') == environment.get('HINDSIGHT_CP_DATAPLANE_API_KEY'), 'API client/server credential mismatch')
    require(dashboard_key == environment.get('HINDSIGHT_CP_ACCESS_KEY'), 'Dashboard credential mismatch')
    require(environment.get('HINDSIGHT_API_TENANT_EXTENSION') == 'hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension', 'API authentication must be enabled')
    require(environment.get('HINDSIGHT_API_TENANT_MCP_AUTH_DISABLED', 'false') == 'false', 'MCP authentication must remain enabled')
    require(environment.get('HINDSIGHT_API_HOST') == '127.0.0.1' and environment.get('HINDSIGHT_CP_HOSTNAME') == 'localhost', 'Keep API and dashboard loopback-only')
    require(plugin.get('bankId') == 'shared' and plugin.get('dynamicBankId') is False, 'Keep the shared memory bank')
    require(plugin.get('apiUrl') == cli.get('api_url') == environment.get('HINDSIGHT_CP_DATAPLANE_API_URL') == 'http://127.0.0.1:8888', 'Local API URLs must agree')
    return home, key


def preflight():
    home, _key = configuration()
    paths = ['.config/hindsight/compose.yaml', '.config/hindsight/postgres.env', '.config/hindsight/initdb/10-hindsight.sql', '.config/systemd/user/hindsight.service', '.config/systemd/user/hindsight-db.service', '.codex/config.toml', '.codex/hooks.json', '.agents/skills/hindsight-docs/SKILL.md', '.agents/skills/hindsight-coding-agent/SKILL.md']
    for relative in paths:
        path = home / relative
        require(path.is_file() and '@@DOTFILES:' not in path.read_text(), 'Missing/unrendered file: ' + relative)
    codex = tomllib.loads((home / '.codex/config.toml').read_text())
    require(codex.get('features', {}).get('hooks') is True, 'Restore Codex hook configuration first')
    result = subprocess.run(['docker', 'compose', '--project-name', 'hindsight', '--file', str(home / '.config/hindsight/compose.yaml'), 'config', '--format', 'json'], capture_output=True)
    require(result.returncode == 0, 'Rendered Docker Compose configuration is invalid')
    services = json.loads(result.stdout)['services']
    for name in ['database', 'app']:
        service = services[name]
        require(re.fullmatch(r'ghcr.io/[\w./-]+@sha256:[0-9a-f]{64}', service['image']), 'Container images must use pinned GHCR digests')
        require(service.get('network_mode') == 'host' and not service.get('ports'), 'Preserve host networking without published ports')
    for relative in ['.local/share/hindsight/postgres', '.local/share/hindsight/cache']:
        require((home / relative).is_dir(), 'Render persistent directory first: ' + relative)
    print('Rendered authentication, shared-bank routing, unit files and pinned Compose configuration validated')


def health():
    _home, key = configuration()
    checks = [('http://127.0.0.1:8888/v1/default/banks', key, 200), ('http://127.0.0.1:8888/v1/default/banks', None, 401), ('http://127.0.0.1:9999/api/list', None, 401)]
    for attempt in range(60):
        healthy = True
        for url, token, expected in checks:
            headers = {'Authorization': 'Bearer ' + token} if token else {}
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=3) as response:
                    status = response.status
            except urllib.error.HTTPError as error:
                status = error.code
            except (OSError, urllib.error.URLError):
                status = None
            healthy = healthy and status == expected
        if healthy:
            print('Authenticated API is ready; anonymous API and dashboard data requests are rejected')
            return
        if attempt < 59:
            time.sleep(2)
    raise ValueError('Hindsight did not become healthy/authenticated; inspect user service logs (no credentials printed)')


def runtime(minimum):
    root = Path.home() / '.hindsight/coding-agents'
    path = root / 'package.json'
    if not path.exists():
        return False
    version = json.loads(path.read_text()).get('version', '')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        return False
    return tuple(map(int, version.split('.'))) >= tuple(map(int, minimum.split('.'))) and all((root / 'dist' / name).is_file() for name in ['installer.js', 'mcp-server.js', 'codex-hook.js'])


def main():
    parser = argparse.ArgumentParser(description='Non-secret Hindsight installer validation')
    parser.add_argument('command', choices=['preflight', 'health', 'runtime'])
    parser.add_argument('--minimum', default='0.5.3')
    args = parser.parse_args()
    try:
        if args.command == 'runtime':
            return 0 if runtime(args.minimum) else 1
        if args.command == 'preflight':
            preflight()
        else:
            health()
    except (OSError, ValueError, KeyError, TypeError):
        print('Hindsight validation failed: verify rendered credentials, prerequisites and local services; private details withheld', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
