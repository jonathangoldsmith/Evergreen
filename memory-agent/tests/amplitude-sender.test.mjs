import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { scanTree } from './helpers/secret-scan.mjs';
import { buildEvent, opaqueId, send, BATCH_SIZE, URL_ENDPOINT } from '../src/amplitude/node/index.mjs';

const KEY = 'k3y' + 'a1b2c3d4e5f60718293a4b5c6d7e8f';
const IDENV = { TRACKER_ID_SECRET: 'fake-' + 'a'.repeat(24) };
const ENV = { AMPLITUDE_API_KEY: KEY };
const at = new Date('2026-11-18T12:00:00Z');
const mk = (n) => Array.from({ length: n }, (_, i) => buildEvent('comeback_accepted', opaqueId('usr', 'a', IDENV), at, { rec_id: opaqueId('rec', `r${i}`, IDENV), minutes: 20 }, opaqueId('occ', `o${i}`, IDENV)));
const recorder = (status = 200) => {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push({ url, init, body: JSON.parse(init.body) }); return { status }; };
  return { calls, fetchImpl };
};

test('batches of at most 500 are posted to the endpoint with api_key and events', async () => {
  const { calls, fetchImpl } = recorder();
  const r = await send(mk(1203), { fetchImpl, env: ENV });
  assert.equal(BATCH_SIZE, 500);
  assert.deepEqual(calls.map((c) => c.body.events.length), [500, 500, 203]);
  assert.ok(calls.every((c) => c.url === URL_ENDPOINT && c.body.api_key === KEY));
  assert.equal(r.sent, 1203);
  assert.ok(!JSON.stringify(r).includes(KEY));
});

test('refuses without a key, and sends nothing', async () => {
  const { calls, fetchImpl } = recorder();
  await assert.rejects(send(mk(1), { fetchImpl, env: {} }), /AMPLITUDE_API_KEY is not set/);
  assert.equal(calls.length, 0);
});

test('an apiKey argument is ignored: the key comes only from the environment object', async () => {
  const { calls, fetchImpl } = recorder();
  await assert.rejects(send(mk(1), { apiKey: KEY, fetchImpl, env: {} }), /AMPLITUDE_API_KEY is not set/);
  assert.equal(calls.length, 0);
});

test('key comes from the environment variable when no argument is given', async () => {
  const { calls, fetchImpl } = recorder();
  await send(mk(1), { fetchImpl, env: { AMPLITUDE_API_KEY: KEY } });
  assert.equal(calls[0].body.api_key, KEY);
});

test('refuses without a fetch implementation (no real network by default)', async () => {
  await assert.rejects(send(mk(1), { env: ENV }), (e) => !e.message.includes(KEY) && /no fetch/.test(e.message));
});

test('the key is redacted in every failure path: the result carries fixed error text only', async () => {
  const leaky = async () => { throw new Error(`connect failed for ${KEY}`); };
  const badStatus = async () => ({ status: `500 ${KEY}` });
  const noResponse = async () => undefined;
  const texts = [];
  for (const fetchImpl of [leaky, badStatus, noResponse, recorder(429).fetchImpl]) {
    const r = await send(mk(2), { fetchImpl, env: ENV });
    assert.ok(!JSON.stringify(r).includes(KEY));
    assert.equal(r.sent, 0);
    assert.equal(r.failed.length, 1);
    texts.push(r.failed[0].error);
  }
  assert.deepEqual(texts, ['Amplitude request failed', 'Amplitude gave no valid answer', 'Amplitude gave no valid answer', 'Amplitude answered 429']);
  await assert.rejects(send('nope', { fetchImpl: recorder().fetchImpl, env: ENV }), (e) => !e.message.includes(KEY));
});

test('a failed batch stops the run; the result says which insert_ids were acknowledged and which failed', async () => {
  const events = mk(1203);
  const calls = [];
  const fetchImpl = async (u, init) => { calls.push(JSON.parse(init.body).events.length); return { status: calls.length === 2 ? 500 : 200 }; };
  const r = await send(events, { fetchImpl, env: ENV });
  assert.deepEqual(calls, [500, 500]); // the third batch is not attempted
  assert.equal(r.sent, 500);
  assert.deepEqual(r.acked.map((b) => [b.batch, b.insert_ids.length]), [[0, 500]]);
  assert.deepEqual(r.acked[0].insert_ids, events.slice(0, 500).map((e) => e.insert_id));
  assert.deepEqual(r.failed.map((b) => [b.batch, b.insert_ids.length, b.error]), [[1, 500, 'Amplitude answered 500'], [2, 203, 'not attempted after an earlier failure']]);
  assert.deepEqual(r.failed[0].insert_ids, events.slice(500, 1000).map((e) => e.insert_id));
  const ok = await send(events, { fetchImpl: recorder().fetchImpl, env: ENV });
  assert.deepEqual(ok.failed, []);
  assert.equal(ok.acked.reduce((n, b) => n + b.insert_ids.length, 0), 1203);
});

