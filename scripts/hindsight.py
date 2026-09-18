#!/usr/bin/env python3
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.error
import urllib.request

sys.dont_write_bytecode = True

from dotfiles import beneath, materialize
from snapshot import private_write


REPO = Path(__file__).resolve().parents[1]
IMAGE_ID = r'sha256:[0-9a-f]{64}'


def build_recipe():
    recipe = json.loads((REPO / 'root/home/user/.config/hindsight/build.json').read_text())
    validate_recipe(recipe)
    return recipe


def validate_recipe(recipe):
    require(recipe.get('format') == 1, 'Unsupported build recipe')
    require(recipe.get('source') == 'https://github.com/vectorize-io/hindsight', 'Only official upstream source is supported')
    require(re.fullmatch(r'[0-9a-f]{40}', recipe['commit']), 'Full upstream commit required')
    require(recipe.get('dockerfile') == 'docker/standalone/Dockerfile' and recipe.get('target') == 'standalone', 'Use the upstream standalone Dockerfile')
    require(recipe.get('build_args') == {'PRELOAD_ML_MODELS': 'false', 'INCLUDE_LOCAL_MODELS': 'true'}, 'Preserve local ML dependencies without preloading models')
    require(recipe.get('tag') == 'dotfiles/hindsight:' + recipe['commit'][:12], 'Use an honest local image tag')


def image_details(reference):
    result = subprocess.run(['docker', 'image', 'inspect', reference], capture_output=True)
    if result.returncode:
        return None
    return json.loads(result.stdout)[0]


def verify_image(details, recipe, image_id):
    require(re.fullmatch(IMAGE_ID, image_id), 'Immutable Docker image ID required')
    require(details and details.get('Id') == image_id, 'Local image does not match its receipt')
    labels = details.get('Config', {}).get('Labels') or {}
    require(labels.get('org.opencontainers.image.source') == recipe['source'], 'Image source label mismatch')
    require(labels.get('org.opencontainers.image.revision') == recipe['commit'], 'Image revision label mismatch')


def receipt_path():
    return beneath(Path.home(), '.local/state/dotfiles/hindsight-build.json')


def load_receipt(recipe=None):
    path = receipt_path()
    require(not path.is_symlink(), 'Build receipt must not be a symlink')
    receipt = json.loads(path.read_text())
    require(receipt.get('format') == 1, 'Unsupported build receipt')
    validate_recipe(receipt['recipe'])
    require(recipe is None or receipt['recipe'] == recipe, 'Build receipt must match the complete recipe')
    require(receipt.get('source_verified') is True and re.fullmatch(r'[0-9a-f]{40}', receipt['source_tree']), 'Verified source receipt required')
    require(receipt.get('method') in {'build', 'operator-adoption'}, 'Unsupported receipt provenance')
    require(re.fullmatch(IMAGE_ID, receipt['image_id']), 'Invalid receipt image ID')
    return receipt


def compose_services(home, text=None):
    command = ['docker', 'compose', '--project-name', 'hindsight', '--project-directory', str(home / '.config/hindsight'), '--file', '-' if text is not None else str(home / '.config/hindsight/compose.yaml'), 'config', '--format', 'json']
    result = subprocess.run(command, input=text, text=True, capture_output=True)
    require(result.returncode == 0, 'Rendered Docker Compose configuration is invalid')
    return json.loads(result.stdout)['services']


def verify_services(services):
    for name in ['database', 'app']:
        service = services[name]
        image = service['image']
        if name == 'app':
            require(re.fullmatch(IMAGE_ID, image), 'Compose app must use a receipted immutable local image ID')
            recipe = build_recipe()
            receipt = load_receipt(recipe)
            require(receipt['image_id'] == image, 'Compose app must match the verified build receipt')
            verify_image(image_details(image), recipe, image)
        else:
            require(re.fullmatch(r'ghcr.io/[\w./-]+@sha256:[0-9a-f]{64}', image), 'Database image must use a pinned GHCR digest')
        require(service.get('network_mode') == 'host' and not service.get('ports'), 'Preserve host networking without published ports')


def atomic_private_write(path, text):
    require(not path.is_symlink(), 'Refusing a symlink destination')
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='.hindsight-', dir=path.parent) as temporary:
        staged = Path(temporary) / 'file'
        private_write(staged, text)
        os.replace(staged, path)


def source_command(source, *arguments):
    result = subprocess.run(['git', '-C', str(source), *arguments], capture_output=True, env={**os.environ, 'GIT_NO_REPLACE_OBJECTS': '1', 'GIT_OPTIONAL_LOCKS': '0'})
    require(result.returncode == 0, 'Upstream source verification failed')
    return result.stdout.decode().strip()


