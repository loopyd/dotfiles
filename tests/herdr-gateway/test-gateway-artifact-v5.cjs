const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const https = require('node:https');
const http = require('node:http');
const net = require('node:net');
const { spawn, spawnSync } = require('node:child_process');
const HASH = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const close = server => new Promise(resolve => server.close(resolve));
(async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gateway-js-test-'));
  let server, proxy;
  const connections = new Set();
  const track = socket => { connections.add(socket); socket.on('close', () => connections.delete(socket)); };
  try {
    const cert = path.join(root, 'cert.pem'), key = path.join(root, 'key.pem');
    assert.equal(spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,DNS:gateway-fixture.invalid,IP:127.0.0.1'], { stdio: 'ignore' }).status, 0);
    server = https.createServer({ key: await fs.readFile(key), cert: await fs.readFile(cert) }, (request, response) => {
      if (request.url.startsWith('/expired')) { response.writeHead(403); response.end('opaque-canary-token'); }
      else { response.writeHead(200); response.end('hello'); }
    });
    server.on('connection', track);
    await listen(server);
    let tunnels = 0;
    proxy = http.createServer();
    proxy.on('connection', track);
    proxy.on('connect', (request, socket, head) => {
      tunnels++;
      const upstream = net.connect(server.address().port, '127.0.0.1', () => {
        socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        if (head.length) upstream.write(head);
        socket.pipe(upstream); upstream.pipe(socket);
      });
      socket.on('error', () => upstream.destroy());
      upstream.on('error', () => socket.destroy());
      socket.on('close', () => upstream.destroy());
    });
    await listen(proxy);
    const env = { ...process.env, NODE_EXTRA_CA_CERTS: cert, HTTPS_PROXY: `http://127.0.0.1:${proxy.address().port}`, NO_PROXY: 'localhost,127.0.0.1' };
    delete env.https_proxy; delete env.no_proxy; delete env.NODE_TLS_REJECT_UNAUTHORIZED;
    let count = 0;
    async function invoke(changes = {}) {
      const destination = path.join(root, 'result-' + count++);
      const input = { action: 'artifact', include_content:true, expected_sha256: HASH, size_bytes: 5, inspect_bytes: 3, destination,
        download_url: `https://127.0.0.1:${server.address().port}/artifact?opaque-canary-token`, ...changes };
      const child = spawn(process.execPath, [path.join(__dirname, 'gateway-js/gateway_artifact.cjs')], { env, stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '', err = '';
      child.stdout.on('data', chunk => out += chunk); child.stderr.on('data', chunk => err += chunk);
      child.stdin.end(JSON.stringify(input) + '\n');
      const code = await new Promise(resolve => child.on('close', resolve));
      assert.equal(err, ''); assert(!out.includes('opaque-canary-token')); assert(!out.includes('https://'));
      return { code, receipt: JSON.parse(out), destination };
    }
    const metadataOnly=await invoke({include_content:false});assert.equal(metadataOnly.receipt.inspection.text,undefined);
    const direct = await invoke();
    assert.equal(direct.code, 0); assert.equal(await fs.readFile(direct.destination, 'utf8'), 'hello');
    assert.deepEqual(direct.receipt.inspection, { prefix_bytes: 3, truncated: true, kind: 'utf8', text: 'hel',sha256:require('node:crypto').createHash('sha256').update('hel').digest('hex') });
    assert.equal(tunnels, 0);
    const proxied = await invoke({ download_url: `https://gateway-fixture.invalid:${server.address().port}/artifact?opaque-canary-token` });
    assert.equal(proxied.code, 0); assert.equal(proxied.receipt.sha256, HASH); assert.equal(tunnels, 1);
    const denied = await invoke({ download_url: `https://127.0.0.1:${server.address().port}/expired?opaque-canary-token` });
    assert.deepEqual(denied.receipt, { status: 'error', error_code: 'download_failed', details: { host: '127.0.0.1', http_status: 403 } });
    const refused = await invoke({ download_url: 'https://127.0.0.1:1/opaque-canary-token' });
    assert.equal(refused.receipt.details.network_code, 'ECONNREFUSED'); assert.equal(refused.receipt.details.host, '127.0.0.1');
    const mismatch = await invoke({ expected_sha256: '0'.repeat(64) });
    assert.equal(mismatch.receipt.error_code, 'integrity_mismatch'); await assert.rejects(fs.access(mismatch.destination));
    const reused = await invoke({ destination: direct.destination, download_url: 'https://127.0.0.1:1/opaque-canary-token' });
    assert.equal(reused.receipt.source, 'local_reuse');
    const conflict = await invoke({ destination: direct.destination, expected_sha256: '0'.repeat(64) });
    assert.equal(conflict.receipt.error_code, 'destination_exists'); assert.equal(await fs.readFile(direct.destination, 'utf8'), 'hello');
    const metadata = await invoke({ action: 'apply_library_metadata', destination: direct.destination, library_file_id: 'libfile_fixture', version: 3,
      xattrs: [{ name: 'user.library-file-version', value: '3' }], setfattr_path: '/not-installed', getfattr_path: '/not-installed' });
    assert.equal(metadata.receipt.metadata_persistence, 'sidecar');
    const saved = JSON.parse(await fs.readFile(direct.destination + '.library.json', 'utf8'));
    assert.equal(saved.library_file_id, 'libfile_fixture'); assert.equal(saved.sha256, HASH); assert.equal(saved.size_bytes, 5); assert.equal(saved.version, 3);
    console.log('9 CLI behaviors passed including metadata default: direct/NO_PROXY, configured CONNECT proxy, HTTP diagnosis, network diagnosis, integrity rejection, local reuse, existing-file preservation, metadata sidecar.');
  } finally { for (const socket of connections) socket.destroy(); if (proxy) await close(proxy); if (server) await close(server); await fs.rm(root, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
