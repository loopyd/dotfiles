#!/usr/bin/env python3
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import tempfile
import time
import uuid
from urllib.request import Request, urlopen

from network import installed_helpers


def execute(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True)


def configuration():
    directory = Path.home() / '.config/easyllama'
    deployment = json.loads((directory / 'deployment.json').read_text())
    if deployment['version'] != '0.6.0' or deployment['revision'] != '94166edbd5e74a9e89741d889483b12bdb82907c':
        raise ValueError('Unexpected EasyLlama release pin')
    command = ['docker', 'compose', '--project-name', 'easyllama', '--file', str(directory / 'compose.yaml')]
    services = json.loads(execute([*command, 'config', '--format', 'json']).stdout)['services']
    if set(services) != {'proxy', 'chat', 'embeddings'} or set(deployment['images']) != set(services):
        raise ValueError('Unexpected EasyLlama service set')
    for role, service in services.items():
        if service['image'] != deployment['images'][role]['id'] or service.get('network_mode') != 'host' or service.get('ports'):
            raise ValueError('EasyLlama image or network differs')
        service['environment'] = {key: value.replace('$$', '$') for key, value in service['environment'].items()}
        service['command'] = [value.replace('$$', '$') for value in service['command']]
    return directory, deployment, services, command


def images(directory=None):
    _config, deployment, _services, _command = configuration()
    for pin in {value['id']: value for value in deployment['images'].values()}.values():
        result = subprocess.run(['docker', 'image', 'inspect', pin['id'], '--format', '{{.Id}}'], capture_output=True, text=True)
        if result.returncode and directory is not None:
            archive = directory / pin['archive']
            if archive.resolve().parent != directory.resolve() or not archive.is_file() or archive.is_symlink():
                raise ValueError('Missing or unsafe local image archive')
            execute(['docker', 'load', '--input', str(archive)])
            result = subprocess.run(['docker', 'image', 'inspect', pin['id'], '--format', '{{.Id}}'], capture_output=True, text=True)
        if result.returncode or result.stdout.strip() != pin['id']:
            raise ValueError('Pinned local image unavailable; restore its private archive first')


def archive(directory):
    images()
    _config, deployment, _services, _command = configuration()
    if any((parent / '.git').exists() for parent in [directory, *directory.parents]):
        raise ValueError('Keep image archives outside Git')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    for pin in {value['id']: value for value in deployment['images'].values()}.values():
        target = directory / pin['archive']
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, 'wb') as output:
                subprocess.run(['docker', 'save', pin['id']], stdout=output, stderr=subprocess.PIPE, check=True)
        except BaseException:
            target.unlink(missing_ok=True)
            raise
    print('Pinned image archives saved privately; no models or container environment exported')


def prepare():
    directory, deployment, services, _command = configuration()
    root = Path(deployment['root'])
    if not root.is_absolute() or root.resolve() != root or not root.is_dir():
        raise ValueError('Create the configured EasyLlama data root first')
    copies = {'proxy.yaml': '.runtime/qwen.proxy.effective.yaml'}
    copies.update({'chat_template/' + name: 'chat_template/' + name for name in ['qwen3.5.jinja', 'qwen3.6.jinja', 'qwen3.8.jinja']})
    for source, relative in copies.items():
        target = root / relative
        contents = (directory / source).read_bytes()
        if source.startswith('chat_template/'):
            pin = deployment['chat_templates'][Path(source).name]
            if not pin['final_newline'] and contents.endswith(b'\n'):
                contents = contents[:-1]
            if hashlib.sha256(contents).hexdigest() != pin['sha256']:
                raise ValueError('Captured chat template differs from its pin')
        if target.resolve() != target or target.exists() and target.read_bytes() != contents:
            raise ValueError('Existing runtime configuration differs; refusing replacement')
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as output:
                output.write(contents)
    for service in services.values():
        for mount in service['volumes']:
            source = Path(mount['source'])
            if source.is_relative_to(root) and not source.exists():
                source.mkdir(parents=True, mode=0o700)
            if not source.exists():
                raise ValueError('A captured bind mount is unavailable')
    installed_helpers(['easyllama.py', 'network.py', 'readiness.py'])


