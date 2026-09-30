#!/usr/bin/env python3
"""Run scoped skill synchronization regression tests in disposable homes."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/skills.py'


class SkillsSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-skills-test-', dir=Path.home())
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home, self.repo = root / 'home', root / 'repo'
        self.values = root / 'private/values.json'
        self.skill = self.home / '.agents/skills/example/SKILL.md'
        self.skill.parent.mkdir(parents=True)
        self.skill.write_text('---\nname: example\ndescription: Example skill\n---\nRead ' + str(self.home) + '/notes.\n')
        agents = self.home / '.pi/agent/agents'
        agents.mkdir(parents=True)
        (agents / 'worker.md').write_text('---\nname: worker\n---\nDo the assigned task.\n')
        (self.repo / 'templates').mkdir(parents=True)
        self.manifest = self.repo / 'templates/manifest.json'
        self.manifest.write_text(json.dumps({'format': 1, 'files': [], 'symlinks': []}))
        (self.repo / 'templates/values.example.json').write_text('{}\n')

    def run_sync(self, *args, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *args, '--home', str(self.home),
                                 '--repo', str(self.repo), '--values', str(self.values)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
        return json.loads(result.stdout) if result.stdout else None

    def test_capture_update_check_and_dry_run(self):
        result = self.run_sync('sync', '--dry-run')
        self.assertEqual(result['source_files'], 2)
        self.assertEqual(json.loads(self.manifest.read_text())['files'], [])
        self.run_sync('sync')
        target = self.repo / 'root/home/user/.agents/skills/example/SKILL.md.tmpl'
        self.assertEqual(target.read_text(), '---\nname: example\ndescription: Example skill\n---\nRead @@DOTFILES:HOME@@/notes.\n')
        self.skill.write_text('Updated instructions.\n')
        self.run_sync('check', success=False)
        self.run_sync('sync')
        self.assertEqual(target.read_text(), 'Updated instructions.\n')
        before = self.manifest.read_bytes()
        self.assertEqual(self.run_sync('check')['changed_files'], [])
        self.run_sync('sync')
        self.assertEqual(self.manifest.read_bytes(), before)

    def add_entry(self, relative, text):
        source = 'root/home/user/' + relative + '.tmpl'
        path = self.repo / source
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        manifest = json.loads(self.manifest.read_text())
        manifest['files'].append({'source': source, 'target': relative, 'mode': '0600',
                                  'sha256': hashlib.sha256(text.encode()).hexdigest()})
        self.manifest.write_text(json.dumps(manifest))
        return path

    def test_backup_zips_each_skill_and_sync_ignores_archive(self):
        helper = self.skill.parent / 'helper.py'
        helper.write_text('#!/usr/bin/env python3\nprint("hello")\n')
        preview = self.run_sync('backup', '--dry-run')
        self.assertEqual(preview['action'], 'backup')
        self.assertEqual(preview['skills'], ['example'])
        archive = self.home / '.agents/skills/archive'
        self.assertFalse(archive.exists())
        result = self.run_sync('backup')
        self.assertEqual([entry['files'] for entry in result['archived']], [2])
        bundle = archive / 'example.zip'
        self.assertTrue(bundle.is_file())
        with zipfile.ZipFile(bundle) as opened:
            self.assertEqual(sorted(opened.namelist()), ['example/SKILL.md', 'example/helper.py'])
        synced = self.run_sync('sync')
        self.assertIn('.agents/skills/archive', synced['excluded'])
        targets = {entry['target'] for entry in json.loads(self.manifest.read_text())['files']}
        self.assertNotIn('.agents/skills/archive/example.zip', targets)
        self.run_sync('check')

    def test_prune_preserves_metadata_and_unrelated_entries(self):
        old = self.add_entry('.agents/skills/example/old.md', 'old\n')
        metadata = self.add_entry('.agents/skills/example/agents/openai.yaml', 'interface: {}\n')
        unrelated = self.add_entry('.config/example.toml', 'value = 1\n')
        self.run_sync('sync')
        self.assertEqual(old.read_text(), 'old\n')
        result = self.run_sync('sync', '--prune')
        self.assertEqual(result['removed_files'], ['root/home/user/.agents/skills/example/old.md.tmpl'])
        self.assertFalse(old.exists())
        self.assertEqual(metadata.read_text(), 'interface: {}\n')
        self.assertEqual(unrelated.read_text(), 'value = 1\n')

    def test_secret_capture_preserves_private_values(self):
        self.values.parent.mkdir()
        self.values.write_text(json.dumps({'EXISTING': 'keep-me'}))
        config = self.skill.parent / 'settings.json'
        config.write_text(json.dumps({'api_key': 'synthetic-test-' + 'credential-12345'}))
        self.run_sync('sync')
        target = self.repo / 'root/home/user/.agents/skills/example/settings.json.tmpl'
        self.assertEqual(json.loads(target.read_text()), {'api_key': '@@DOTFILES:SECRET_AGENTS_SKILLS_EXAMPLE_SETTINGS_JSON_API_KEY@@'})
        values = json.loads(self.values.read_text())
        self.assertEqual(values['EXISTING'], 'keep-me')
        self.assertEqual(values['SECRET_AGENTS_SKILLS_EXAMPLE_SETTINGS_JSON_API_KEY'], 'synthetic-test-credential-12345')
        self.assertEqual(self.values.stat().st_mode & 0o777, 0o600)
        self.run_sync('check')

    def test_documentation_example_word_is_not_a_global_secret(self):
        (self.skill.parent / 'notes.md').write_text('"key": "priority"\n')
        other = self.home / '.agents/skills/other/SKILL.md'
        other.parent.mkdir(parents=True)
        other.write_text('---\nname: other\ndescription: Other\n---\nAct with priority.\n')
        self.run_sync('sync')
        captured = (self.repo / 'root/home/user/.agents/skills/other/SKILL.md.tmpl').read_text()
        self.assertIn('priority', captured)
        self.assertNotIn('@@DOTFILES:', captured)

    def test_documentation_credential_assignment_is_still_captured(self):
        (self.skill.parent / 'notes.md').write_text('NINEROUTER_KEY="synthetic-credential-12345"\n')
        self.run_sync('sync')
        captured = (self.repo / 'root/home/user/.agents/skills/example/notes.md.tmpl').read_text()
        self.assertIn('@@DOTFILES:', captured)
        self.assertNotIn('synthetic-credential-12345', captured)

    def test_source_symlinks_and_escape_fail_before_writes(self):
        link = self.skill.parent / 'outside.md'
        link.symlink_to(self.skill)
        self.run_sync('sync', success=False)
        self.assertEqual(json.loads(self.manifest.read_text())['files'], [])
        link.unlink()
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        (self.repo / 'root').symlink_to(outside, target_is_directory=True)
        self.run_sync('sync', success=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_prune_rejects_misdirected_manifest_source(self):
        victim = self.repo / 'README.md'
        victim.write_text('Preserve this file.\n')
        manifest = json.loads(self.manifest.read_text())
        manifest['files'].append({'source': 'README.md', 'target': '.agents/skills/removed/SKILL.md',
                                  'mode': '0600', 'sha256': hashlib.sha256(victim.read_bytes()).hexdigest()})
        self.manifest.write_text(json.dumps(manifest))
        self.run_sync('sync', '--prune', success=False)
        self.assertEqual(victim.read_text(), 'Preserve this file.\n')
        self.assertEqual(len(json.loads(self.manifest.read_text())['files']), 1)

    def test_executable_assets_and_snapshot_exclusions(self):
        script = self.skill.parent / 'helper.py'
        script.write_text('#!/usr/bin/env python3\nprint("hello")\n')
        script.chmod(0o700)
        (self.skill.parent / 'runtime.log').write_text('not captured\n')
        generated = self.home / '.agents/skills/openspec-example'
        generated.mkdir()
        (generated / 'SKILL.md').write_text('generated elsewhere\n')
        self.run_sync('sync')
        entries = {entry['target']: entry for entry in json.loads(self.manifest.read_text())['files']}
        self.assertEqual(entries['.agents/skills/example/helper.py']['mode'], '0700')
        self.assertEqual(len(entries), 3)
        self.assertNotIn('.agents/skills/example/runtime.log', entries)
        self.assertNotIn('.agents/skills/openspec-example/SKILL.md', entries)


if __name__ == '__main__':
    unittest.main()
