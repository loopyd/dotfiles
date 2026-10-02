"""Regression checks for captured Pi settings."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PiSettingsTests(unittest.TestCase):
    def test_pi_compacts_local_combo_at_half_context(self):
        settings = json.loads((ROOT / 'root/home/user/.pi/agent/settings.json.tmpl').read_text())
        compaction = settings['compaction']
        self.assertTrue(compaction['enabled'])
        self.assertEqual(compaction['reserveTokens'], 32768)
        self.assertEqual(compaction['keepRecentTokens'], 24000)
        self.assertEqual(compaction['modelOverrides']['ninerouter/qwen-combo']['reserveTokens'], 131072)
        self.assertEqual(compaction['modelOverrides']['ninerouter/gpt-combo']['reserveTokens'], 128000)
        models = json.loads((ROOT / 'root/home/user/.pi/agent/models.json.tmpl').read_text())
        model = next(model for model in models['providers']['ninerouter']['models'] if model['id'] == 'qwen-combo')
        self.assertEqual(model['contextWindow'] - compaction['modelOverrides']['ninerouter/qwen-combo']['reserveTokens'], 131072)

    def test_pi_pins_ask_extension_once(self):
        settings = json.loads((ROOT / 'root/home/user/.pi/agent/settings.json.tmpl').read_text())
        self.assertEqual(settings['packages'].count('npm:@nguyenquangthai/pi-ask@0.2.1'), 1)


if __name__ == '__main__':
    unittest.main()
