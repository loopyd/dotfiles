#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import time
import tempfile
import uuid
from urllib.request import Request, urlopen

from network import decode_files, decode_tables, installed_helpers, restore_files, restore_tables


def config():
    return Path.home() / '.config/9router'


def data():
    return Path.home() / '.9router'


def client():
    values = {}
    for line in (config() / 'client.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"\'')
    return values


def health(port):
    settings = client()
    base = 'http://127.0.0.1:' + str(port)
    headers = {'Authorization': 'Bearer ' + settings['NINEROUTER_KEY']}
    with urlopen(Request(base + '/v1/models', headers=headers), timeout=15) as response:
        models = json.load(response)
    identities = {entry['id'] for entry in models['data']}
    if not {'qwen-combo', 'qwen3-chat/qwen3-embeddings'}.issubset(identities):
        raise ValueError('Required Qwen models missing')
    print(json.dumps({'authenticated_models': len(identities), 'required_qwen_models': True, 'port': port}))


def check(port):
    subprocess.run(['systemctl', '--user', 'is-active', '--quiet', '9router.service'], check=True, capture_output=True)
    inspected = subprocess.run(['docker', 'inspect', '9router'], check=True, capture_output=True, text=True)
    container = json.loads(inspected.stdout)[0]
    compose = subprocess.run(['docker', 'compose', '--file', str(config() / 'compose.yaml'), 'config', '--format', 'json'], check=True, capture_output=True, text=True)
    expected = json.loads(compose.stdout)['services']['router']['image']
    image = subprocess.run(['docker', 'image', 'inspect', expected, '--format', '{{.Id}}'], check=True, capture_output=True, text=True)
    if not container['State']['Running'] or container['Image'] != image.stdout.strip():
        raise ValueError('Managed router container or image differs')
    limits = container['HostConfig']
    if limits['NanoCpus'] != 2000000000 or limits['ShmSize'] != 4294967296 or limits['NetworkMode'] != 'host':
        raise ValueError('Managed router limits or networking differ')
    if not any(mount['Source'] == str(data()) and mount['Destination'] == '/app/data' for mount in container['Mounts']):
        raise ValueError('Managed router persistent storage differs')
    health(port)
    print('Managed router unit, image, storage, host network and resource limits verified')


def copy_database(source, target):
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    with sqlite3.connect('file:' + str(source) + '?mode=ro', uri=True) as original:
        with sqlite3.connect(target) as destination:
            original.backup(destination, pages=4096, sleep=0.1)
    target.chmod(0o600)


def prepare():
    for name in ['compose.yaml', 'runtime.env', 'client.env']:
        if not (config() / name).is_file():
            raise ValueError('Render the router configuration first')
    identity = config() / 'identity.json'
    if identity.exists() and not (data() / 'db/data.sqlite').exists():
        restore_files(data(), decode_files(json.loads(identity.read_text())))
    (data() / 'tailscale').mkdir(parents=True, exist_ok=True)
    link = data() / 'tailscale/tailscaled.sock'
    if link.is_symlink() and os.readlink(link) != '/run/tailscale/tailscaled.sock':
        raise ValueError('Unexpected Tailscale socket link')
    if not link.is_symlink():
        if link.exists():
            raise ValueError('Tailscale socket path is occupied')
        link.symlink_to('/run/tailscale/tailscaled.sock')
    installed_helpers(['router.py', 'network.py'])


def initialize():
    database = data() / 'db/data.sqlite'
    if database.exists():
        return
    tables = decode_tables(json.loads((config() / 'restore.json').read_text()))
    compose = subprocess.run(['docker', 'compose', '--file', str(config() / 'compose.yaml'), 'config', '--format', 'json'], capture_output=True, check=True, text=True)
    image = json.loads(compose.stdout)['services']['router']['image']
    state = Path.home() / '.local/state/9router'
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='initialize-', dir=state) as temporary:
        root = Path(temporary)
        container = '9router-initialize-' + uuid.uuid4().hex
        try:
            subprocess.run([
                'docker', 'run', '--detach', '--name', container, '--pull', 'never',
                '--network', 'none', '--log-driver', 'none', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges', '--cpus', '2', '--shm-size', '4g',
                '--user', str(os.getuid()) + ':' + str(os.getgid()),
                '--env', 'DATA_DIR=/app/data', '--env', 'HOME=/home/node',
                '--env', 'HOSTNAME=127.0.0.1', '--env', 'PORT=20128',
                '--mount', 'type=bind,src=' + str(root) + ',dst=/app/data',
                '--mount', 'type=bind,src=' + str(root) + ',dst=/home/node/.9router',
                '--entrypoint', 'node', image, 'custom-server.js',
            ], check=True, capture_output=True)
            for attempt in range(60):
                status = subprocess.run(['docker', 'exec', container, 'node', '-e', "fetch('http://127.0.0.1:20128/v1/models').then(response=>process.exit(response.ok||response.status===401?0:1)).catch(()=>process.exit(1))"], capture_output=True, timeout=10)
                if status.returncode == 0 and (root / 'db/data.sqlite').exists():
                    break
                time.sleep(1)
            else:
                raise ValueError('Isolated database initialization failed')
        finally:
            subprocess.run(['docker', 'stop', '--time', '15', container], capture_output=True)
            subprocess.run(['docker', 'rm', '--force', container], capture_output=True, check=True)
        restore_tables(root / 'db/data.sqlite', tables)
        (root / 'db').chmod(0o700)
        (root / 'db/data.sqlite').chmod(0o600)
        if database.parent.exists():
            raise ValueError('Database destination appeared during initialization')
        (root / 'db').rename(database.parent)
    print('Database initialized offline and captured credentials restored before exposure')


def restore():
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 20128)) == 0:
            raise ValueError('Stop 9router before restoring tables')
    database = data() / 'db/data.sqlite'
    if not database.exists():
        raise ValueError('Initialize the container database first')
    tables = decode_tables(json.loads((config() / 'restore.json').read_text()))
    backup = Path.home() / '.local/state/9router' / ('before-restore-' + str(time.time_ns()) + '.sqlite')
    copy_database(database, backup)
    restore_tables(database, tables)
    print('Captured configuration and credentials restored transactionally; backup retained privately')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['prepare', 'initialize', 'restore', 'health', 'check', 'ready', 'wait'])
    parser.add_argument('--port', type=int, default=20128)
    args = parser.parse_args()
    if args.command == 'ready':
        if subprocess.run(['systemctl', '--user', 'is-active', '--quiet', '9router.service']).returncode != 0:
            with socket.socket() as probe:
                if probe.connect_ex(('127.0.0.1', args.port)) == 0:
                    raise ValueError('Existing gateway owns the port; plan and rehearse its shutdown before activating the unit')
    elif args.command == 'wait':
        for attempt in range(30):
            try:
                health(args.port)
                return
            except Exception:
                time.sleep(2)
        raise ValueError('Gateway did not become healthy')
    elif args.command == 'check':
        check(args.port)
    elif args.command == 'health':
        health(args.port)
    else:
        {'prepare': prepare, 'initialize': initialize, 'restore': restore}[args.command]()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Router operation failed; verify configuration, database state and service availability. Private details withheld.', file=sys.stderr)
        raise SystemExit(1)