def verified_source(recipe, fetch):
    source = beneath(Path.home(), '.cache/dotfiles/hindsight/' + recipe['commit'])
    require(not source.is_symlink(), 'Source checkout must not be a symlink')
    if source.exists():
        return source, verify_checkout(source, recipe)
    require(fetch, 'Adoption requires the existing verified source checkout')
    source.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='.' + recipe['commit'] + '-', dir=source.parent) as temporary:
        checkout = Path(temporary) / 'source'
        checkout.mkdir(mode=0o700)
        source_command(checkout, 'init')
        source_command(checkout, 'remote', 'add', 'origin', recipe['source'])
        source_command(checkout, '-c', 'core.hooksPath=/dev/null', 'fetch', '--depth=1', 'origin', recipe['commit'])
        source_command(checkout, '-c', 'core.hooksPath=/dev/null', 'checkout', '--detach', recipe['commit'])
        tree = verify_checkout(checkout, recipe)
        require(not source.exists() and not source.is_symlink(), 'Source checkout appeared during fetch; retry verification')
        os.rename(checkout, source)
    return source, tree


def verify_checkout(source, recipe):
    require((source / '.git').is_dir() and not (source / '.git').is_symlink(), 'Dedicated Git checkout required')
    if 'origin' in source_command(source, 'remote').splitlines():
        require(source_command(source, 'config', '--get', 'remote.origin.url') in {recipe['source'], recipe['source'] + '.git'}, 'Unexpected upstream remote')
    require(source_command(source, 'rev-parse', 'HEAD') == recipe['commit'], 'Source HEAD differs from pinned commit')
    require(not source_command(source, 'status', '--porcelain', '--untracked-files=all', '--ignored'), 'Source checkout must be unmodified')
    tree = source_command(source, 'rev-parse', recipe['commit'] + '^{tree}')
    require(re.fullmatch(r'[0-9a-f]{40}', tree), 'Invalid source tree')
    return tree


def render_image(image_id):
    home = Path.home()
    values_path = beneath(home, '.config/dotfiles/values.json')
    target = beneath(home, '.config/hindsight/compose.yaml')
    require(not values_path.is_symlink() and not target.is_symlink(), 'Refusing symlink configuration')
    original = values_path.read_text()
    original_compose = target.read_text() if target.exists() else None
    values = json.loads(original)
    values['HINDSIGHT_IMAGE'] = image_id
    template = (REPO / 'root/home/user/.config/hindsight/compose.yaml.tmpl').read_text()
    require('@@DOTFILES:HINDSIGHT_IMAGE@@' in template, 'Compose template must use HINDSIGHT_IMAGE')
    substitutions = {**values, 'HOME': str(home), 'USER': home.name, 'UID': str(os.getuid()), 'GID': str(os.getgid())}
    rendered = materialize(template, substitutions, target)
    services = compose_services(home, rendered)
    require(services['app']['image'] == image_id, 'Rendered app image mismatch')
    verify_services(services)
    try:
        atomic_private_write(values_path, json.dumps(values, indent=2) + '\n')
        atomic_private_write(target, rendered)
    except BaseException:
        if original_compose is None:
            target.unlink(missing_ok=True)
        else:
            atomic_private_write(target, original_compose)
        atomic_private_write(values_path, original)
        raise


def build_image(args):
    recipe = build_recipe()
    if args.dry_run:
        print('DRY-RUN: verify/reuse the pinned upstream image or build it, write its receipt, update private HINDSIGHT_IMAGE and render only Hindsight compose.yaml; no services or bank changes')
        return
    require(os.geteuid() != 0, 'Run as the destination user')
    configuration()
    require(subprocess.run(['docker', 'info'], capture_output=True).returncode == 0, 'Docker must already be available to this user')
    state = receipt_path().parent
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = state / 'hindsight-build.lock'
    require(not lock.is_symlink(), 'Refusing a symlink lock')
    with lock.open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        receipt = receipt_path()
        require(not receipt.is_symlink(), 'Build receipt must not be a symlink')
        original_receipt = receipt.read_text() if receipt.exists() else None
        try:
            image_id = ensure_image(recipe, args)
            render_image(image_id)
        except BaseException:
            if original_receipt is None:
                receipt.unlink(missing_ok=True)
            elif not receipt.exists() or receipt.read_text() != original_receipt:
                atomic_private_write(receipt, original_receipt)
            raise
    print('Verified pinned upstream image: ' + image_id)
    print('Build receipt saved; private image value and Hindsight Compose updated; no services or banks changed')


