"""Regression checks for the captured Bonsai context and admission configuration."""

import hashlib
import json
import re
import shlex
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'root/home/user/.config/easyllama/native'


class BonsaiContextTests(unittest.TestCase):
    def test_all_bonsai_profiles_bound_admission_and_serialize_full_context_chat(self):
        profiles = list((NATIVE / 'config').glob('*bonsai*.tmpl'))
        self.assertEqual(len(profiles), 4)
        for path in profiles:
            with self.subTest(profile=path.name):
                chat = path.read_text().split('  bonsai-chat:', 1)[1].split('  qwen3-embeddings:', 1)[0]
                # Admission counts outstanding requests; the backend executes one at a time.
                limits = re.findall(r'^    concurrencyLimit: (\d+)$', chat, re.MULTILINE)
                self.assertEqual(limits, ['16'])
                command = chat.split("    cmd: '", 1)[1].rsplit("'", 1)[0]
                arguments = shlex.split(command)
                for flag, value in (('--parallel', '1'), ('-c', '262144')):
                    self.assertEqual(arguments.count(flag), 1)
                    self.assertEqual(arguments[arguments.index(flag) + 1], value)
                self.assertEqual(arguments.count('--kv-unified'), 1)

    def test_deployment_receipt_and_manifest_match_templates(self):
        receipt = json.loads((ROOT / 'root/home/user/.config/easyllama/deployment.json.tmpl').read_text())
        self.assertEqual(receipt['chat_slots'], 1)
        self.assertEqual(receipt['context_tokens'], 262144)
        for entry in receipt['files']:
            source = NATIVE / (entry['path'] + '.tmpl')
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), entry['template_sha256'], entry['path'])
        manifest = json.loads((ROOT / 'templates/manifest.json').read_text())
        for entry in manifest['files']:
            if 'easyllama/' in entry['source']:
                self.assertEqual(hashlib.sha256((ROOT / entry['source']).read_bytes()).hexdigest(), entry['sha256'], entry['source'])


if __name__ == '__main__':
    unittest.main()
