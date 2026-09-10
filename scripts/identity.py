#!/usr/bin/env python3
import argparse
import base64
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile


IMAGE = 'decolua/9router@sha256:47c17576ad49f0918d1a455dd412ae4509ee8bc742f17ba0b3327ddc70f35a40'
TABLES = ('settings', 'providerNodes', 'providerConnections', 'combos', 'apiKeys', 'proxyPools')
ROUTER_FILES = (
    'machine-id', 'jwt-secret', 'auth/cli-secret', 'mitm/rootCA.crt',
    'mitm/rootCA.key', 'mitm/aliases.json',
    'tailscale/certs/ninerouter.tailc28ab1.ts.net.crt',
    'tailscale/certs/ninerouter.tailc28ab1.ts.net.key',
)
TAILSCALE_FILES = (
    'tailscaled.state', 'certs/acme-account.key.pem',
    'certs/koija-pc.tailc28ab1.ts.net.crt', 'certs/koija-pc.tailc28ab1.ts.net.key',
    'certs/ninerouter.tailc28ab1.ts.net.crt', 'certs/ninerouter.tailc28ab1.ts.net.key',
    'ssh/ssh_host_ecdsa_key', 'ssh/ssh_host_ed25519_key', 'ssh/ssh_host_rsa_key',
)
LIMIT = 16 * 1024 * 1024


def bounded_read(path, limit):
    if path.resolve() != path:
        raise ValueError('Symlink input refused')
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('Only regular files are allowed')
        contents = source.read(limit + 1)
    if len(contents) > limit:
        raise ValueError('Input exceeds its size limit')
    return contents


def encode(value):
    contents = json.dumps(value, separators=(',', ':')).encode()
    if len(contents) > LIMIT:
        raise ValueError('Export exceeds its size limit')
    return base64.b64encode(contents).decode()


def router_tables(home):
    database = home / '.9router/db/data.sqlite'
    if database.resolve() != database or not database.is_file():
        raise ValueError('Unexpected database path')
    with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as connection:
        connection.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 1024 * 1024)
        connection.row_factory = sqlite3.Row
        connection.execute('BEGIN')
        records = {}
        for table in TABLES:
            rows = connection.execute('SELECT * FROM "' + table + '" LIMIT 10001').fetchall()
            if len(rows) > 10000:
                raise ValueError('Table exceeds the bounded export')
            records[table] = [dict(row) for row in rows]
    return encode(records)


def tailscale_files():
    program = '''
const fs = require('fs');
const files = JSON.parse(process.argv[1]);
const output = {};
for (const name of files) {
    const path = '/state/' + name;
    if (fs.realpathSync(path) !== path) process.exit(2);
    const descriptor = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const before = fs.fstatSync(descriptor);
    if (!before.isFile() || before.size > 65536) process.exit(2);
    const buffer = Buffer.alloc(65537);
    const length = fs.readSync(descriptor, buffer, 0, buffer.length, 0);
    const contents = buffer.subarray(0, length);
    fs.closeSync(descriptor);
    if (contents.length > 65536) process.exit(2);
    output[name] = contents.toString('base64');
}
process.stdout.write(JSON.stringify(output));
'''
    result = subprocess.run([
        'docker', 'run', '--rm', '--pull', 'never', '--network', 'none', '--read-only',
        '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--log-driver', 'none',
        '--user', '0:0', '--cpus', '1', '--memory', '128m', '--pids-limit', '32',
        '--mount', 'type=bind,src=/var/lib/tailscale,dst=/state,readonly',
        '--entrypoint', 'node', IMAGE, '-e', program, json.dumps(TAILSCALE_FILES),
    ], capture_output=True, check=True, timeout=30)
    if len(result.stdout) > 1024 * 1024:
        raise ValueError('Identity export exceeds its size limit')
    records = json.loads(result.stdout)
    if set(records) != set(TAILSCALE_FILES):
        raise ValueError('Unexpected identity files')
    for value in records.values():
        if len(base64.b64decode(value, validate=True)) > 65536:
            raise ValueError('Identity exceeds its size limit')
    return encode(records)


def capture():
    home = Path.home()
    destination = home / '.config/dotfiles/values.json'
    if any((parent / '.git').exists() for parent in destination.parents):
        raise ValueError('Private destination must be outside Git')
    if destination.resolve() != destination or destination.stat().st_uid != os.getuid():
        raise ValueError('Unexpected private destination')
    if destination.stat().st_mode & 0o077 or destination.parent.stat().st_mode & 0o022:
        raise ValueError('Private destination is not protected')
    with destination.open('rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        original = bounded_read(destination, LIMIT)
        values = json.loads(original)
        values['SECRET_ROUTER_IDENTITY'] = encode({
            name: base64.b64encode(bounded_read(home / '.9router' / name, 65536)).decode()
            for name in ROUTER_FILES
        })
        values['SECRET_ROUTER_TABLES'] = router_tables(home)
        values['SECRET_TAILSCALE_IDENTITY'] = tailscale_files()
        updated = json.dumps(values, indent=2, sort_keys=True).encode() + b'\n'
        if len(updated) > LIMIT:
            raise ValueError('Private values exceed their size limit')
        descriptor, temporary = tempfile.mkstemp(prefix='.values-', dir=destination.parent)
        try:
            with os.fdopen(descriptor, 'wb') as output:
                output.write(updated)
                output.flush()
                os.fsync(output.fileno())
            if bounded_read(destination, LIMIT) != original:
                raise ValueError('Private values changed concurrently')
            os.replace(temporary, destination)
        finally:
            Path(temporary).unlink(missing_ok=True)
    print('Private export complete: 8 router files, 9 Tailscale files and 6 configuration tables. No secret contents printed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Explicitly authorized, fixed-allowlist private identity export; never uploads or writes into Git.')
    parser.add_argument('command', choices=['capture'])
    parser.parse_args()
    try:
        capture()
    except Exception:
        print('Private export failed; existing values preserved unless atomic replacement completed. Details withheld.', file=sys.stderr)
        raise SystemExit(1)