test('dry run returns the payloads, sends nothing, and hides the key', async () => {
  const { calls, fetchImpl } = recorder();
  const r = await send(mk(501), { fetchImpl, env: ENV, dryRun: true });
  assert.equal(calls.length, 0);
  assert.equal(r.dryRun, true);
  assert.deepEqual(r.payloads.map((p) => p.events.length), [500, 1]);
  assert.ok(!JSON.stringify(r).includes(KEY));
  const noKey = await send(mk(1), { dryRun: true, env: {} });
  assert.equal(noKey.payloads.length, 1);
});

test('no file in the repo looks like a key, a secret or a long token', () => {
  const root = new URL('..', import.meta.url).pathname;
  assert.deepEqual(scanTree(root), []);
});

test('the scanner detects planted samples in several shapes', () => {
  const hex = ['a1b2c3d4e5f60718', '293a4b5c6d7e8f90'].join('');
  const b64 = ['QWxhZGRpbjpvcGVuIHNlc2FtZQ', 'QWxhZGRpbjpvcGVuIHNlc2FtZQ12'].join('');
  const samples = {
    variable: `const AMPLITUDE_${'API_KEY'} = ${hex};\n`,
    quoted: `AMPLITUDE_${'API_KEY'}: "${hex}"\n`,
    bare_hex: `${hex}\n`,
    concatenated: `const k = '${hex.slice(0, 11)}' + '${hex.slice(11)}';\n`,
    concatenated_double: `const k = "${hex.slice(0, 5)}" + "${hex.slice(5)}";\n`,
    base64: `token ${b64}\n`,
    long_assignment: `MY_${'SECRET'}="abcdefghij0123456789ZZ"\n`,
    google: `x = '${'AI' + 'za'}${'A'.repeat(30)}'\n`,
    github: `${'gh' + 'p_'}${'a'.repeat(30)}\n`,
    private_key: `${['-----BEGIN RSA PRIVATE', 'KEY-----'].join(' ')}\n`,
  };
  const dir = mkdtempSync(join(tmpdir(), 'scan-'));
  try {
    for (const [name, text] of Object.entries(samples)) writeFileSync(join(dir, `${name}.txt`), text);
    const hits = scanTree(dir);
    for (const name of Object.keys(samples)) assert.ok(hits.some((h) => h.endsWith(`${name}.txt`)), `missed ${name}`);
    writeFileSync(join(dir, 'clean.txt'), 'usr_3f9a1c2b rec_3f9a1c2b nothing to see here\n');
    assert.ok(!scanTree(dir).some((h) => h.endsWith('clean.txt')));
    assert.deepEqual(scanTree(dir, new Set([hex])).filter((h) => h.endsWith('bare_hex.txt')), []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('sender errors never echo caller-supplied or fetch-supplied values', async () => {
  const D = 'DISTINCTIVE9271';
  const e = mk(1)[0];
  const bad = [
    { ...e, event_type: `heartRate:${D}` }, { ...e, user_id: D }, { ...e, insert_id: D }, { ...e, time: D },
    { ...e, event_properties: { ...e.event_properties, minutes: D } }, { ...e, event_properties: { rec_id: D } },
    { ...e, event_properties: { [D]: D } },
  ];
  for (const ev of bad) {
    for (const opts of [{ env: ENV, fetchImpl: recorder().fetchImpl }, { dryRun: true, env: {} }]) {
      await assert.rejects(send([ev], opts), (err) => !err.message.includes(D) && !String(err.stack).includes(D));
    }
  }
  const echoing = async () => { throw new Error(`boom ${D}`); };
  assert.ok(!JSON.stringify(await send([e], { env: ENV, fetchImpl: echoing })).includes(D));
  assert.ok(!JSON.stringify(await send([e], { env: ENV, fetchImpl: async () => ({ status: D }) })).includes(D));
});
