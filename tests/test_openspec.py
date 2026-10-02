"""Global OpenSpec discovery and legacy-install upgrade checks."""

import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class OpenSpecTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        with patch('pathlib.Path.home', return_value=self.home):
            spec = importlib.util.spec_from_file_location('openspec', ROOT / 'scripts/openspec.py')
            self.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.module)
        m = self.module
        m.CONFIG.parent.mkdir(parents=True)
        m.CONFIG.write_text(json.dumps({'profile': 'custom', 'workflows': ['propose'], 'delivery': 'both'}))
        for relative in ['.pi/skills/openspec-propose/SKILL.md', '.agents/skills/openspec-propose/SKILL.md',
                         '.pi/prompts/opsx-propose.md']:
            path = m.STAGING / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('Generated ' + relative + '\n')
        self.args = argparse.Namespace(dry_run=False)

    def sync(self):
        with patch.object(self.module, 'generate', return_value='1.13.2'), patch('os.geteuid', return_value=1000):
            self.module.sync(self.args)

    def legacy_receipt(self):
        m = self.module
        path = self.home / '.codex/skills/openspec-propose/SKILL.md'
        path.parent.mkdir(parents=True)
        path.write_text('Old generated skill\n')
        m.write_receipt({'format': 1, 'package': m.PACKAGE, 'version': '1.13.2',
                         'tools': m.TOOLS, 'workflows': ['propose'], 'roots': [str(path.parent)],
                         'files': {str(path): m.file_hash(path)}})
        return path

    def test_fresh_install_uses_current_codex_discovery_directory(self):
        self.sync()
        self.assertTrue((self.home / '.agents/skills/openspec-propose/SKILL.md').is_file())
        self.assertFalse((self.home / '.codex/skills').exists())
        self.assertTrue((self.home / '.pi/agent/prompts/opsx-propose.md').is_file())

    def test_upgrade_moves_only_recorded_legacy_skills(self):
        legacy = self.legacy_receipt()
        unrelated = legacy.parent.parent / 'personal/SKILL.md'
        unrelated.parent.mkdir()
        unrelated.write_text('Personal skill\n')
        self.sync()
        self.assertFalse(legacy.exists())
        self.assertTrue((self.home / '.agents/skills/openspec-propose/SKILL.md').is_file())
        self.assertEqual(unrelated.read_text(), 'Personal skill\n')

    def test_upgrade_preserves_modified_and_unrecorded_legacy_files(self):
        legacy = self.legacy_receipt()
        for modified in [True, False]:
            with self.subTest(modified=modified):
                legacy.write_text('Local edit\n' if modified else 'Old generated skill\n')
                extra = legacy.parent / 'notes.md'
                if not modified:
                    extra.write_text('Local notes\n')
                with self.assertRaisesRegex(ValueError, 'preserve and review'):
                    self.sync()
                self.assertTrue(legacy.is_file())
                self.assertFalse((self.home / '.agents/skills/openspec-propose').exists())

    def test_check_rejects_changed_workflow_configuration(self):
        self.sync()
        m = self.module
        m.CONFIG.write_text(json.dumps({'profile': 'custom', 'workflows': ['explore'], 'delivery': 'both'}))
        with patch.object(m, 'cli_version', return_value=((1, 13, 2), '1.13.2')):
            with self.assertRaisesRegex(ValueError, 'workflows'):
                m.check(self.args)


if __name__ == '__main__':
    unittest.main()