def ensure_image(recipe, args):
    previous = load_receipt() if receipt_path().exists() else None
    previous_text = receipt_path().read_text() if previous is not None else None
    if args.adopt_iidfile is None and previous is not None and previous['recipe'] == recipe:
        image_id = previous['image_id']
        details = image_details(image_id)
        if details is None and args.archive:
            require(subprocess.run(['docker', 'image', 'load', '--input', str(args.archive)], capture_output=True).returncode == 0, 'Local archive recovery failed')
            details = image_details(image_id)
        if details is not None:
            verify_image(details, recipe, image_id)
            return image_id
        require(not args.archive, 'Archive does not contain the receipted image')
    else:
        require(not args.archive, 'Archive recovery requires a verified receipt matching the current recipe')
    source, tree = verified_source(recipe, fetch=args.adopt_iidfile is None)
    if args.adopt_iidfile:
        image_id = args.adopt_iidfile.read_text().strip()
        require(re.fullmatch(IMAGE_ID, image_id), 'Immutable Docker image ID required')
        verify_image(image_details(recipe['tag']), recipe, image_id)
        method = 'operator-adoption'
    else:
        if image_details(recipe['tag']) is not None:
            print('An unreceipted local tag exists. Use build-image --adopt-iidfile only after verifying that build used the exact recipe.', file=sys.stderr)
            raise ValueError('Explicit build adoption required')
        print('Building the unmodified pinned upstream Git archive')
        with tempfile.TemporaryDirectory(prefix='hindsight-build-', dir=receipt_path().parent) as temporary:
            archive = Path(temporary) / 'source.tar'
            iidfile = Path(temporary) / 'image-id'
            source_command(source, 'archive', '--format=tar', '--output=' + str(archive), recipe['commit'])
            command = ['docker', 'build', '--file', recipe['dockerfile'], '--target', recipe['target'], '--tag', recipe['tag'], '--iidfile', str(iidfile), '--label', 'org.opencontainers.image.source=' + recipe['source'], '--label', 'org.opencontainers.image.revision=' + recipe['commit']]
            for name, value in recipe['build_args'].items():
                command.extend(['--build-arg', name + '=' + value])
            with archive.open('rb') as context:
                require(subprocess.run([*command, '-'], stdin=context).returncode == 0, 'Pinned upstream build failed')
            image_id = iidfile.read_text().strip()
        method = 'build'
    require(re.fullmatch(IMAGE_ID, image_id), 'Immutable Docker image ID required')
    verify_image(image_details(image_id), recipe, image_id)
    receipt = {'format': 1, 'recipe': recipe, 'image_id': image_id, 'source_verified': True, 'source_tree': tree, 'method': method, 'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    if previous is not None and (previous['recipe'] != recipe or previous['image_id'] != image_id):
        history = receipt_path().parent / 'hindsight-build-history'
        require(not history.is_symlink(), 'Refusing a symlink receipt history')
        digest = hashlib.sha256(previous_text.encode()).hexdigest()
        atomic_private_write(history / (digest + '.json'), previous_text)
    atomic_private_write(receipt_path(), json.dumps(receipt, indent=2) + '\n')
    return image_id


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
    require((home / '.pi/agent/skills/hindsight-coding-agent/SKILL.md').is_file(), 'pi harness skill missing; run scripts/hindsight.sh update')
    pi_settings = json.loads((home / '.pi/agent/settings.json').read_text())
    require(any('coding-agents/dist/pi.js' in entry for entry in (pi_settings.get('extensions') or [])), 'pi extension not registered in ~/.pi/agent/settings.json; run scripts/hindsight.sh update')
    verify_services(compose_services(home))
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
    parser = argparse.ArgumentParser(description='Hindsight validation and pinned upstream image build')
    parser.add_argument('command', choices=['preflight', 'health', 'runtime', 'build-image'])
    parser.add_argument('--minimum', default='0.5.3')
    parser.add_argument('--dry-run', action='store_true')
    recovery = parser.add_mutually_exclusive_group()
    recovery.add_argument('--adopt-iidfile', type=Path, help='Attest that a trusted completed build used the exact recipe; verify its IID, source checkout and OCI labels before recording it')
    recovery.add_argument('--archive', type=Path, help='Recover the exact receipted image from a local Docker save archive')
    args = parser.parse_args()
    if args.command != 'build-image' and (args.dry_run or args.adopt_iidfile or args.archive):
        parser.error('Build options require build-image')
    try:
        if args.command == 'build-image':
            build_image(args)
            return 0
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
