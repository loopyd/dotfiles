const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');

(async () => {
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major < 24 || major === 24 && minor < 5) throw Error('Node 24.5+ required');
  const repo = path.resolve(__dirname, '../..');
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'dotfiles-skill-tests-'));
  try {
    for (const name of ['gateway', 'herdr']) {
      const from = path.join(repo, 'root/home/user/.agents/skills', name, 'scripts');
      const to = path.join(root, name + '-js');
      await fs.mkdir(to);
      let files;
      try { files = await fs.readdir(from); }
      catch (error) { if (error.code === 'ENOENT') continue; throw error; }
      for (const file of files) {
        if (file.endsWith('.tmpl')) await fs.copyFile(path.join(from, file), path.join(to, file.slice(0, -5)));
      }
    }
    const files = await fs.readdir(__dirname);
    for (const file of files) {
      if (file !== 'run.cjs') await fs.copyFile(path.join(__dirname, file), path.join(root, file));
    }
    const selected = process.argv.slice(2);
    const tests = selected.length ? selected : files.filter(file => /^test-.*\.cjs$/.test(file)).sort();
    for (const name of tests) {
      if (!/^test-[A-Za-z0-9-]+\.cjs$/.test(name) || !files.includes(name)) throw Error('Unknown test: ' + name);
      const child = spawn(process.execPath, [path.join(root, name)], {
        cwd: root,
        stdio: 'inherit',
        env: { ...process.env, NODE_DISABLE_COMPILE_CACHE: '1' },
      });
      const code = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => child.kill('SIGKILL'), 60000);
        child.once('error', error => { clearTimeout(timer); reject(error); });
        child.once('close', code => { clearTimeout(timer); resolve(code); });
      });
      if (code !== 0) throw Error(name + ' failed: ' + code);
    }
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
