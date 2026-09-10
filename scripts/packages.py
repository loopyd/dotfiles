#!/usr/bin/env python3
import argparse
import datetime
import email.parser
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tomllib
from urllib.parse import unquote, urlsplit
from scope import game_package, without_games


ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r'(?:@[a-z0-9_.-]+/)?[A-Za-z0-9][A-Za-z0-9_.-]*')
PI_PREFIXES = ('@earendil-works/pi-', '@mariozechner/pi-', '@plannotator/pi-', '@samfp/pi-', 'pi-')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def output(arguments):
    result = subprocess.run(arguments, cwd=Path.home(), capture_output=True, text=True)
    require(result.returncode == 0, 'Inventory command failed: ' + arguments[0])
    return result.stdout


def snapshot():
    home = Path.home()
    mise = json.loads(output(['mise', 'ls', '--installed', '--json']))
    npm = set()
    for directory in (home / '.local/share/mise/installs/node').glob('*'):
        if directory.is_symlink():
            continue
        for pattern in ['*/package.json', '@*/*/package.json']:
            for path in (directory / 'lib/node_modules').glob(pattern):
                npm.add(json.loads(path.read_text())['name'])
    for root in [home / '.npm-global/lib/node_modules', home / '.local/lib/node_modules']:
        for pattern in ['*/package.json', '@*/*/package.json']:
            for path in root.glob(pattern):
                npm.add(json.loads(path.read_text())['name'])
    alternate = {}
    for manager, relative in [('bun', '.bun/install/global/package.json'), ('pnpm', '.local/share/pnpm/global/5/package.json'), ('yarn', '.config/yarn/global/package.json')]:
        path = home / relative
        alternate[manager] = sorted(json.loads(path.read_text()).get('dependencies', {})) if path.exists() else []
    python = {}
    for site in sorted((home / '.local/lib').glob('python*/site-packages')):
        packages, requested = set(), set()
        for metadata in site.glob('*.dist-info/METADATA'):
            require(not (metadata.parent / 'direct_url.json').exists(), 'Review direct/local Python sources before capture')
            name = email.parser.Parser().parsestr(metadata.read_text())['Name']
            packages.add(name)
            if (metadata.parent / 'REQUESTED').exists():
                requested.add(name)
        python[site.parent.name.removeprefix('python')] = {'packages': sorted(packages), 'requested': sorted(requested)}
    uv = [line.split()[0] for line in output(['uv', 'tool', 'list']).splitlines() if line and not line.startswith((' ', '-'))]
    managed = {}
    for root in (home / '.local/share/mise/installs/python').glob('*'):
        if root.is_symlink():
            continue
        for site in root.glob('lib/python*/site-packages'):
            group = managed.setdefault(site.parent.name.removeprefix('python'), {'packages': [], 'sources': []})
            for metadata in site.glob('*.dist-info/METADATA'):
                name = email.parser.Parser().parsestr(metadata.read_text())['Name']
                group['packages'].append(name)
                direct = metadata.parent / 'direct_url.json'
                if direct.exists() and name != 'pip':
                    data = json.loads(direct.read_text())
                    url = urlsplit(data['url'])
                    require(not url.username and not url.password and not url.query, 'Direct Python source requires private review')
                    if url.scheme == 'file':
                        path = Path(unquote(url.path))
                        source = '~/' + str(path.relative_to(home)) if path.is_relative_to(home) else str(path)
                        group['sources'].append({'name': name, 'source': source, 'kind': 'local', 'editable': data.get('dir_info', {}).get('editable', False)})
                    elif data.get('vcs_info', {}).get('vcs') == 'git':
                        group['sources'].append({'name': name, 'source': data['url'], 'kind': 'git', 'editable': False})
                    else:
                        group['sources'].append({'name': name, 'kind': 'manual', 'reason': 'Direct archive source excluded from versionless restore'})
    for group in managed.values():
        group['packages'] = sorted(set(group['packages']))
        group['sources'] = sorted({entry['name']: entry for entry in group['sources']}.values(), key=lambda entry: entry['name'])
    crates = home / '.cargo/.crates2.json'
    cargo = []
    for source, options in json.loads(crates.read_text()).get('installs', {}).items() if crates.exists() else []:
        require('(registry+https://github.com/rust-lang/crates.io-index)' in source, 'Review non-registry Cargo source before capture')
        require(not options.get('features') and not options.get('no_default_features') and not options.get('all_features'), 'Review custom Cargo features before capture')
        cargo.append(source.split()[0])
    components, targets = set(), set()
    for path in (home / '.rustup/toolchains').glob('*/lib/rustlib/components'):
        host = re.fullmatch(r'(?:\d+\.\d+\.\d+|stable|beta|nightly(?:-\d{4}-\d{2}-\d{2})?)-(.+)', path.parents[2].name)
        require(host is not None, 'Review custom Rust toolchain before capture')
        for component in path.read_text().splitlines():
            suffix = '-' + host.group(1)
            if component.endswith(suffix):
                components.add(component.removesuffix(suffix).removesuffix('-preview'))
            elif component.startswith('rust-std-'):
                targets.add(component.removeprefix('rust-std-'))
            else:
                components.add(component.removesuffix('-preview'))
    go = {}
    roots = {home / '.local/bin', home / 'go/bin'}
    roots.update(Path(entry['install_path']) / 'bin' for entry in mise.get('go', []))
    for root in roots:
        if not root.exists():
            continue
        for path in root.iterdir():
            if path.is_symlink() or not path.is_file():
                continue
            with path.open('rb') as stream:
                if stream.read(4) != b'\x7fELF':
                    continue
            result = subprocess.run(['go', 'version', '-m', str(path)], capture_output=True, text=True)
            fields = [line.strip().split('\t') for line in result.stdout.splitlines()]
            package = next((parts[1] for parts in fields if len(parts) > 1 and parts[0] == 'path'), '')
            module = next((parts for parts in fields if len(parts) > 2 and parts[0] == 'mod'), None)
            if module:
                go[package] = {'package': package, 'binary': path.name, 'local_build': module[2] == '(devel)'}
    npm_config = {}
    npmrc = home / '.npmrc'
    for line in npmrc.read_text().splitlines() if npmrc.exists() else []:
        key, separator, value = line.partition('=')
        key, value = key.strip(), value.strip()
        if separator and (key in ['registry', 'allow-scripts', 'audit', 'fund', 'update-notifier', 'engine-strict'] or re.fullmatch(r'@[\w-]+:registry', key)):
            if key.endswith('registry'):
                url = urlsplit(value)
                require(url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.query, 'Registry URL needs private review')
            npm_config[key] = value
    return without_games({
        'format': 1,
        'captured_on': datetime.date.today().isoformat(),
        'mise_installed': sorted(mise),
        'npm': sorted(npm),
        'retired_pi': sorted(name for name in npm if name.startswith(PI_PREFIXES)),
        'npm_config': npm_config,
        'alternate_node_managers': alternate,
        'python_user': python,
        'python_managed': dict(sorted(managed.items())),
        'uv_tools': sorted(uv),
        'cargo': sorted(cargo),
        'rust_components': sorted(components),
        'rust_targets': sorted(targets),
        'go': sorted(go.values(), key=lambda entry: entry['package']),
        'exclusions': ['package versions and duplicate runtime installations', 'system packages and project virtual environments', 'games, game servers, launchers and emulator packages', 'caches, compiled artifacts, registry credentials and telemetry'],
    })


