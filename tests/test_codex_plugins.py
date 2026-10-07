"""Pinned plugin restoration must reject changed code before trusting hooks."""

import importlib.util
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class CodexPluginTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('codex_plugins', ROOT / 'scripts/codex_plugins.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.lock = self.module.load_lock(ROOT / 'templates/codex-plugins.json')
        self.plugin = self.lock['plugins'][0]
        self.cache = self.home / '.codex/plugins/cache' / self.plugin['marketplace'] / self.plugin['name'] / self.plugin['version']
        self.cache.mkdir(parents=True)

    def test_changed_cached_script_prevents_trust(self):
        script = self.cache / 'script.py'
        script.write_text('reviewed source\n')
        self.plugin['files'] = {'script.py': hashlib.sha256(script.read_bytes()).hexdigest()}
        script.write_text('changed source\n')
        with patch.object(self.module, 'rpc') as rpc:
            with self.assertRaisesRegex(ValueError, 'Pinned plugin file'):
                self.module.trust(self.home, self.lock, ROOT)
            rpc.assert_not_called()

    def test_unreviewed_extra_skill_prevents_trust(self):
        self.plugin['files'] = {}
        (self.cache / 'unreviewed.md').write_text('Unreviewed instructions\n')
        with patch.object(self.module, 'rpc') as rpc:
            with self.assertRaisesRegex(ValueError, 'inventory changed'):
                self.module.trust(self.home, self.lock, ROOT)
            rpc.assert_not_called()

    def test_conflicting_marketplace_pin_is_preserved(self):
        configuration = {'marketplaces': {self.plugin['marketplace']: {'ref': 'different'}}}
        with patch.object(self.module, 'configuration', return_value=configuration), patch.object(self.module, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'preserve and review'):
                self.module.sync(self.home, self.lock)
            run.assert_not_called()

    def test_hook_review_rejects_changed_definition_and_ignores_other_plugins(self):
        hooks = [dict(item, pluginId=self.plugin['id'], enabled=True, isManaged=False,
                      key=self.plugin['id'] + ':' + item['suffix'], currentHash=item['hash'])
                 for item in self.plugin['hooks']]
        unrelated = {'pluginId': 'other@market', 'key': 'other', 'currentHash': 'other'}
        state = self.module.reviewed_hook_state(self.plugin, hooks + [unrelated])
        self.assertEqual(len(state), 6)
        self.assertNotIn('other', state)
        hooks[0]['currentHash'] = 'sha256:changed'
        with self.assertRaisesRegex(ValueError, 'Hook definition changed'):
            self.module.reviewed_hook_state(self.plugin, hooks)

    def test_dry_run_does_not_start_codex_or_create_home(self):
        missing_home = self.home / 'missing'
        with patch.object(self.module, 'run') as run:
            self.module.sync(missing_home, self.lock, dry_run=True)
        run.assert_not_called()
        self.assertFalse(missing_home.exists())


if __name__ == '__main__':
    unittest.main()