def containers(services):
    result = []
    for role, service in services.items():
        inspected = subprocess.run(['docker', 'container', 'inspect', service['container_name']], capture_output=True, text=True)
        if inspected.returncode:
            names = execute(['docker', 'container', 'ls', '--all', '--format', '{{.Names}}']).stdout.splitlines()
            if service['container_name'] in names:
                raise ValueError('Existing container cannot be inspected')
            continue
        container = json.loads(inspected.stdout)[0]
        expected = execute(['docker', 'image', 'inspect', service['image'], '--format', '{{.Id}}']).stdout.strip()
        config, host = container['Config'], container['HostConfig']
        if container['Image'] != expected or config.get('Labels', {}).get('easyllama.managed') != 'true':
            raise ValueError('Refusing an unrelated or differently pinned container')
        if (config.get('Entrypoint') or []) != (service.get('entrypoint') or []) or config['Cmd'] != service['command']:
            raise ValueError('Existing container command differs')
        if dict(entry.split('=', 1) for entry in config['Env']) != service['environment']:
            raise ValueError('Existing container environment differs')
        limits = [('NanoCpus', int(float(service['cpus']) * 1e9)), ('Memory', int(service['mem_limit'])), ('MemorySwap', int(service['memswap_limit'])), ('ShmSize', int(service['shm_size'])), ('PidsLimit', int(service['pids_limit'])), ('NetworkMode', 'host')]
        if any(host[key] != value for key, value in limits):
            raise ValueError('Existing container limits differ')
        devices = host.get('DeviceRequests') or []
        if service.get('runtime') == 'nvidia' and (host['Runtime'] != 'nvidia' or len(devices) != 1 or devices[0]['Count'] != -1 or devices[0].get('DeviceIDs') or devices[0].get('Driver') not in {'', 'nvidia'} or devices[0]['Capabilities'] != [['gpu']]):
            raise ValueError('Existing GPU runtime or device request differs')
        if host.get('Privileged') or host.get('SecurityOpt') != service.get('security_opt'):
            raise ValueError('Existing container security differs')
        actual = {(mount['Source'], mount['Destination'], not mount['RW']) for mount in container['Mounts']}
        expected_mounts = {(mount['source'], mount['target'], mount.get('read_only', False)) for mount in service['volumes']}
        if actual != expected_mounts:
            raise ValueError('Existing container mounts differ')
        result.append((role, container))
    return result


def health():
    directory, _deployment, _services, _command = configuration()
    key = json.loads((directory / 'config.json').read_text())['credentials']['api_key']
    with urlopen(Request('http://127.0.0.1:8080/v1/models', headers={'Authorization': 'Bearer ' + key}), timeout=15) as response:
        models = {entry['id'] for entry in json.load(response)['data']}
    if not {'qwen3-chat', 'qwen3-embeddings'}.issubset(models):
        raise ValueError('Captured Qwen models missing')


def check():
    _directory, _deployment, services, _command = configuration()
    images()
    observed = containers(services)
    if len(observed) != 3 or any(not container['State']['Running'] for _role, container in observed):
        raise ValueError('EasyLlama stack is not running')
    health()
    print('Three pinned EasyLlama containers, captured limits/mounts and authenticated Qwen discovery verified')


def wait():
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        try:
            if not ownership().exists():
                raise ValueError('Adoption has not committed')
            state = json.loads(ownership().read_text())
            if state['phase'] != 'committed' or state['invocation'] != os.environ.get('INVOCATION_ID'):
                raise ValueError('Readiness belongs to a different invocation')
            _directory, _deployment, services, _command = configuration()
            same_owners(state, containers(services))
            check()
            return
        except Exception:
            time.sleep(2)
    raise ValueError('EasyLlama startup readiness timed out')


