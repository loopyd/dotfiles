#!/usr/bin/env python3
import base64
import json
import os
from pathlib import Path
import subprocess
import sqlite3


def decode_tables(document):
    if document.get('format') == 2:
        tables = json.loads(base64.b64decode(document['tables'], validate=True))
    elif document.get('format') == 1:
        tables = document['tables']
    else:
        raise ValueError('Unsupported router export format')
    if set(tables) != {'settings', 'providerNodes', 'providerConnections', 'combos', 'apiKeys', 'proxyPools'}:
        raise ValueError('Unexpected router tables')
    return tables


def run(arguments, capture=False, timeout=None):
    return subprocess.run(arguments, check=True, capture_output=capture, text=True, timeout=timeout)


def restore_tables(database, tables):
    decode_tables({'format': 1, 'tables': tables})
    with sqlite3.connect(database) as connection:
        connection.execute('BEGIN IMMEDIATE')
        for table, records in tables.items():
            columns = {row[1] for row in connection.execute('PRAGMA table_info("' + table + '")')}
            if not columns or any(not record or not set(record).issubset(columns) for record in records):
                raise ValueError('Router schema differs from the captured configuration')
            connection.execute('DELETE FROM "' + table + '"')
            for record in records:
                names = ','.join('"' + column.replace('"', '""') + '"' for column in record)
                values = [json.dumps(value) if isinstance(value, (dict, list)) else value for value in record.values()]
                connection.execute('INSERT INTO "' + table + '" (' + names + ') VALUES (' + ','.join('?' for value in values) + ')', values)


def decode_files(document):
    records = json.loads(base64.b64decode(document['files'], validate=True))
    for name, encoded in records.items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe identity path')
        records[name] = base64.b64decode(encoded, validate=True)
    return records


def restore_files(root, records):
    root = root.resolve()
    for name, contents in records.items():
        target = root / name
        if not target.resolve().is_relative_to(root) or target.is_symlink():
            raise ValueError('Identity path escapes its root')
        if target.exists() and target.read_bytes() != contents:
            raise ValueError('Existing identity differs; refusing replacement')
    for name, contents in records.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not target.exists():
            descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(contents)


def installed_helpers(scripts):
    import shutil
    target = Path.home() / '.local/lib/dotfiles'
    target.mkdir(parents=True, exist_ok=True)
    for name in scripts:
        shutil.copy2(Path(__file__).parent / name, target / name)
