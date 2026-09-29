#!/usr/bin/env python3
"""Check Codex metadata discovery in a disposable home without running a model turn."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import tomllib

def request(process, request_id, method, params):
    process.stdin.write((json.dumps({'id': request_id, 'method': method, 'params': params}) + '\n').encode())
    deadline = time.monotonic() + 30
    buffer = b''
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        chunk = os.read(process.stdout.fileno(), 1)
        if not chunk:
            raise RuntimeError('Codex exited before answering ' + method)
        buffer += chunk
        if chunk != b'\n':
            continue
        message = json.loads(buffer)
        buffer = b''
        if message.get('id') == request_id:
            if 'error' in message:
                raise RuntimeError(method + ': ' + json.dumps(message['error']))
            return message['result']
    raise RuntimeError('Codex timed out answering ' + method)


def check(repo, executable):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
    from dotfiles import materialize

    with tempfile.TemporaryDirectory(prefix='dotfiles-codex-check-') as directory:
        home = Path(directory)
        codex = home / '.codex'
        codex.mkdir()
        values = {'HOME': str(home)}
        values.update({key: 'placeholder' for key in json.loads((repo / 'templates/values.example.json').read_text())})
        overlay = repo / 'root/home/user'
        agent_names = set()
        for source in sorted((overlay / '.codex/agents').glob('*.toml.tmpl')):
            target = home / source.relative_to(overlay).with_suffix('')
            text = materialize(source.read_text(), values, target)
            data = tomllib.loads(text)
            if not all(isinstance(data.get(key), str) and data[key] for key in ('name', 'description', 'developer_instructions')):
                raise ValueError('Missing agent fields: ' + source.name)
            if data['name'] in agent_names:
                raise ValueError('Duplicate agent: ' + data['name'])
            agent_names.add(data['name'])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        expected = {'delegate', 'evidence-auditor', 'oracle', 'researcher', 'reviewer', 'scout', 'worker', 'comment-remover'}
        if agent_names != expected:
            raise ValueError('Unexpected agent inventory')
        skills = set()
        for source in (overlay / '.agents/skills').glob('*/agents/openai.yaml.tmpl'):
            skill = source.parents[1].name
            skills.add(skill)
            target = home / source.relative_to(overlay).with_suffix('')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source.read_text())
            skill_source = source.parents[1] / 'SKILL.md.tmpl'
            (target.parent.parent / 'SKILL.md').write_text(materialize(skill_source.read_text(), values, target.parent.parent / 'SKILL.md'))
        (codex / 'config.toml').write_text('[agents]\nenabled = true\n')
        process = subprocess.Popen([executable, 'app-server', '--stdio', '--strict-config'], cwd=home,
                                   env={**os.environ, 'HOME': str(home), 'CODEX_HOME': str(codex)},
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        try:
            request(process, 1, 'initialize', {'clientInfo': {'name': 'dotfiles-check', 'version': '1'},
                                              'capabilities': {'experimentalApi': True}})
            process.stdin.write(b'{"method":"initialized"}\n')
            result = request(process, 2, 'skills/list', {'cwds': [str(home)], 'forceReload': True})
            loaded = {}
            for group in result['data']:
                if group['errors']:
                    raise ValueError('Codex skill loading errors: ' + json.dumps(group['errors']))
                loaded.update({skill['name']: skill for skill in group['skills']})
            for name in skills:
                interface = loaded[name]['interface']
                if not interface or '$' + name not in interface['defaultPrompt']:
                    raise ValueError('Codex did not load the skill metadata: ' + name)
                if not 25 <= len(interface['shortDescription']) <= 64:
                    raise ValueError('Invalid short description: ' + name)
            request(process, 3, 'thread/start', {'cwd': str(home), 'ephemeral': True,
                                                'approvalPolicy': 'never', 'sandbox': 'read-only'})
            return {'agent_files_validated': sorted(agent_names), 'metadata_loaded_by_codex': sorted(skills),
                    'thread_start': 'passed', 'model_turns': 0, 'agent_spawning': 'not tested'}
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--codex', default='codex')
    args = parser.parse_args()
    print(json.dumps(check(args.repo.resolve(), args.codex), indent=2))


if __name__ == '__main__':
    main()
