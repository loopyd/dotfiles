#!/usr/bin/env python3
"""Install and maintain the global OpenSpec integration for Pi and Codex.

The ``openspec`` CLI itself is installed by ``scripts/tools.sh`` from
``templates/packages.json``. This helper regenerates OpenSpec's agent
integration from that CLI and installs it into the account's global agent
directories:

    ~/.pi/agent/skills/openspec-*/     Pi Agent Skills
    ~/.pi/agent/prompts/opsx-*.md      Pi slash commands (/opsx-*)
    ~/.codex/skills/openspec-*/        Codex Agent Skills ($openspec-*)

OpenSpec renders a tool-specific variant for each root, so Pi gets the
``/opsx-*`` handoffs and Codex the ``$openspec-*`` handoffs.

Generated files are owned here. ``scripts/snapshot.py`` excludes them from
capture so they are never frozen into dotfiles templates, and the installer
refuses to remove anything it did not record in its receipt.

OpenSpec has no model setting of its own, so the model policy for OpenSpec
work is configured on each agent:

    ~/.codex/openspec.config.toml     Codex profile (``codex -p openspec``)
    ~/.local/bin/openspec-pi          Pi launcher (``ninerouter/ds-combo:high``)

Subcommands:
    sync              Regenerate and install the global integration
    check             Verify config, receipt and installed artifacts, read-only
    remove            Remove only the installed integration and staging tree
    scaffold [PATH]   Initialize OpenSpec in PATH with the dotfiles project template
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[1]
PACKAGE = '@fission-ai/openspec'
MINIMUM = (1, 13, 2)
TOOLS = 'pi,codex'
SKILL_PREFIX = 'openspec-'
PROMPT_GLOB = 'opsx-*.md'
CORE_WORKFLOWS = ['propose', 'explore', 'apply', 'update', 'sync', 'archive']

HOME = Path.home()
CONFIG = HOME / '.config/openspec/config.json'
STAGING = HOME / '.local/share/dotfiles/openspec/global'
PI_SKILLS_DIR = HOME / '.pi/agent/skills'
PROMPTS_DIR = HOME / '.pi/agent/prompts'
CODEX_SKILLS_DIR = HOME / '.codex/skills'
RECEIPT = HOME / '.local/state/dotfiles/openspec.json'
SCAFFOLD_CANDIDATES = (
    REPO / 'templates/openspec/config.yaml',
    Path(__file__).resolve().parent / 'openspec-config.yaml',
)
SKILL_DIRS = (PI_SKILLS_DIR, CODEX_SKILLS_DIR)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(arguments, cwd=None, capture=False):
    environment = dict(os.environ, OPENSPEC_TELEMETRY='0', NO_COLOR='1')
    result = subprocess.run(
        arguments,
        cwd=str(cwd) if cwd else None,
        env=environment,
        text=True,
        capture_output=capture,
    )
    if result.returncode:
        detail = ((result.stderr or '') + (result.stdout or '')).strip() if capture else ''
        raise ValueError('Command failed: ' + ' '.join(str(part) for part in arguments) + (': ' + detail if detail else ''))
    return result.stdout if capture else ''


def cli():
    path = shutil.which('openspec')
    require(path is not None, 'openspec CLI not found; install it with ./scripts/tools.sh install')
    return path


def cli_version():
    text = run([cli(), '--version'], capture=True).strip()
    match = re.search(r'(\d+)\.(\d+)\.(\d+)', text)
    require(match is not None, 'Unparseable openspec version: ' + text)
    return tuple(int(part) for part in match.groups()), match.group(0)


def configuration():
    require(not CONFIG.is_symlink(), 'Refusing a symlink global config: ' + str(CONFIG))
    require(CONFIG.is_file(), 'Rendered global config missing; render dotfiles first: ' + str(CONFIG))
    data = json.loads(CONFIG.read_text())
    require(data.get('profile') in {'core', 'custom'}, 'Unsupported OpenSpec profile in ' + str(CONFIG))
    require(data.get('delivery') in {None, 'both', 'skills', 'commands'}, 'Unsupported OpenSpec delivery in ' + str(CONFIG))
    return data


def configured_workflows():
    data = configuration()
    if data.get('profile') == 'custom':
        workflows = data.get('workflows')
        require(isinstance(workflows, list) and workflows and all(isinstance(name, str) for name in workflows),
                'Custom OpenSpec profile requires a non-empty workflows list in ' + str(CONFIG))
        return list(workflows)
    return list(CORE_WORKFLOWS)


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def owned(path):
    path = Path(path)
    for directory in SKILL_DIRS:
        if path.parent == directory and path.name.startswith(SKILL_PREFIX):
            return True
        if directory in path.parents:
            try:
                if path.relative_to(directory).parts[0].startswith(SKILL_PREFIX):
                    return True
            except (ValueError, IndexError):
                return False
    return path.parent == PROMPTS_DIR and path.name.startswith('opsx-') and path.suffix == '.md'


def generate():
    version, text = cli_version()
    require(version >= MINIMUM, 'OpenSpec ' + text + ' is older than the required ' + '.'.join(str(part) for part in MINIMUM))
    configured_workflows()
    STAGING.mkdir(parents=True, exist_ok=True, mode=0o700)
    # init is idempotent and re-asserts the selected tools from global config.
    run([cli(), 'init', '--tools', TOOLS, '--no-animation'], cwd=STAGING)
    return text


def generated_artifacts():
    pi_skills_root = STAGING / '.pi/skills'
    prompts_root = STAGING / '.pi/prompts'
    codex_skills_root = STAGING / '.agents/skills'

    def skills(root):
        if not root.is_dir():
            return []
        return sorted((path for path in root.iterdir() if path.is_dir() and path.name.startswith(SKILL_PREFIX)),
                      key=lambda path: path.name)

    pi_skills = skills(pi_skills_root)
    codex_skills = skills(codex_skills_root)
    prompts = sorted(prompts_root.glob(PROMPT_GLOB)) if prompts_root.is_dir() else []
    require(pi_skills, 'OpenSpec produced no Pi skills; inspect ' + str(STAGING))
    require(prompts, 'OpenSpec produced no Pi prompts; inspect ' + str(STAGING))
    require(codex_skills, 'OpenSpec produced no Codex skills; inspect ' + str(STAGING))
    return pi_skills, prompts, codex_skills


def install_tree(source, directory):
    destination = directory / source.name
    require(not destination.is_symlink(), 'Refusing a symlink destination: ' + str(destination))
    temporary = directory / ('.' + source.name + '.tmp')
    if temporary.exists():
        shutil.rmtree(temporary)
    shutil.copytree(source, temporary)
    if destination.exists():
        shutil.rmtree(destination)
    os.replace(temporary, destination)


def install_prompt(source):
    destination = PROMPTS_DIR / source.name
    require(not destination.is_symlink(), 'Refusing a symlink destination: ' + str(destination))
    temporary = PROMPTS_DIR / ('.' + source.name + '.tmp')
    shutil.copyfile(source, temporary)
    os.chmod(temporary, 0o600)
    os.replace(temporary, destination)


def remove_tree(path):
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        return
    require(owned(path), 'Refusing to remove a path this component does not own: ' + str(path))
    if path.is_symlink() or path.is_file():
        path.unlink()
    else:
        shutil.rmtree(path)


def write_receipt(data):
    require(not RECEIPT.is_symlink(), 'Refusing a symlink receipt')
    RECEIPT.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = RECEIPT.parent / ('.' + RECEIPT.name + '.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    os.chmod(temporary, 0o600)
    os.replace(temporary, RECEIPT)


def read_receipt():
    if not RECEIPT.is_file() or RECEIPT.is_symlink():
        return None
    data = json.loads(RECEIPT.read_text())
    require(data.get('format') == 1 and data.get('package') == PACKAGE, 'Unsupported OpenSpec receipt')
    return data


def sync(args):
    if args.dry_run:
        print('DRY-RUN: verify the OpenSpec config, regenerate the integration in ' + str(STAGING)
              + ' and install Pi skills/prompts under ' + str(HOME / '.pi/agent') + ' and Codex skills under '
              + str(CODEX_SKILLS_DIR) + '; no writes')
        return
    require(os.geteuid() != 0, 'Run as the destination user, not root')
    text = generate()
    pi_skills, prompts, codex_skills = generated_artifacts()
    for directory in (*SKILL_DIRS, PROMPTS_DIR):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    previous = read_receipt()
    roots = set()
    files = {}
    for source in pi_skills:
        install_tree(source, PI_SKILLS_DIR)
        root = PI_SKILLS_DIR / source.name
        roots.add(str(root))
        for path in sorted(root.rglob('*')):
            if path.is_file():
                files[str(path)] = file_hash(path)
    for source in codex_skills:
        install_tree(source, CODEX_SKILLS_DIR)
        root = CODEX_SKILLS_DIR / source.name
        roots.add(str(root))
        for path in sorted(root.rglob('*')):
            if path.is_file():
                files[str(path)] = file_hash(path)
    for source in prompts:
        install_prompt(source)
        path = PROMPTS_DIR / source.name
        roots.add(str(path))
        files[str(path)] = file_hash(path)
    if previous:
        for root in previous.get('roots', []):
            if root not in roots:
                remove_tree(root)
        for name in previous.get('files', {}):
            if name not in files and owned(name):
                path = Path(name)
                if path.is_file() and not path.is_symlink():
                    path.unlink()
    write_receipt({
        'format': 1,
        'package': PACKAGE,
        'version': text,
        'tools': TOOLS,
        'workflows': configured_workflows(),
        'roots': sorted(roots),
        'files': files,
    })
    print('Installed OpenSpec ' + text + ' integration: ' + str(len(pi_skills)) + ' Pi skills, '
          + str(len(prompts)) + ' Pi prompts, ' + str(len(codex_skills)) + ' Codex skills')


def check(args):
    version, text = cli_version()
    require(version >= MINIMUM, 'OpenSpec ' + text + ' is older than the required ' + '.'.join(str(part) for part in MINIMUM))
    configuration()
    data = read_receipt()
    require(data is not None, 'No installation receipt; run ./scripts/openspec.sh install')
    require(data.get('version') == text, 'Receipt version ' + str(data.get('version')) + ' differs from installed ' + text + '; run sync')
    modified = []
    for name, expected in data.get('files', {}).items():
        path = Path(name)
        if not owned(path) or not path.is_file() or path.is_symlink() or file_hash(path) != expected:
            modified.append(name)
    require(not modified, 'Missing or modified installed artifacts: ' + ', '.join(modified[:5]))
    require(STAGING.is_dir(), 'Staging tree missing; run sync: ' + str(STAGING))
    print('OpenSpec ' + text + ' integration verified (' + str(len(data.get('files', {}))) + ' files)')


def remove(args):
    if args.dry_run:
        print('DRY-RUN: remove recorded OpenSpec Pi skills, Pi prompts and Codex skills plus the staging tree; keep the CLI and global config')
        return
    require(os.geteuid() != 0, 'Run as the destination user, not root')
    data = read_receipt()
    if data:
        for name, expected in data.get('files', {}).items():
            path = Path(name)
            if not owned(path):
                continue
            if path.is_file() and not path.is_symlink() and file_hash(path) != expected:
                raise ValueError('Installed artifact changed since install; preserve and review: ' + name)
        for root in data.get('roots', []):
            remove_tree(root)
        RECEIPT.unlink()
    if STAGING.exists() and not STAGING.is_symlink():
        shutil.rmtree(STAGING)
    print('Removed OpenSpec agent integration and staging tree; CLI, global config and project files retained')


def scaffold_config():
    for candidate in SCAFFOLD_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise ValueError('Missing OpenSpec project template; run ./scripts/openspec.sh install')


def scaffold(args):
    target = Path(args.path).resolve()
    require(target.is_dir(), 'Target directory does not exist: ' + str(target))
    template = scaffold_config()
    config = target / 'openspec/config.yaml'
    require(not config.exists(), 'Project already has an OpenSpec config: ' + str(config))
    if args.dry_run:
        print('DRY-RUN: run openspec init --tools ' + TOOLS + ' in ' + str(target)
              + ' and apply ' + str(template))
        return
    require(os.geteuid() != 0, 'Run as the destination user, not root')
    run([cli(), 'init', '--tools', TOOLS, '--no-animation'], cwd=target)
    require(config.is_file(), 'openspec init did not create ' + str(config))
    shutil.copyfile(template, config)
    print('Initialized OpenSpec in ' + str(target) + ' with the dotfiles project template')


def main():
    parser = argparse.ArgumentParser(description='Maintain the global OpenSpec integration for Pi and Codex')
    parser.add_argument('action', choices=['sync', 'check', 'remove', 'scaffold'])
    parser.add_argument('path', nargs='?', default='.')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.action == 'scaffold':
        scaffold(args)
    elif args.action == 'sync':
        sync(args)
    elif args.action == 'remove':
        remove(args)
    else:
        check(args)


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