def configuration():
    path = Path.home() / '.config/mise/config.toml'
    text = path.read_text()
    require('@@DOTFILES:' not in text, 'Render user configuration first')
    config = tomllib.loads(text)
    require(not config.get('settings', {}).get('trusted_config_paths'), 'Remove blanket mise trust from the restored config; do not trust the whole filesystem')
    require('node' in config.get('tools', {}) and 'uv' in config['tools'], 'Rendered mise config must include Node and uv')
    require(all(isinstance(value, str) and value and not value.startswith('-') for value in config['tools'].values()), 'Review complex mise tool configuration manually')
    require(not any(game_package(name) for name in config['tools']), 'Configured mise game tools are outside dotfiles scope')
    return config


def validate(manifest):
    require(manifest.get('format') == 1, 'Unsupported package manifest')
    names = manifest['npm'] + manifest['uv_tools'] + manifest['cargo'] + manifest['rust_components'] + manifest['rust_targets']
    for group in manifest['python_user'].values():
        names += group['packages'] + group['requested']
    for group in manifest['python_managed'].values():
        names += group['packages']
    for packages in manifest['alternate_node_managers'].values():
        names += packages
    require(all(isinstance(name, str) and NAME.fullmatch(name) for name in names), 'Invalid package name')
    require(not any(game_package(name) for name in names + manifest['mise_installed']), 'Game packages are outside dotfiles scope')
    require(not any(game_package(entry['binary']) for entry in manifest['go']), 'Game binaries are outside dotfiles scope')
    require(all(re.fullmatch(r'3\.\d+', minor) for minor in manifest['python_user']), 'Invalid Python runtime selector')
    require(all(re.fullmatch(r'3\.\d+', minor) for minor in manifest['python_managed']), 'Invalid managed Python runtime selector')
    require(all(isinstance(tool, str) and not tool.startswith('-') and not any(character.isspace() for character in tool) for tool in manifest['mise_installed']), 'Invalid mise tool identifier')
    require(all(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', entry['package']) for entry in manifest['go']), 'Invalid Go package identifier')


def restore(manifest, dry_run, include_retired_pi, update=False):
    home = Path.home()
    config_path = home / '.config/mise/config.toml'
    config = tomllib.loads((ROOT / 'root/home/user/.config/mise/config.toml.tmpl').read_text()) if dry_run else configuration()
    require(not any(game_package(name) for name in config['tools']), 'Configured mise game tools are outside dotfiles scope')
    mise = str(home / '.local/bin/mise')
    environment = dict(os.environ)
    environment['PATH'] = str(home / '.local/bin') + ':' + str(home / '.cargo/bin') + ':' + environment.get('PATH', '')
    environment['GOBIN'] = str(home / '.local/bin')
    environment['CARGO_HOME'] = str(home / '.cargo')
    environment['RUSTUP_HOME'] = str(home / '.rustup')
    environment['UV_TOOL_DIR'] = str(home / '.local/share/uv/tools')
    environment['UV_TOOL_BIN_DIR'] = str(home / '.local/bin')
    environment['NPM_CONFIG_USERCONFIG'] = str(home / '.npmrc')

    def run(arguments):
        print(('DRY-RUN: ' if dry_run else 'RUN: ') + shlex.join(arguments), flush=True)
        if not dry_run:
            subprocess.run(arguments, cwd=home, env=environment, check=True)

    run([mise, 'trust', str(config_path)])
    run([mise, 'install'])
    if update:
        run([mise, 'upgrade'])
    if not dry_run:
        node = subprocess.run([mise, 'where', 'node'], cwd=home, env=environment, text=True, capture_output=True, check=True)
        node_path = Path(node.stdout.strip()).resolve()
        require(node_path.is_relative_to(home) and node_path.stat().st_uid == os.getuid(), 'Refusing global npm installs outside the user account')
        environment['NPM_CONFIG_PREFIX'] = str(node_path)
    for tool in manifest['mise_installed']:
        if tool not in config['tools']:
            selector = 'ref:master' if tool.startswith('cargo:https://') else 'latest'
            run([mise, 'install', tool + '@' + selector])
    rust = home / '.rustup/settings.toml'
    if dry_run:
        rust = ROOT / 'root/home/user/.rustup/settings.toml.tmpl'
    rust_config = tomllib.loads(rust.read_text())
    default = re.match(r'(?:\d+\.\d+\.\d+|stable|beta|nightly(?:-\d{4}-\d{2}-\d{2})?)', rust_config['default_toolchain']).group()
    run([mise, 'exec', '--', 'rustup', 'toolchain', 'install', default, '--profile', rust_config.get('profile', 'default')])
    run([mise, 'exec', '--', 'rustup', 'default', default])
    if manifest['rust_components']:
        run([mise, 'exec', '--', 'rustup', 'component', 'add', '--toolchain', default, *manifest['rust_components']])
    if manifest['rust_targets']:
        run([mise, 'exec', '--', 'rustup', 'target', 'add', '--toolchain', default, *manifest['rust_targets']])
    for key, value in manifest['npm_config'].items():
        run([mise, 'exec', '--', 'npm', 'config', 'set', '--location=user', key, value])
    packages = [name for name in manifest['npm'] if name != 'npm' and (include_retired_pi or name not in manifest['retired_pi'])]
    if packages:
        run([mise, 'exec', '--', 'npm', 'install', '--global', '--', *packages])
    for manager, packages in manifest['alternate_node_managers'].items():
        if packages:
            run([mise, 'exec', manager + '@latest', '--', manager, 'add', '--global', *packages])
    for minor, group in manifest['python_managed'].items():
        selector = config['tools']['python'] if config['tools']['python'].startswith(minor + '.') else minor
        run([mise, 'install', 'python@' + selector])
        python_path = home / '.local/share/mise/installs/python' / selector / 'bin/python'
        if not dry_run:
            result = subprocess.run([mise, 'where', 'python@' + selector], cwd=home, env=environment, text=True, capture_output=True, check=True)
            python_path = Path(result.stdout.strip()) / 'bin/python'
            require(python_path.resolve().is_relative_to(home) and python_path.stat().st_uid == os.getuid(), 'Refusing to modify Python outside the user account')
        sources = {entry['name'] for entry in group['sources']}
        packages = [name for name in group['packages'] if name not in sources and name != 'pip']
        if packages:
            run([mise, 'exec', '--', 'uv', 'pip', 'install', *(['--upgrade'] if update else []), '--python', str(python_path), '--', *packages])
        for entry in group['sources']:
            print('MANUAL: restore Python source package ' + entry['name'] + ' from ' + entry.get('source', entry.get('reason', 'original source')))
    for minor, group in manifest['python_user'].items():
        run([mise, 'exec', '--', 'uv', 'python', 'install', minor])
        if group['packages']:
            run([mise, 'exec', '--', 'uv', 'pip', 'install', *(['--upgrade'] if update else []), '--python', minor, '--target', str(home / '.local/lib' / ('python' + minor) / 'site-packages'), '--', *group['packages']])
    cli_tools = set(manifest['uv_tools'])
    for group in manifest['python_user'].values():
        cli_tools.update(name for name in group['requested'] if name in {'ruff', 'sqlfluff', 'yamllint'})
    for package in sorted(cli_tools):
        run([mise, 'exec', '--', 'uv', 'tool', 'install', '--force', package])
    for package in manifest['cargo']:
        run([mise, 'exec', '--', 'cargo', 'install', '--locked', package])
    for entry in manifest['go']:
        if entry['local_build']:
            print('MANUAL: rebuild local Go source for ' + entry['package'] + ' (' + entry['binary'] + ')')
        else:
            run([mise, 'exec', '--', 'go', 'install', entry['package'] + '@latest'])
    if manifest['retired_pi'] and not include_retired_pi:
        print('Retired Pi packages inventoried but skipped; use --include-retired-pi only when explicitly wanted')
    run([mise, 'reshim'])


def uninstall(manifest, dry_run):
    home = Path.home()
    mise = str(home / '.local/bin/mise')
    environment = dict(os.environ, CARGO_HOME=str(home / '.cargo'), RUSTUP_HOME=str(home / '.rustup'), UV_TOOL_DIR=str(home / '.local/share/uv/tools'), UV_TOOL_BIN_DIR=str(home / '.local/bin'), NPM_CONFIG_USERCONFIG=str(home / '.npmrc'))
    if not dry_run:
        result = subprocess.run([mise, 'where', 'node'], cwd=home, capture_output=True, text=True, check=True)
        prefix = Path(result.stdout.strip()).resolve()
        require(prefix.is_relative_to(home), 'Npm prefix must remain in the user account')
        environment['NPM_CONFIG_PREFIX'] = str(prefix)
    commands = []
    selected = [name for name in manifest['npm'] if name != 'npm' and name not in manifest['retired_pi']]
    if selected:
        commands.append([mise, 'exec', '--', 'npm', 'uninstall', '--global', '--', *selected])
    cli_tools = set(manifest['uv_tools'])
    for group in manifest['python_user'].values():
        cli_tools.update(name for name in group['requested'] if name in {'ruff', 'sqlfluff', 'yamllint'})
    for package in sorted(cli_tools):
        if dry_run or (home / '.local/share/uv/tools' / package).is_dir():
            commands.append([mise, 'exec', '--', 'uv', 'tool', 'uninstall', package])
    cargo_receipt = home / '.cargo/.crates.toml'
    cargo_installed = tomllib.loads(cargo_receipt.read_text()).get('v1', {}) if cargo_receipt.exists() else {}
    for package in manifest['cargo']:
        if dry_run or any(identity.split()[0] == package for identity in cargo_installed):
            commands.append([mise, 'exec', '--', 'cargo', 'uninstall', package])
    for command in commands:
        print(('DRY-RUN: ' if dry_run else 'RUN: ') + shlex.join(command), flush=True)
        if not dry_run:
            subprocess.run(command, cwd=home, env=environment, check=True)
    print('Shared mise/Rust/Python runtimes, library dependencies, local Go builds, Pi packages and configuration retained')


def check(manifest):
    configuration()
    mise = Path.home() / '.local/bin/mise'
    require(mise.is_file(), 'Mise is missing')
    result = subprocess.run([str(mise), 'ls', '--current', '--missing', '--json'], cwd=Path.home(), env=dict(os.environ, MISE_OFFLINE='true', MISE_SELF_UPDATE_AVAILABLE='false'), capture_output=True, text=True, check=True)
    require(not json.loads(result.stdout), 'Configured mise runtimes are missing')
    print('Package manifest, configuration and configured runtime availability validated')


def main():
    parser = argparse.ArgumentParser(description='Snapshot or restore versionless user packages without copying binaries or credentials')
    parser.add_argument('command', choices=['snapshot', 'validate', 'install', 'update', 'uninstall', 'check'])
    parser.add_argument('--manifest', type=Path, default=ROOT / 'templates/packages.json')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--include-retired-pi', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'snapshot':
            manifest = snapshot()
            validate(manifest)
            args.manifest.write_text(json.dumps(manifest, indent=2) + '\n')
            print('Captured versionless package names; no registry credentials or binaries copied')
            return
        manifest = json.loads(args.manifest.read_text())
        validate(manifest)
        if args.command == 'validate':
            configuration()
            print('Package manifest and rendered mise configuration validated')
        elif args.command == 'check':
            check(manifest)
        elif args.command == 'uninstall':
            require(args.dry_run or os.geteuid() != 0, 'Run as the destination user, not root')
            uninstall(manifest, args.dry_run)
        else:
            require(args.dry_run or os.geteuid() != 0, 'Run as the destination user, not root')
            restore(manifest, args.dry_run, args.include_retired_pi, args.command == 'update')
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        print('User-tool operation failed; check prerequisites, rendered mise config and package manifest. Credential-bearing details withheld.', file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
