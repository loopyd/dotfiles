#!/usr/bin/env python3
"""Refresh shared skills and Pi agents, and archive them, without recapturing unrelated configuration."""
import argparse
import datetime
import hashlib
import json
import os
import zipfile
from pathlib import Path

from dotfiles import beneath
from guard import findings
from snapshot import MARKER, Scrubber, private_material, private_write, reason


ROOTS = ('.agents/skills', '.pi/agent/agents')
ARCHIVE = 'archive'


def unreadable(error):
    raise error


def plan(home, repo, values):
    scrubber = Scrubber(home)
    collected = {}
    excluded = []
    for prefix in ROOTS:
        base = beneath(home, prefix)
        if not base.is_dir() or base.is_symlink():
            raise ValueError('Missing or symlink source directory: ' + prefix)
        for directory, directories, files in os.walk(base, followlinks=False, onerror=unreadable):
            parent = Path(directory)
            kept = []
            for name in sorted(directories):
                path = parent / name
                relative = path.relative_to(home)
                if path.is_symlink():
                    raise ValueError('Symlink source: ' + str(relative))
                if reason(relative, is_dir=True) or (prefix == '.agents/skills' and parent == base and (name == ARCHIVE or name.startswith('openspec-'))):
                    excluded.append(str(relative))
                else:
                    kept.append(name)
            directories[:] = kept
            for name in sorted(files):
                path = parent / name
                relative = str(path.relative_to(home))
                if path.is_symlink():
                    raise ValueError('Symlink source: ' + relative)
                if reason(Path(relative)):
                    excluded.append(relative)
                    continue
                if not path.is_file() or path.stat().st_size > 2 * 1024**2:
                    raise ValueError('Nonregular or oversized source: ' + relative)
                text = path.read_text()
                if '\x00' in text or any(ord(char) < 8 for char in text) or private_material(text, documentation=path.suffix == '.md'):
                    raise ValueError('Binary or private material: ' + relative)
                scrubber.inspect(text, relative)
                collected[relative] = (text, '0700' if path.stat().st_mode & 0o100 else '0600')
    outputs = {}
    for relative, (text, mode) in sorted(collected.items()):
        source = 'root/home/user/' + relative + '.tmpl'
        sanitized = scrubber.scrub(text, relative)
        issues = findings(source, sanitized.encode())
        if issues:
            raise ValueError('Unsafe capture: ' + relative + ': ' + ', '.join(issues))
        for key in MARKER.findall(sanitized):
            if key in values and key in scrubber.values and values[key] != scrubber.values[key]:
                raise ValueError('Private value collision: ' + key)
        outputs[source] = (sanitized, {'source': source, 'target': relative, 'mode': mode,
                                     'sha256': hashlib.sha256(sanitized.encode()).hexdigest()})
        beneath(repo, source)
    used = {key for text, _ in outputs.values() for key in MARKER.findall(text)}
    additions = {key: scrubber.values[key] for key in used if key not in {'HOME', 'USER', 'UID', 'GID'} and key in scrubber.values}
    missing = used - values.keys() - scrubber.values.keys()
    if missing:
        raise ValueError('Unresolved template keys: ' + ', '.join(sorted(missing)))
    return outputs, additions, excluded