def ownership():
    return Path.home() / '.local/state/easyllama/ownership.json'


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_state(destination, document):
    descriptor, temporary = tempfile.mkstemp(prefix='.state-', dir=destination.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(document, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
        sync_directory(destination.parent)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextlib.contextmanager
def locked():
    path = ownership()
    missing = []
    parent = path.parent
    while not parent.exists():
        missing.append(parent)
        parent = parent.parent
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent.resolve() != path.parent:
        raise ValueError('Unexpected ownership directory')
    for directory in reversed(missing):
        sync_directory(directory.parent)
        sync_directory(directory)
    descriptor = os.open(path.with_suffix('.lock'), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def inspect_owned(record):
    result = subprocess.run(['docker', 'inspect', record['id']], capture_output=True, text=True)
    if result.returncode:
        identifiers = execute(['docker', 'container', 'ls', '--all', '--no-trunc', '--format', '{{.ID}}']).stdout.splitlines()
        if record['id'] in identifiers:
            raise ValueError('Owned container cannot be inspected')
        return None
    container = json.loads(result.stdout)[0]
    if container['Id'] != record['id'] or container['Image'] != record['image'] or container['Config'].get('Labels', {}).get('easyllama.managed') != 'true':
        raise ValueError('Owned container identity differs')
    return container


def stop_owned(records):
    failed = False
    for record in sorted(records, key=lambda entry: ['proxy', 'chat', 'embeddings'].index(entry['role'])):
        try:
            if inspect_owned(record) is not None:
                execute(['docker', 'stop', '--time', '60', record['id']])
        except Exception:
            failed = True
    if failed:
        raise ValueError('One or more owned containers could not be stopped')


def rollback(records, original):
    failed = False
    for record in records:
        try:
            container = inspect_owned(record)
            previous = original.get(record['role'])
            if container is None:
                if previous is not None:
                    raise ValueError('Original container disappeared during adoption')
                continue
            if previous is None or not previous['running']:
                stop_owned([record])
            if previous is not None:
                policy = previous['restart']
                value = policy['Name']
                if value == 'on-failure' and policy.get('MaximumRetryCount'):
                    value += ':' + str(policy['MaximumRetryCount'])
                execute(['docker', 'update', '--restart=' + value, record['id']])
                if previous['running'] and not container['State']['Running']:
                    execute(['docker', 'start', record['id']])
        except Exception:
            failed = True
    if failed:
        raise ValueError('Adoption rollback needs attention; journal retained')


def discover_created(state):
    known = {record['id'] for record in state['records']}
    identifiers = execute(['docker', 'container', 'ls', '--all', '--no-trunc', '--filter', 'label=dotfiles.easyllama.transaction=' + state['invocation'], '--format', '{{.ID}}']).stdout.splitlines()
    for identifier in identifiers:
        if identifier in known:
            continue
        container = json.loads(execute(['docker', 'inspect', identifier]).stdout)[0]
        role = container['Config'].get('Labels', {}).get('com.docker.compose.service')
        plan = state['planned'].get(role)
        if plan is None or container['Image'] != plan['image'] or container['Name'].lstrip('/') != plan['name']:
            raise ValueError('Unexpected transaction container; journal retained')
        state['records'].append({'role': role, 'id': identifier, 'image': container['Image']})
    write_state(ownership(), state)


def cleanup(state):
    if state['phase'] == 'adopting':
        discover_created(state)
        rollback(state['records'], state['original'])
    elif state['phase'] == 'committed':
        stop_owned(state['records'])
    else:
        raise ValueError('Unknown ownership phase')
    if json.loads(ownership().read_text())['invocation'] != state['invocation']:
        raise ValueError('Ownership changed during cleanup')
    ownership().unlink()
    (ownership().parent / ('compose-' + state['invocation'] + '.json')).unlink(missing_ok=True)
    sync_directory(ownership().parent)


def stop():
    with locked():
        if ownership().exists():
            state = json.loads(ownership().read_text())
            invocation = os.environ.get('INVOCATION_ID')
            if invocation and invocation != state['invocation']:
                raise ValueError('Cleanup invocation differs; journal retained')
            cleanup(state)


def same_owners(state, observed):
    expected = {record['role']: record['id'] for record in state['records']}
    if {role: container['Id'] for role, container in observed} != expected:
        raise ValueError('Owned container was replaced')


def supervise():
    if ownership().exists():
        cleanup(json.loads(ownership().read_text()))
    _directory, _deployment, services, command = configuration()
    images()
    observed = dict(containers(services))
    invocation = os.environ.get('INVOCATION_ID') or uuid.uuid4().hex
    if not re.fullmatch(r'[a-fA-F0-9]{32}', invocation):
        raise ValueError('Unexpected service invocation')
    state = {
        'invocation': invocation, 'phase': 'adopting',
        'records': [{'role': role, 'id': container['Id'], 'image': container['Image']} for role, container in observed.items()],
        'original': {role: {'running': container['State']['Running'], 'restart': container['HostConfig']['RestartPolicy']} for role, container in observed.items()},
        'planned': {role: {'name': service['container_name'], 'image': service['image']} for role, service in services.items() if role not in observed},
    }
    write_state(ownership(), state)
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda _signal, _frame: stopping.set())
    signal.signal(signal.SIGINT, lambda _signal, _frame: stopping.set())
    try:
        override = ownership().parent / ('compose-' + invocation + '.json')
        write_state(override, {'services': {role: {'labels': {'dotfiles.easyllama.transaction': invocation}} for role in services}})
        for role in ['chat', 'embeddings', 'proxy']:
            if stopping.is_set():
                return
            if role not in observed:
                execute([*command, '--file', str(override), 'up', '--no-start', '--no-deps', '--no-build', '--pull', 'never', role])
                discover_created(state)
            record = next(entry for entry in state['records'] if entry['role'] == role)
            container = inspect_owned(record)
            if container is None:
                raise ValueError('Verified container disappeared')
            execute(['docker', 'update', '--restart=no', record['id']])
            if not container['State']['Running']:
                execute(['docker', 'start', record['id']])
        for attempt in range(60):
            if stopping.is_set():
                return
            try:
                health()
                break
            except Exception:
                stopping.wait(2)
        else:
            raise ValueError('EasyLlama endpoint did not become healthy')
        if len(state['records']) != 3:
            raise ValueError('Could not establish ownership of the full stack')
        current = containers(services)
        same_owners(state, current)
        if any(not container['State']['Running'] for _role, container in current):
            raise ValueError('An EasyLlama owner stopped before adoption committed')
        committed = dict(state, phase='committed')
        write_state(ownership(), committed)
        state = committed
        while not stopping.wait(10):
            current = containers(services)
            same_owners(state, current)
            if any(not container['State']['Running'] for _role, container in current):
                raise ValueError('An EasyLlama container stopped')
    finally:
        cleanup(state)


def run():
    with locked():
        supervise()


def main():
    parser = argparse.ArgumentParser(description='Pinned EasyLlama Docker lifecycle; never builds floating source or removes model data')
    parser.add_argument('command', choices=['prepare', 'images', 'archive', 'run', 'stop', 'check', 'health', 'wait'])
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args()
    if args.command == 'archive':
        if args.directory is None:
            parser.error('archive requires --directory outside Git')
        archive(args.directory.resolve())
    elif args.command == 'images':
        images(args.directory)
    else:
        {'prepare': prepare, 'run': run, 'stop': stop, 'check': check, 'health': health, 'wait': wait}[args.command]()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('EasyLlama operation failed; check private rendering, exact local images, Docker/GPU availability and captured mounts. Details withheld.', file=sys.stderr)
        raise SystemExit(1)
