"""Regression checks for Hindsight's standalone Pi compatibility adapter."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / 'root/home/user/.local/lib/dotfiles/hindsight-pi.mjs.tmpl'
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('hindsight', ROOT / 'scripts/hindsight.py')
hindsight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hindsight)


class HindsightPiTests(unittest.TestCase):
    def test_custom_runs_skip_prompt_retrieval_and_keep_memory_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            runtime = home / '.hindsight/coding-agents/dist/pi.js'
            runtime.parent.mkdir(parents=True)
            runtime.write_text('''
export default function extension(pi) {
  pi.registerTool({name: 'hindsight_test'});
  pi.on('before_agent_start', async (event, ctx) => {
    const prompt = event.prompt.trim();
    if (prompt) ctx.prompts.push(prompt);
    event.systemPromptOptions.sections.hindsight = 'remembered context';
    return {systemPrompt: event.systemPrompt};
  });
  pi.on('agent_end', (event, ctx) => ctx.ends.push(event));
}
''')
            script = '''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source = readFileSync(process.argv[1], 'utf8');
const {default: extension} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const handlers = new Map();
const tools = [];
await extension({registerTool: tool => tools.push(tool), on: (name, handler) => handlers.set(name, handler)});
assert.equal(tools[0].name, 'hindsight_test');
const ctx = {prompts: [], ends: []};
const sections = {};
const custom = {messageType: 'custom', message: {content: 'automatic continuation'}, systemPromptOptions: {sections},
  get systemPrompt() {return sections.hindsight || 'base';}};
assert.deepEqual(await handlers.get('before_agent_start')(custom, ctx), {systemPrompt: 'remembered context'});
assert.deepEqual(ctx.prompts, []);
assert.equal(Object.hasOwn(custom, 'prompt'), false);
assert.equal(sections.hindsight, 'remembered context');
const user = {...custom, messageType: 'user', prompt: '  user question  '};
await handlers.get('before_agent_start')(user, ctx);
await handlers.get('before_agent_start')({...user, prompt: '  '}, ctx);
await handlers.get('before_agent_start')({...user, messageType: undefined, prompt: 'legacy user'}, ctx);
assert.deepEqual(ctx.prompts, ['user question', 'legacy user']);
const end = {messages: ['transcript']};
await handlers.get('agent_end')(end, ctx);
assert.deepEqual(ctx.ends, [end]);
'''
            result = subprocess.run(['node', '--input-type=module', '-e', script, str(ADAPTER)],
                                    env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_wiring_replaces_direct_runtime_once_and_preserves_other_settings(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(hindsight.Path, 'home', return_value=Path(directory)):
            home = Path(directory)
            settings = home / '.pi/agent/settings.json'
            settings.parent.mkdir(parents=True)
            unrelated = {'packages': ['npm:other'], 'extensions': ['other.ts', str(home / '.hindsight/coding-agents/dist/pi.js')]}
            settings.write_text(json.dumps(unrelated))
            hindsight.wire_pi()
            hindsight.wire_pi()
            wrapper = home / '.local/lib/dotfiles/hindsight-pi.mjs'
            self.assertEqual(json.loads(settings.read_text()), {**unrelated, 'extensions': ['other.ts', str(wrapper)]})
            self.assertEqual(wrapper.read_text(), ADAPTER.read_text())


if __name__ == '__main__':
    unittest.main()
