#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote


GAMES = {'archipelago', 'bottles', 'cemu', 'dolphin-emu', 'dreadzone', 'gamemode', 'heroic', 'horizon-private-server', 'horizon-zero-dawn', 'horizonzerodawnremastered', 'itch', 'lutris', 'mame', 'minecraft', 'opengoal', 'playonlinux', 'poptracker', 'ppsspp', 'pcsx2', 'retroarch', 'rpcs3', 'rsi-launcher', 'ryujinx', 'scummvm', 'snes9x', 'starcitizen', 'steam', 'steamcmd', 'yuzu'}


def game_package(name):
    normalized = name.lower()
    if ':' in normalized and normalized.split(':', 1)[0] in {'npm', 'cargo', 'pipx', 'pip', 'go', 'aqua', 'github', 'asdf', 'vfox', 'ubi', 'flatpak', 'snap'}:
        normalized = normalized.split(':', 1)[1]
    normalized = normalized.rsplit('/', 1)[-1].split(':', 1)[0].split('=', 1)[0].split('@', 1)[0].removesuffix('.git').replace('_', '-').replace(' ', '-')
    aliases = GAMES | {'archipelagolauncher', 'star-citizen'}
    return any(candidate == game or candidate.startswith(game + '-') for candidate in [normalized, normalized.rsplit('.', 1)[-1]] for game in aliases)


def game_path(path):
    for part in str(path).replace('\\', '/').split('/'):
        stem = part.lower().removesuffix('.tmpl')
        if game_package(stem) or game_package(stem.split('.', 1)[0]):
            return True
    return False


def game_document(path, text):
    return Path(str(path).removesuffix('.tmpl')).suffix == '.desktop' and not re.search(r'^Categories=.*\bDevelopment;', text, re.M) and bool(re.search(r'^Categories=.*\bGames?(?:;|$)', text, re.M))


def clean_document(path, text):
    if str(path).removesuffix('.tmpl') != '.config/rncbc.org/qpwgraph.conf':
        return text
    return ''.join(line for line in text.splitlines(keepends=True) if not game_path(re.sub(r'%U[0-9a-fA-F]+', '', unquote(line.split('=', 1)[0]))))


def without_games(manifest):
    for key in ['npm', 'retired_pi', 'uv_tools', 'cargo', 'mise_installed']:
        manifest[key] = [name for name in manifest[key] if not game_package(name)]
    for key, names in manifest['alternate_node_managers'].items():
        manifest['alternate_node_managers'][key] = [name for name in names if not game_package(name)]
    for groups in ['python_user', 'python_managed']:
        for group in manifest[groups].values():
            for key in ['packages', 'requested']:
                if key in group: group[key] = [name for name in group[key] if not game_package(name)]
            if 'sources' in group: group['sources'] = [entry for entry in group['sources'] if not game_package(entry['name'])]
    manifest['go'] = [entry for entry in manifest['go'] if not game_package(entry['binary'])]
    return manifest


def apt_games(packages):
    rejected = {name for name in packages if game_package(name)}
    result = subprocess.run(['apt-cache', 'show', '--no-all-versions', *packages], capture_output=True, text=True)
    classified = set()
    for record in result.stdout.split('\n\n'):
        name = re.search(r'^Package: (.+)$', record, re.M)
        section = re.search(r'^Section: (.+)$', record, re.M)
        if name and section:
            classified.add(name.group(1))
            if section.group(1).split('/')[-1] == 'games':
                rejected.add(name.group(1))
    expected = {name.split(':', 1)[0].split('=', 1)[0] for name in packages}
    if result.returncode or not expected.issubset(classified):
        raise ValueError('Package classification unavailable; refresh APT metadata before installation')
    return sorted(rejected)


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] != 'apt':
        raise SystemExit('Usage: scope.py apt PACKAGE...')
    rejected = apt_games(sys.argv[2:]) if len(sys.argv) > 2 else []
    if rejected:
        print('Game packages are outside dotfiles scope: ' + ', '.join(rejected), file=sys.stderr)
        raise SystemExit(1)