def archive(home, dry_run=False):
    base = beneath(home, '.agents/skills')
    if not base.is_dir() or base.is_symlink():
        raise ValueError('Missing or symlink source directory: .agents/skills')
    destination = base / ARCHIVE
    if destination.exists() and (destination.is_symlink() or not destination.is_dir()):
        raise ValueError('Unsafe archive destination: .agents/skills/archive')
    skills = []
    for entry in sorted(base.iterdir(), key=lambda item: item.name):
        if entry.name == ARCHIVE:
            continue
        if entry.is_symlink():
            raise ValueError('Symlink source: ' + str(entry.relative_to(home)))
        if entry.is_dir():
            skills.append(entry)
    archived = []
    if not dry_run:
        destination.mkdir(mode=0o700, exist_ok=True)
    for skill in skills:
        members = []
        for directory, directories, names in os.walk(skill, followlinks=False, onerror=unreadable):
            parent = Path(directory)
            directories[:] = sorted(name for name in directories)
            for name in sorted(names):
                path = parent / name
                if path.is_symlink() or not path.is_file():
                    raise ValueError('Nonregular source: ' + str(path.relative_to(home)))
                members.append((path, Path(skill.name) / path.relative_to(skill)))
        target = destination / (skill.name + '.zip')
        if not dry_run:
            with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as bundle:
                for path, name in members:
                    bundle.write(path, arcname=str(name))
        archived.append({'skill': skill.name, 'archive': str(target), 'files': len(members),
                         'bytes': sum(path.stat().st_size for path, _ in members)})
    return {'action': 'backup', 'dry_run': dry_run, 'destination': str(destination),
            'skills': [skill.name for skill in skills], 'archived': archived}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('sync', 'check', 'backup'))
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--values', type=Path, default=Path.home() / '.config/dotfiles/values.json')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--prune', action='store_true', help='Remove captured files deleted upstream; preserve repository-authored Codex metadata')
    args = parser.parse_args()
    home, repo, values_path = args.home.resolve(), args.repo.resolve(), args.values.resolve()
    if args.action == 'backup':
        print(json.dumps(archive(home, dry_run=args.dry_run), indent=2))
        return
    if values_path.is_relative_to(repo) or any((p / '.git').exists() for p in values_path.parents):
        parser.error('Private values must remain outside Git working trees')
    values = json.loads(values_path.read_text()) if values_path.exists() else {}
    outputs, additions, excluded = plan(home, repo, values)
    manifest_path = beneath(repo, 'templates/manifest.json')
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('format') != 1:
        raise ValueError('Unsupported manifest format')
    entries = {entry['source']: entry for entry in manifest['files']}
    if len(entries) != len(manifest['files']):
        raise ValueError('Duplicate manifest sources')
    changed = [source for source, (text, entry) in outputs.items()
               if not (repo / source).exists() or (repo / source).read_text() != text or entries.get(source) != entry]
    retained = sorted(source for source, entry in entries.items()
                      if any(entry['target'].startswith(prefix + '/') for prefix in ROOTS) and source not in outputs)
    removed = [source for source in retained
               if not source.endswith('/agents/openai.yaml.tmpl')
               and not entries[source]['target'].startswith('.agents/skills/openspec-')
               and not reason(Path(entries[source]['target']))] if args.prune else []
    for source in removed:
        if source != 'root/home/user/' + entries[source]['target'] + '.tmpl':
            raise ValueError('Unexpected capture source: ' + source)
        beneath(repo, source)
    example_path = beneath(repo, 'templates/values.example.json')
    example = json.loads(example_path.read_text())
    example.update({key: None for key in additions})
    new_values = {**values, **additions}
    values_changed = new_values != values
    if args.action == 'sync' and not args.dry_run:
        if values_changed:
            if values_path.exists():
                stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
                private_write(values_path.parent / 'backups' / (stamp + '.json'), values_path.read_text())
            private_write(values_path, json.dumps(new_values, indent=2) + '\n')
        for source in changed:
            destination = beneath(repo, source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(outputs[source][0])
        for source in removed:
            beneath(repo, source).unlink(missing_ok=True)
            del entries[source]
        entries.update({source: entry for source, (_, entry) in outputs.items()})
        manifest['files'] = list(entries.values())
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        example_path.write_text(json.dumps(example, indent=2) + '\n')
    print(json.dumps({'action': args.action, 'dry_run': args.dry_run, 'source_files': len(outputs),
                      'changed_files': changed, 'private_values_changed': values_changed,
                      'removed_files': removed,
                      'retained_repo_only_files': sorted(set(retained) - set(removed)), 'excluded': excluded}, indent=2))
    if args.action == 'check' and (changed or removed or values_changed):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
