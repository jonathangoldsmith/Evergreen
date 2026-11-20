import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as core from '../src/amplitude/index.mjs';
import { sha256Hex } from '../src/amplitude/sha256.mjs';
import { scanDir, scanCore } from './helpers/core-scan.mjs';

const coreDir = new URL('../src/amplitude/', import.meta.url).pathname;

test('the pure core imports no node: module and uses no Node global', () => {
  assert.deepEqual(scanDir(coreDir), []);
  assert.ok(Object.keys(core).length > 10);
});

test('the scanner catches planted examples and ignores comments and strings', () => {
  const planted = {
    'import of node:fs': "import { readFileSync } from 'node:fs';\n",
    'import of fs': "import fs from \"fs\";\n",
    'import of node:crypto': "export { createHash } from 'node:crypto';\n",
    'import of lodash': "import _ from 'lodash';\n",
    'import of node:path': "const p = await import('node:path');\n",
    'require': "const fs = require('fs');\n",
    'global process': 'const k = process.env.KEY;\n',
    'global Buffer': "const b = Buffer.from('x');\n",
    'global fetch': 'await fetch(url);\n',
    'global TextEncoder': 'new TextEncoder().encode(s);\n',
    'global setImmediate': 'setImmediate(f);\n',
    'global __dirname': 'join(__dirname, x);\n',
    'in a template expression': 'const s = `value ${process.pid}`;\n',
    'in nested template': 'const s = `a ${`b ${Buffer.alloc(1)}`}`;\n',
  };
  for (const [name, src] of Object.entries(planted)) assert.ok(scanCore(src).length > 0, `missed ${name}`);
  const clean = [
    "import { a } from './events.mjs';\nexport { b } from '../x.mjs';\n",
    '// process.env and Buffer are only mentioned here\nconst x = 1;\n',
    "/* require('fs') fetch */ const y = 'process Buffer fetch';\n",
    'const z = `no ${1 + 1} process here`;\n',
    "throw new Error('uses process');\n",
    'const obj = {}; obj.process; obj.fetch;\n',
  ];
  for (const src of clean) assert.deepEqual(scanCore(src), [], src);
  // and a planted file in a folder is reported by scanDir
  const d = mkdtempSync(join(tmpdir(), 'core-scan-'));
  try {
    writeFileSync(join(d, 'ok.mjs'), "export const a = 1;\n");
    writeFileSync(join(d, 'bad.mjs'), "import fs from 'node:fs';\nexport const b = process.pid;\n");
    assert.deepEqual(scanDir(d), ['bad.mjs: import of node:fs', 'bad.mjs: global process']);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the pure sha256 matches Node for fixed vectors and random inputs, including non-ASCII', () => {
  for (const s of ['', 'abc', 'a'.repeat(55), 'a'.repeat(56), 'a'.repeat(64), 'a'.repeat(1000), 'ünïcødé ✓ 😀', '["usr_0123abcd","workout_completed","occ_89abcdef"]']) {
    assert.equal(sha256Hex(s), createHash('sha256').update(s).digest('hex'), s.slice(0, 20));
  }
  for (let i = 0; i < 50; i += 1) {
    const s = randomBytes(1 + (i * 7) % 200).toString('latin1');
    assert.equal(sha256Hex(s), createHash('sha256').update(s, 'utf8').digest('hex'));
  }
});

// ---- the host is injected: a different hmac, an in-memory store and a fake SDK drive the whole loop ----
const SECRET = 'fake-' + 'a'.repeat(24);
const nodeHmac = (secret, data) => createHmac('sha256', secret).update(data).digest('hex');
const HOST = { hmac: nodeHmac, secret: SECRET };
const U = core.opaqueId('usr', 'person-a', HOST);
const wk = (d, m = 30) => ({ activityType: 'Running', start: `${d}T08:00:00-08:00`, end: `${d}T08:30:00-08:00`, durationMin: m });
const snap = (...workouts) => ({ coverage: { from: '2026-10-01', to: '2026-11-18' }, workouts });

function memoryStore(failures = []) {
  let saved = null;
  let saves = 0;
  return {
    save: (o) => { saves += 1; if (failures.includes(saves)) return { ok: false, error: 'outbox could not be saved' }; saved = JSON.stringify(o); return { ok: true }; },
    load: () => ({ ok: true, outbox: saved === null ? null : JSON.parse(saved) }),
    sync: () => ({ ok: true }),
    peek: () => saved,
  };
}
// the Amplitude iOS SDK: keeps its own queue and deduplicates by insert_id; returns what it accepted
function fakeSdk() {
  const queue = new Map();
  return { queue, handOver: async (events) => { for (const e of events) if (!queue.has(e.insert_id)) queue.set(e.insert_id, e); return { acked: [{ batch: 0, insert_ids: events.map((e) => e.insert_id) }], failed: [] }; } };
}

test('the core works with injected hmac, store and delivery, and never sends anything itself', async () => {
  const store = memoryStore();
  const sdk = fakeSdk();
  const opts = { host: HOST, source: 'phone' };
  let ob = core.newOutbox(U);
  let step = core.commitSnapshot(store, ob, snap(wk('2026-10-19', 30)), opts);
  assert.equal(step.ok, true);
  assert.equal(step.outbox.events.length, 1);
  // the state and the events are saved BEFORE anything is handed over
  assert.equal(JSON.parse(store.peek()).events.length, 1);
  assert.equal(sdk.queue.size, 0);
  // hand over, but "crash" before the acknowledgement is saved
  await sdk.handOver(step.outbox.events);
  const restarted = core.loadOutbox(store, U);
  assert.equal(restarted.ok, true);
  assert.equal(restarted.outbox.events.length, 1);
  // after the restart the unacknowledged events go first (the SDK deduplicates by insert_id)
  const done = await core.deliverOutbox(store, restarted.outbox, sdk.handOver);
  assert.equal(done.outbox.events.length, 0);
  assert.equal(sdk.queue.size, 1);
  step = core.commitSnapshot(store, done.outbox, snap(wk('2026-10-19', 40)), opts);
  assert.equal(step.outbox.events[0].event_properties.supersedes, restarted.outbox.events[0].event_properties.occurrence_id);
  await core.deliverOutbox(store, step.outbox, sdk.handOver);
  assert.equal(sdk.queue.size, 2);
  assert.equal(core.loadOutbox(store, U).outbox.events.length, 0);
});

test('a failed save keeps the old outbox and blocks nothing it should not; a failed ack save keeps the events', async () => {
  const store = memoryStore([2]); // the second save fails
  const sdk = fakeSdk();
  const opts = { host: HOST, source: 'phone' };
  const step = core.commitSnapshot(store, core.newOutbox(U), snap(wk('2026-10-19')), opts);
  assert.equal(step.ok, true);
  const r = await core.deliverOutbox(store, step.outbox, sdk.handOver);
  assert.equal(r.saved.ok, false);
  assert.deepEqual(r.outbox, step.outbox); // the original, still listing the events
  assert.throws(() => core.stageSnapshot(r.outbox, snap(wk('2026-10-19', 40)), opts), /unsent events/);
  const again = await core.deliverOutbox(store, r.outbox, sdk.handOver);
  assert.equal(again.saved.ok, true);
  assert.equal(sdk.queue.size, 1);
  // a store that throws or returns junk is a failed save, never a crash and never success
  for (const bad of [() => { throw new Error('secret path /x'); }, () => null, () => 5]) {
    const broken = { save: bad, load: bad, sync: bad };
    const c = core.commitSnapshot(broken, core.newOutbox(U), snap(wk('2026-10-20')), opts);
    assert.equal(c.ok, false);
    assert.deepEqual(c.outbox, { ...core.newOutbox(U), status: 'unrecovered' }); // a throw or junk may have written: unknown until a load
    assert.ok(!JSON.stringify(c).includes('/x'));
    assert.equal(core.loadOutbox(broken, U).ok, false);
  }
});

test('a store that reports unsynced or unrecovered blocks the outbox until sync or load succeeds', async () => {
  const opts = { host: HOST, source: 'phone' };
  let synced = false;
  const store = {
    save: (o) => ({ ok: false, error: 'outbox directory sync failed', unsynced: true, outbox: o }),
    load: () => ({ ok: true, outbox: null }),
    sync: (o) => { synced = true; return { ok: true }; },
  };
  const step = core.commitSnapshot(store, core.newOutbox(U), snap(wk('2026-10-19')), opts);
  assert.equal(step.ok, false);
  assert.equal(step.outbox.status, 'unsynced');
  await assert.rejects(core.deliverOutbox(store, step.outbox, fakeSdk().handOver), /not synced/);
  assert.throws(() => core.stageSnapshot(step.outbox, snap(wk('2026-10-19', 40)), opts), /not synced/);
  const ok = core.syncOutbox(store, step.outbox);
  assert.equal(synced, true);
  assert.equal(ok.ok, true);
  assert.equal(ok.outbox.status, undefined);
  const lost = core.commitSnapshot({ ...store, save: () => ({ ok: false, error: 'x', unrecovered: true }) }, core.newOutbox(U), snap(wk('2026-10-19')), opts);
  assert.equal(lost.outbox.status, 'unrecovered');
  assert.throws(() => core.stageSnapshot(lost.outbox, snap(wk('2026-10-19', 40)), opts), /unrecovered/);
});

test('the host hmac is required, checked and keyed: ids change with the secret and with the hmac', () => {
  assert.throws(() => core.opaqueId('usr', 'x', {}), /host hmac is required/);
  assert.throws(() => core.opaqueId('usr', 'x', { hmac: nodeHmac }), /TRACKER_ID_SECRET/);
  assert.throws(() => core.opaqueId('usr', 'x', { hmac: nodeHmac, secret: 'short' }), /TRACKER_ID_SECRET/);
  for (const out of ['', 'xyz', 5, null, 'A'.repeat(64), 'a'.repeat(63)]) {
    assert.throws(() => core.opaqueId('usr', 'x', { hmac: () => out, secret: SECRET }), /host hmac failed/);
  }
  const other = { hmac: (secret, data) => createHash('sha256').update(`other${secret}${data}`).digest('hex'), secret: SECRET };
  assert.notEqual(core.opaqueId('usr', 'x', HOST), core.opaqueId('usr', 'x', other));
  assert.notEqual(core.opaqueId('usr', 'x', HOST), core.opaqueId('usr', 'x', { ...HOST, secret: 'other-' + 'b'.repeat(24) }));
  // the whole pipeline runs on any conforming hmac
  const ev = core.eventsFromSnapshot(snap(wk('2026-10-19')), U, { host: other, source: 'mock' }).events;
  assert.equal(ev.length, 1);
});
