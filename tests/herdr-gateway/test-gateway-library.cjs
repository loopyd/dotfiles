const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

async function invoke(input) {
  const child = spawn(process.execPath, [path.join(__dirname, 'gateway-js/gateway_artifact.cjs')]);
  let output = '';
  child.stdout.on('data', chunk => output += chunk);
  child.stdin.end(JSON.stringify(input) + '\n');
  await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
  return JSON.parse(output);
}

(async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gateway-library-test-'));
  try {
    const source = path.join(root, 'source');
    const directory = path.join(root, 'readback');
    await fs.writeFile(source, 'x');
    await fs.mkdir(directory);
    const alias = path.join(directory, 'alias');
    await fs.link(source, alias);
    const request = {
      action: 'materialize_library', destination: alias, source_path: source,
      readback_directory: directory, file_id: 'file_pinned', library_file_id: 'libfile_fixture',
      expected_sha256: hash('x'), size_bytes: 1,
      transfer: { workspace_path: alias, file_id: 'file_pinned', library_file_id: 'libfile_fixture' },
    };
    assert.equal((await invoke(request)).error_code, 'readback_source_alias');
    assert.equal((await invoke({ ...request, transfer: { ...request.transfer, file_id: 'file_wrong' } })).error_code, 'library_version_identity_mismatch');
    assert.equal((await invoke({ ...request, transfer: { ...request.transfer, workspace_path: source } })).error_code, 'readback_destination_not_isolated');
    const independent = path.join(directory, 'independent');
    await fs.writeFile(independent, 'x');
    assert.equal((await invoke({ ...request, destination: independent,
      transfer: { ...request.transfer, workspace_path: independent },
      setfattr_path: '/not-installed', getfattr_path: '/not-installed' })).status, 'verified');
    assert.equal((await invoke({ ...request, destination: independent,
      transfer: { file_id: 'file_pinned', library_file_id: 'libfile_fixture', download_url: 'https://fixture.invalid/private' } })).error_code, 'readback_destination_exists');

    const getter = path.join(root, 'getfattr');
    const setter = path.join(root, 'setfattr');
    const marker = path.join(root, 'setter-called');
    await fs.writeFile(getter, '#!/usr/bin/env node\nif (!process.argv.includes("--version")) console.log("user.library-file-id=0s" + Buffer.from("libfile_original").toString("base64"));\n', { mode: 0o700 });
    await fs.writeFile(setter, '#!/usr/bin/env node\nif (!process.argv.includes("--version")) require("fs").writeFileSync(' + JSON.stringify(marker) + ', "called");\n', { mode: 0o700 });
    const metadata = { action: 'apply_library_metadata', destination: source,
      library_file_id: 'libfile_other', expected_sha256: hash('x'), size_bytes: 1,
      setfattr_path: setter, getfattr_path: getter };
    assert.equal((await invoke(metadata)).error_code, 'metadata_identity_conflict');
    await assert.rejects(fs.access(marker));
    await fs.writeFile(source + '.library.json', JSON.stringify({ library_file_id: 'libfile_original' }));
    assert.equal((await invoke({ ...metadata, setfattr_path: '/not-installed', getfattr_path: '/not-installed' })).error_code, 'metadata_identity_conflict');
    console.log('Library checks passed: isolated pinned readback, hardlink rejection, stale destination, native and sidecar identity preservation.');
  } finally { await fs.rm(root, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
