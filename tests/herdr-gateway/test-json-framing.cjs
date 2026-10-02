const assert = require('node:assert/strict');
const { Readable } = require('node:stream');
const { readInput } = require('./gateway-js/json_io.cjs');
const stream = chunks => Readable.from(chunks);

(async () => {
  const body = Buffer.from(JSON.stringify({ text: '😀\n'.repeat(14000) }));
  const frame = Buffer.concat([Buffer.from(String(body.length) + '\n'), body]);
  const chunks = [];
  for (let start = 0; start < frame.length; start += 7) chunks.push(frame.subarray(start, start + 7));
  assert.deepEqual(await readInput(stream(chunks), true), JSON.parse(body));
  await assert.rejects(readInput(stream([Buffer.from('8\n{}')]), true), error => error.code === 'incomplete_frame');
  await assert.rejects(readInput(stream([Buffer.from('2\n{}x')]), true), error => error.code === 'frame_length_mismatch');
  await assert.rejects(readInput(stream([Buffer.from('01\n{}')]), true), error => error.code === 'invalid_frame');
  await assert.rejects(readInput(stream([Buffer.from('200\n')]), true, 100), error => error.code === 'input_limit');
  await assert.rejects(readInput(stream([Buffer.from('{}\n{}\n')]), false), error => error.code === 'multiple_inputs');
  assert.deepEqual(await readInput(stream([Buffer.from('{}\n')]), false), {});
  console.log('JSON framing passed: fragmented Unicode, large input, incomplete/extra/invalid frames and input bounds.');
})().catch(error => { console.error(error); process.exitCode = 1; });
