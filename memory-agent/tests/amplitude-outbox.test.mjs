import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as realFs from 'node:fs';
import { createHmac } from 'node:crypto';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import {
  opaqueId, eventsFromSnapshot, newOutbox, syncOutbox, createFileStore, forgetDay as forgetDayNode, restoreForgotten as restoreNode, stageSnapshot, ackOutbox, saveOutbox, loadOutbox, commitSnapshot, deliverOutbox,
} from '../src/amplitude/node/index.mjs';

const ENV_ID = { TRACKER_ID_SECRET: 'fake-' + 'a'.repeat(24) };
const SENDENV = { AMPLITUDE_API_KEY: 'k'.repeat(32), ...ENV_ID };
const U = opaqueId('usr', 'person-a', ENV_ID);
const COVER = { coverage: { from: '2026-10-01', to: '2026-11-18' } };
const wk = (d, minutes = 30) => ({ activityType: 'Running', start: `${d}T08:00:00-08:00`, end: `${d}T08:30:00-08:00`, durationMin: minutes });
const snap = (...workouts) => ({ ...COVER, workouts });
const EMPTY = snap();

// A fake Amplitude: records what it received and drops repeats of an insert_id, like the real one.
function fakeAmplitude(failOnCall = []) {
  const stored = new Map();
  let calls = 0;
  const fetchImpl = async (url, init) => {
    calls += 1;
    if (failOnCall.includes(calls)) return { status: 500 };
    for (const e of JSON.parse(init.body).events) if (!stored.has(e.insert_id)) stored.set(e.insert_id, e);
    return { status: 200 };
  };
  return { fetchImpl, stored, calls: () => calls };
}

// the documented query
const active = (events) => {
  const gone = new Set();
  for (const e of events) {
    if (e.event_properties.supersedes) gone.add(e.event_properties.supersedes);
    if (e.event_type === 'workout_retracted') gone.add(e.event_properties.occurrence_id);
  }
  return events.filter((e) => e.event_type === 'workout_completed' && !gone.has(e.event_properties.occurrence_id));
};

const dir = () => mkdtempSync(join(tmpdir(), 'outbox-'));

test('the exact crash sequence: deliver 30 minutes, crash before the ack is saved, correct to 40, restart', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    // 1. stage and persist the 30-minute workout together with its event, then adopt it
    let outbox = newOutbox(U);
    let step = commitSnapshot(path, outbox, snap(wk('2026-10-19', 30)), { source: 'mock', env: ENV_ID });
    assert.equal(step.ok, true);
    outbox = step.outbox;
    const v1 = outbox.events[0];
    // 2. deliver, then "crash": the ack is never saved (the file still lists the event)
    const { send } = await import('../src/amplitude/node/index.mjs');
    const delivery = await send(outbox.events, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(delivery.failed.length, 0);
    assert.equal(amp.stored.size, 1);
    // 3. restart: load the file, deliver the outbox FIRST (same insert_id, Amplitude deduplicates)
    const loaded = loadOutbox(path, U);
    assert.equal(loaded.ok, true);
    assert.equal(loaded.outbox.events.length, 1);
    const resent = await deliverOutbox(path, loaded.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(resent.saved.ok, true);
    assert.equal(resent.outbox.events.length, 0);
    assert.equal(amp.stored.size, 1); // still one: the resend was a duplicate
    // 4. the workout was corrected to 40 minutes before the retry: now build from the new snapshot
    step = commitSnapshot(path, resent.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID });
    assert.equal(step.ok, true);
    const v2 = step.outbox.events[0];
    assert.equal(v2.event_properties.minutes, 40);
    assert.equal(v2.event_properties.supersedes, v1.event_properties.occurrence_id);
    assert.notEqual(v2.insert_id, v1.insert_id);
    const done = await deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(done.outbox.events.length, 0);
    // Amplitude now holds both, and exactly one live occurrence: the 40-minute one
    assert.equal(amp.stored.size, 2);
    const live = active([...amp.stored.values()]);
    assert.equal(live.length, 1);
    assert.equal(live[0].event_properties.minutes, 40);
    assert.equal(loadOutbox(path, U).outbox.state.workouts[Object.keys(loadOutbox(path, U).outbox.state.workouts)[0]].version, 2);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('staging while events are unsent is refused, so the old events are always resent first', () => {
  const d = dir();
  try {
    const staged = commitSnapshot(join(d, 'o.json'), newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    assert.throws(() => stageSnapshot(staged.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /unsent events/);
    assert.throws(() => commitSnapshot(join(d, 'o.json'), staged.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /unsent events/);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('crash after delivering a retraction: the restored workout gets a new version and is live', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    const run = async (outbox, snapshot) => {
      const step = commitSnapshot(path, outbox, snapshot, { source: 'mock', env: ENV_ID });
      assert.equal(step.ok, true);
      return (await deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV })).outbox;
    };
    let ob = await run(newOutbox(U), snap(wk('2026-10-19')));
    // the retraction is staged and persisted, delivered, and the app crashes before the ack is saved
    const step = commitSnapshot(path, ob, EMPTY, { source: 'mock', env: ENV_ID });
    assert.equal(step.outbox.events[0].event_type, 'workout_retracted');
    const { send } = await import('../src/amplitude/node/index.mjs');
    await send(step.outbox.events, { fetchImpl: amp.fetchImpl, env: SENDENV });
    // restart: resend first, then the workout comes back
    const restarted = loadOutbox(path, U).outbox;
    ob = (await deliverOutbox(path, restarted, { fetchImpl: amp.fetchImpl, env: SENDENV })).outbox;
    ob = await run(ob, snap(wk('2026-10-19')));
    const all = [...amp.stored.values()];
    assert.equal(all.length, 3);
    assert.equal(active(all).length, 1);
    const entry = Object.values(ob.state.workouts)[0];
    assert.equal(entry.live, true);
    assert.equal(entry.version, 2);
    assert.equal(new Set(all.map((e) => e.insert_id)).size, 3);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('versions always increase and insert_id depends only on user, type and occurrence', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    let ob = newOutbox(U);
    const seen = [];
    for (const minutes of [30, 40, 35, 50]) {
      const step = commitSnapshot(path, ob, snap(wk('2026-10-19', minutes)), { source: 'mock', env: ENV_ID });
      ob = (await deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV })).outbox;
      seen.push(Object.values(ob.state.workouts)[0].version);
    }
    assert.deepEqual(seen, [1, 2, 3, 4]);
    assert.equal(active([...amp.stored.values()]).length, 1);
    assert.equal(active([...amp.stored.values()])[0].event_properties.minutes, 50);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('an outbox write failure keeps the old state and returns a failure; the step can be retried', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const first = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    assert.equal(first.ok, true);
    const before = readFileSync(file, 'utf8');
    const failing = {
      write: { ...realFs, writeSync: () => { throw new Error(`disk full ${path}`); } },
      fsync: { ...realFs, fsyncSync: () => { throw new Error('no fsync'); } },
      rename: { ...realFs, renameSync: () => { throw new Error('no rename'); } },
      open: { ...realFs, openSync: () => { throw new Error('no open'); } },
      // the temp file reads back differently from what was written
      tempMismatch: { ...realFs, readFileSync: (p, ...rest) => { const t = realFs.readFileSync(p, ...rest); return String(p).includes('.tmp') ? `${t} ` : t; } },
    };
    const delivered = first.outbox.events.map((e) => e.insert_id);
    const acked = ackOutbox(first.outbox, delivered);
    for (const [name, fs] of Object.entries(failing)) {
      const bad = saveOutbox(path, acked, { fs });
      assert.equal(bad.ok, false, name);
      assert.ok(!JSON.stringify(bad).includes(d), name); // no path in the error
      assert.ok(!JSON.stringify(bad).includes('disk full'), name);
      assert.equal(readFileSync(file, 'utf8'), before, name); // the old file is untouched
      assert.deepEqual(readdirSync(join(d, U)), ['outbox.json'], name); // no temp file left behind
    }
    // commitSnapshot returns the OLD outbox on a failed save, so the old state is kept
    const old = ackOutbox(first.outbox, delivered);
    const step = commitSnapshot(path, old, snap(wk('2026-10-19', 45)), { source: 'mock', env: ENV_ID, fs: failing.rename });
    assert.equal(step.ok, false);
    assert.deepEqual(step.outbox, loadOutbox(path, U).outbox); // the caller holds what is really on disk
    assert.equal(readFileSync(file, 'utf8'), before);
    // the retry with a working disk succeeds and builds the same version 2
    const retry = commitSnapshot(path, old, snap(wk('2026-10-19', 45)), { source: 'mock', env: ENV_ID });
    assert.equal(retry.ok, true);
    assert.equal(retry.outbox.events[0].event_properties.minutes, 45);
    // a read-back that does not match the written file is a failure, never a success
    const finalMismatch = { ...realFs, readFileSync: (p, ...rest) => { const t = realFs.readFileSync(p, ...rest); return String(p) === file ? `${t} ` : t; } };
    assert.equal(saveOutbox(path, retry.outbox, { fs: finalMismatch }).ok, false);
    // a folder that does not exist
    writeFileSync(join(d, 'rootfile'), '');
    assert.equal(saveOutbox(join(d, 'rootfile'), retry.outbox).ok, false); // a root that is a file
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('loadOutbox reports a missing, unreadable or invalid file instead of success', () => {
  const d = dir();
  try {
    assert.deepEqual(loadOutbox(d, U), { ok: true, outbox: null });
    realFs.mkdirSync(join(d, U));
    const file = join(d, U, 'outbox.json');
    writeFileSync(file, '{not json');
    assert.deepEqual(loadOutbox(d, U), { ok: false, error: 'outbox is invalid' });
    writeFileSync(file, JSON.stringify({ user: U, state: { user: U, workouts: {} }, events: [{ event_type: 'heart_rate_sample' }] }));
    assert.equal(loadOutbox(d, U).ok, false);
    rmSync(file);
    realFs.mkdirSync(file); // a folder is not a file
    assert.equal(loadOutbox(d, U).ok, false);
    assert.equal(loadOutbox(d, 'Sam').ok, false);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('partial batch failure: the outbox keeps the unacknowledged events, and a retry sends only those', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const days = Array.from({ length: 1203 }, (_, i) => wk(new Date(Date.UTC(2026, 9, 1) + (i % 28) * 86400000).toISOString().slice(0, 10)));
    // 1203 workouts need distinct starts: spread them over minutes of the day
    const many = days.map((w, i) => ({ ...w, start: `${w.start.slice(0, 11)}${String(Math.floor(i / 28 / 60) % 24).padStart(2, '0')}:${String((Math.floor(i / 28)) % 60).padStart(2, '0')}:00-08:00`, end: undefined }));
    const step = commitSnapshot(path, newOutbox(U), { ...COVER, workouts: many }, { source: 'mock', env: ENV_ID });
    assert.equal(step.ok, true);
    assert.equal(step.outbox.events.length, 1203);
    const amp = fakeAmplitude([2]); // the second batch fails
    const r1 = await deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(r1.saved.ok, true);
    assert.equal(r1.delivery.acked.length, 1);
    assert.equal(r1.outbox.events.length, 703); // 1203 - 500
    assert.equal(loadOutbox(path, U).outbox.events.length, 703); // persisted
    const r2 = await deliverOutbox(path, loadOutbox(path, U).outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(r2.outbox.events.length, 0);
    assert.equal(amp.stored.size, 1203);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('full success: the outbox is empty and the next identical snapshot emits nothing', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    const step = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19'), wk('2026-10-20')), { source: 'mock', env: ENV_ID });
    const done = await deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(done.outbox.events.length, 0);
    assert.equal(done.saved.ok, true);
    assert.equal(amp.stored.size, 2);
    const again = commitSnapshot(path, loadOutbox(path, U).outbox, snap(wk('2026-10-19'), wk('2026-10-20')), { source: 'mock', env: ENV_ID });
    assert.equal(again.outbox.events.length, 0);
    // delivering an empty outbox sends nothing
    const calls = amp.calls();
    await deliverOutbox(path, again.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(amp.calls(), calls);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the outbox file holds no exact timestamp, key or secret', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const exact = '2026-10-19T08:47:31-08:00';
    const step = commitSnapshot(path, newOutbox(U), snap({ ...wk('2026-10-19'), start: exact, end: '2026-10-19T09:17:31-08:00' }), { source: 'mock', env: ENV_ID });
    const text = readFileSync(file, 'utf8');
    for (const raw of ['08:47', ':47:31', String(Date.parse(exact)), 'fake-', 'k'.repeat(32), 'heartRate']) assert.ok(!text.includes(raw), raw);
    assert.equal(step.ok, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

const readsOf = (path, plan) => {
  // plan(n, text) -> text or throws; n counts reads of the final file only
  let n = 0;
  return { ...realFs, readFileSync: (p, ...rest) => {
    const t = realFs.readFileSync(p, ...rest);
    if (String(p) !== path) return t;
    n += 1;
    return plan(n, t);
  } };
};

test('the outbox is rebuilt from an allowlist: raw data in state, entries or the outbox is rejected, never saved or loaded', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const D = 'RAWVALUE4417';
  try {
    const good = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const key = Object.keys(good.state.workouts)[0];
    const dirty = {
      'outbox name': { ...good, name: D },
      'outbox heartRate': { ...good, heartRate: [D] },
      'state route': { ...good, state: { ...good.state, route: [[D]] } },
      'state name': { ...good, state: { ...good.state, name: D } },
      'entry samples': { ...good, state: { ...good.state, workouts: { [key]: { ...good.state.workouts[key], samples: [D] } } } },
      'entry name': { ...good, state: { ...good.state, workouts: { [key]: { ...good.state.workouts[key], name: D } } } },
      'entry start': { ...good, state: { ...good.state, workouts: { [key]: { ...good.state.workouts[key], start: D } } } },
    };
    const before = readFileSync(file, 'utf8');
    for (const [name, o] of Object.entries(dirty)) {
      const r = saveOutbox(path, o);
      assert.equal(r.ok, false, name);
      assert.ok(!JSON.stringify(r).includes(D), name);
      assert.equal(readFileSync(file, 'utf8'), before, name);
      // a file that already contains it is rejected on load, and nothing from it is returned
      writeFileSync(file, JSON.stringify(o));
      const loaded = loadOutbox(path, U);
      writeFileSync(file, before);
      assert.equal(loaded.ok, false, name);
      assert.ok(!JSON.stringify(loaded).includes(D), name);
      assert.throws(() => stageSnapshot(o, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), (e) => !e.message.includes(D), name);
      if (/^(state|entry)/.test(name)) assert.throws(() => eventsFromSnapshot(snap(wk('2026-10-19')), U, { source: 'mock', env: ENV_ID, sent: o.state }), (e) => !e.message.includes(D), name);
    }
    // events are rebuilt by the sender's validator: extra fields are stripped, in memory, on disk and on load
    const U2 = opaqueId('usr', 'person-b', ENV_ID);
    const ev = commitSnapshot(path, newOutbox(U2), snap(wk('2026-10-20')), { source: 'mock', env: ENV_ID }).outbox;
    const evil = { ...ev, events: ev.events.map((e) => ({ ...e, user_properties: { name: D }, event_properties: { ...e.event_properties, heartRate: D, route: [D] } })) };
    assert.ok(!JSON.stringify(saveOutbox(path, evil)).includes(D));
    const file2 = join(d, U2, 'outbox.json');
    assert.ok(!readFileSync(file2, 'utf8').includes(D));
    writeFileSync(file2, JSON.stringify(evil));
    assert.ok(!JSON.stringify(loadOutbox(path, U2)).includes(D));
    assert.ok(!JSON.stringify(ackOutbox(evil, [])).includes(D));
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a failed save of the acknowledgements returns the original outbox, blocks staging, and the retry succeeds', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    const step = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const original = step.outbox;
    const brokenDisk = { ...realFs, writeSync: () => { throw new Error('disk full'); } };
    const r1 = await deliverOutbox(path, original, { fetchImpl: amp.fetchImpl, env: SENDENV, fs: brokenDisk });
    assert.equal(amp.stored.size, 1); // it was delivered...
    assert.equal(r1.saved.ok, false);
    assert.deepEqual(r1.outbox, original); // ...but the cleared state is NOT returned
    assert.equal(r1.outbox.events.length, 1);
    assert.throws(() => stageSnapshot(r1.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /unsent events/);
    // retry with a working disk: the same insert_id is sent again, Amplitude deduplicates, the save succeeds
    const r2 = await deliverOutbox(path, r1.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(r2.saved.ok, true);
    assert.equal(r2.outbox.events.length, 0);
    assert.equal(amp.stored.size, 1);
    assert.equal(loadOutbox(path, U).outbox.events.length, 0);
    const next = commitSnapshot(path, r2.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID });
    assert.equal(next.outbox.events[0].event_properties.supersedes, original.events[0].event_properties.occurrence_id);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a final read-back that fails once is retried and the save succeeds', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const once = readsOf(file, (n, t) => { if (n === 1) throw new Error('transient'); return t; });
    assert.deepEqual(saveOutbox(path, staged, { fs: once }), { ok: true });
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('an unreadable final file after the rename is unrecovered: staging is blocked until loadOutbox succeeds, with no version reuse and no lost events', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  const amp = fakeAmplitude();
  try {
    const unreadable = readsOf(file, () => { throw new Error('io error'); });
    const step = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19', 30)), { source: 'mock', env: ENV_ID, fs: unreadable });
    assert.equal(step.ok, false);
    assert.equal(step.outbox.status, 'unrecovered');
    // blocked everywhere
    for (const f of [
      () => stageSnapshot(step.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }),
      () => commitSnapshot(path, step.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }),
      () => ackOutbox(step.outbox, []),
    ]) assert.throws(f, /unrecovered/);
    await assert.rejects(deliverOutbox(path, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV }), /unrecovered/);
    assert.equal(saveOutbox(path, step.outbox).ok, false);
    // the file on disk does hold the staged version 1 events: loading recovers them
    const loaded = loadOutbox(path, U);
    assert.equal(loaded.ok, true);
    assert.equal(loaded.outbox.status, undefined);
    assert.equal(loaded.outbox.events.length, 1);
    assert.equal(Object.values(loaded.outbox.state.workouts)[0].version, 1);
    // staging stays refused until those events are delivered; then the correction is version 2
    assert.throws(() => stageSnapshot(loaded.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /unsent events/);
    const done = await deliverOutbox(path, loaded.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    const fix = commitSnapshot(path, done.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID });
    await deliverOutbox(path, fix.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    const all = [...amp.stored.values()];
    assert.equal(all.length, 2);
    assert.equal(new Set(all.map((e) => e.insert_id)).size, 2);
    assert.equal(active(all).length, 1);
    assert.equal(active(all)[0].event_properties.minutes, 40);
    assert.equal(Object.values(loadOutbox(path, U).outbox.state.workouts)[0].version, 2);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('valid but different content on disk after the rename is adopted, so staged events are not overwritten or versions reused', async () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const a = commitSnapshot(path, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const other = stageSnapshot(newOutbox(U), snap(wk('2026-10-25')), { source: 'mock', env: ENV_ID });
    const swapped = readsOf(file, () => JSON.stringify(other));
    const staged = stageSnapshot(ackOutbox(a.outbox, a.outbox.events.map((e) => e.insert_id)), snap(wk('2026-10-19', 45)), { source: 'mock', env: ENV_ID });
    const r = saveOutbox(path, staged, { fs: swapped });
    assert.equal(r.ok, false);
    assert.deepEqual(r.outbox, other); // the caller adopts what the disk holds
    const c = commitSnapshot(path, ackOutbox(a.outbox, a.outbox.events.map((e) => e.insert_id)), snap(wk('2026-10-19', 45)), { source: 'mock', env: ENV_ID, fs: swapped });
    assert.equal(c.ok, false);
    assert.deepEqual(c.outbox, other);
    assert.throws(() => stageSnapshot(c.outbox, snap(wk('2026-10-19', 50)), { source: 'mock', env: ENV_ID }), /unsent events/); // other's events are still pending
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

// a recording fs: every operation in order, with the path behind each file descriptor
function recordingFs(overrides = {}) {
  const log = [];
  const paths = new Map();
  const fs = {
    ...realFs,
    openSync: (p, ...rest) => { const fd = realFs.openSync(p, ...rest); paths.set(fd, String(p)); log.push(['open', String(p)]); return fd; },
    writeSync: (fd, ...rest) => { log.push(['write', paths.get(fd)]); return realFs.writeSync(fd, ...rest); },
    fsyncSync: (fd) => { log.push(['fsync', paths.get(fd)]); return realFs.fsyncSync(fd); },
    closeSync: (fd) => { log.push(['close', paths.get(fd)]); return realFs.closeSync(fd); },
    renameSync: (a, b) => { log.push(['rename', String(b)]); return realFs.renameSync(a, b); },
    unlinkSync: (p) => { log.push(['unlink', String(p)]); return realFs.unlinkSync(p); },
    readFileSync: (p, ...rest) => { log.push(['read', String(p)]); return realFs.readFileSync(p, ...rest); },
    ...overrides,
  };
  return { fs, log };
}
const idx = (log, op, pred) => log.findIndex(([o, p]) => o === op && pred(p));

test('the folder is synced after the rename and before success is reported', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const { fs, log } = recordingFs();
    assert.deepEqual(saveOutbox(path, staged, { fs }), { ok: true });
    const isTmp = (p) => p.includes('.tmp');
    const fsyncTmp = idx(log, 'fsync', isTmp);
    const readTmp = idx(log, 'read', isTmp);
    const rename = idx(log, 'rename', (p) => p === file);
    const fsyncDir = idx(log, 'fsync', (p) => p === join(d, U));
    const readFinal = idx(log, 'read', (p) => p === file);
    for (const i of [fsyncTmp, readTmp, rename, fsyncDir, readFinal]) assert.ok(i >= 0);
    assert.ok(fsyncTmp < readTmp && readTmp < rename && rename < fsyncDir && fsyncDir < readFinal, JSON.stringify(log));
    assert.equal(idx(log, 'close', (p) => p === join(d, U)) > fsyncDir, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a failed folder sync fails the save, except the platform not-supported codes', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    realFs.mkdirSync(join(d, U)); // the user folder exists, so only the file's own folder sync is exercised
    const failDir = (code) => recordingFs({ fsyncSync: (fd) => { if (realFs.fstatSync(fd).isDirectory()) { const e = new Error('x'); e.code = code; throw e; } return realFs.fsyncSync(fd); } }).fs;
    for (const code of ['EIO', 'ENOSPC', 'EBADF', undefined]) {
      const r = saveOutbox(path, staged, { fs: failDir(code) });
      assert.equal(r.ok, false, String(code));
      assert.equal(r.error, 'outbox directory sync failed');
      assert.deepEqual(r.outbox, staged); // the rename happened; the disk holds the intended content
      assert.ok(!JSON.stringify(r).includes(d));
    }
    for (const code of ['ENOTSUP', 'EOPNOTSUPP']) assert.deepEqual(saveOutbox(path, staged, { fs: failDir(code) }), { ok: true }, code);
    for (const code of ['EINVAL', 'EPERM', 'EISDIR']) {
      assert.equal(saveOutbox(path, staged, { fs: failDir(code), platform: 'linux' }).ok, false, `linux ${code}`);
      assert.equal(saveOutbox(path, staged, { fs: failDir(code), platform: 'win32' }).ok, true, `win32 ${code}`);
    }
    // an open() failure on the folder behaves the same way
    const noOpenDir = recordingFs({ openSync: (p, ...rest) => { if (String(p) === join(d, U)) { const e = new Error('x'); e.code = 'EACCES'; throw e; } return realFs.openSync(p, ...rest); } }).fs;
    assert.equal(saveOutbox(path, staged, { fs: noOpenDir }).ok, false);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a leftover temp file is removed and the folder synced after the removal', () => {
  const d = dir();
  const path = d; // the root
  const file = join(d, U, 'outbox.json');
  try {
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const { fs, log } = recordingFs({ readFileSync: (p, ...rest) => { const t = realFs.readFileSync(p, ...rest); return String(p).includes('.tmp') ? `${t} ` : t; } });
    assert.equal(saveOutbox(path, staged, { fs }).ok, false);
    const unlink = idx(log, 'unlink', (p) => p.includes('.tmp'));
    const fsyncDir = idx(log, 'fsync', (p) => p === join(d, U));
    assert.ok(unlink >= 0 && fsyncDir > unlink, JSON.stringify(log));
    assert.equal(idx(log, 'rename', () => true), -1); // never renamed
    assert.deepEqual(readdirSync(join(d, U)), []);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

const failDirSync = (code = 'EIO') => recordingFs({ fsyncSync: (fd) => { if (realFs.fstatSync(fd).isDirectory()) { const e = new Error('x'); e.code = code; throw e; } return realFs.fsyncSync(fd); } }).fs;

test('a failed folder sync marks the outbox unsynced: delivery and staging are refused until a sync retry succeeds', async () => {
  const d = dir();
  const amp = fakeAmplitude();
  try {
    realFs.mkdirSync(join(d, U));
    const step = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID, fs: failDirSync() });
    assert.equal(step.ok, false);
    assert.equal(step.outbox.status, 'unsynced');
    assert.equal(step.outbox.events.length, 1); // the disk holds the staged content
    // everything that could build on or deliver from it is refused
    await assert.rejects(deliverOutbox(d, step.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV }), /not synced/);
    assert.equal(amp.calls(), 0);
    assert.throws(() => stageSnapshot(step.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /not synced/);
    assert.throws(() => commitSnapshot(d, step.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /not synced/);
    assert.throws(() => ackOutbox(step.outbox, []), /not synced/);
    assert.equal(saveOutbox(d, step.outbox).ok, false);
    // a retry of the sync that fails again keeps it unsynced
    const again = syncOutbox(d, step.outbox, { fs: failDirSync() });
    assert.equal(again.ok, false);
    assert.equal(again.outbox.status, 'unsynced');
    await assert.rejects(deliverOutbox(d, again.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV }), /not synced/);
    // a retry that succeeds verifies the file and lifts the block
    const fixed = syncOutbox(d, step.outbox);
    assert.equal(fixed.ok, true);
    assert.equal(fixed.outbox.status, undefined);
    assert.deepEqual(fixed.outbox, { user: U, state: step.outbox.state, events: step.outbox.events });
    const done = await deliverOutbox(d, fixed.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV });
    assert.equal(done.saved.ok, true);
    assert.equal(amp.stored.size, 1);
    // syncOutbox only accepts an unsynced outbox; and it re-verifies the file: different content is adopted
    assert.equal(syncOutbox(d, done.outbox).ok, false);
    const stale = { ...step.outbox }; // says "unsynced, one event" but the disk now holds the acknowledged outbox
    const adopt = syncOutbox(d, stale);
    assert.equal(adopt.ok, false);
    assert.deepEqual(adopt.outbox, done.outbox);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('loadOutbox syncs the folder too, so a loaded outbox is durable', () => {
  const d = dir();
  try {
    commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    assert.equal(loadOutbox(d, U).ok, true);
    const r = loadOutbox(d, U, { fs: failDirSync() });
    assert.equal(r.ok, false);
    assert.equal(r.error, 'outbox directory sync failed');
    assert.equal(r.outbox, undefined);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a failed folder sync after the ack save blocks the next step until synced', async () => {
  const d = dir();
  const amp = fakeAmplitude();
  try {
    const staged = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const r = await deliverOutbox(d, staged.outbox, { fetchImpl: amp.fetchImpl, env: SENDENV, fs: failDirSync() });
    assert.equal(r.saved.ok, false);
    assert.equal(r.outbox.status, 'unsynced');
    assert.equal(r.outbox.events.length, 0); // the ack is on disk, but not known durable
    assert.throws(() => stageSnapshot(r.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }), /not synced/);
    const ok = syncOutbox(d, r.outbox);
    assert.equal(ok.ok, true);
    assert.equal(commitSnapshot(d, ok.outbox, snap(wk('2026-10-19', 40)), { source: 'mock', env: ENV_ID }).ok, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the path is derived from root and the validated user id; ../, absolute paths and other users cannot be reached', () => {
  const d = dir();
  const root = join(d, 'root');
  try {
    const good = commitSnapshot(root, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const U2 = opaqueId('usr', 'person-b', ENV_ID);
    assert.deepEqual(readdirSync(root), [U]);
    assert.deepEqual(readdirSync(join(root, U)), ['outbox.json']);
    // hostile user ids and roots never touch the disk
    const outside = join(d, 'outside');
    for (const user of ['../outside', '../../x', '/etc', `/${outside}`, 'usr_../..', 'usr_3f9a1c2b/../../x', 'Sam', '', null, { toString: () => U }]) {
      const o = { ...good, user };
      assert.equal(saveOutbox(root, o).ok, false, String(user));
      assert.equal(loadOutbox(root, user).ok, false, String(user));
      assert.throws(() => stageSnapshot(o, snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }), undefined, String(user));
    }
    for (const bad of ['', null, 5, undefined, ['x']]) {
      assert.equal(saveOutbox(bad, good).ok, false);
      assert.equal(loadOutbox(bad, U).ok, false);
    }
    assert.deepEqual(readdirSync(d).sort(), ['root']); // nothing was created next to root
    assert.deepEqual(readdirSync(root), [U]);
    // another user's outbox is a different file and is never overwritten
    const other = commitSnapshot(root, newOutbox(U2), snap(wk('2026-10-25')), { source: 'mock', env: ENV_ID }).outbox;
    const before2 = readFileSync(join(root, U2, 'outbox.json'), 'utf8');
    commitSnapshot(root, ackOutbox(good, good.events.map((e) => e.insert_id)), snap(wk('2026-10-19', 45)), { source: 'mock', env: ENV_ID });
    assert.equal(readFileSync(join(root, U2, 'outbox.json'), 'utf8'), before2);
    assert.deepEqual(readdirSync(root).sort(), [U, U2].sort());
    // a file in one user's folder that belongs to another user is refused on load
    writeFileSync(join(root, U, 'outbox.json'), before2);
    assert.equal(loadOutbox(root, U).ok, false);
    assert.equal(loadOutbox(root, U2).ok, true);
    assert.ok(other);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('an event whose user_id differs from the outbox user is rejected on save, on load and everywhere else', () => {
  const d = dir();
  try {
    const U2 = opaqueId('usr', 'person-b', ENV_ID);
    const mine = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const theirs = stageSnapshot(newOutbox(U2), snap(wk('2026-10-20')), { source: 'mock', env: ENV_ID });
    const mixed = { ...mine, events: [...mine.events, ...theirs.events] };
    const swapped = { ...mine, events: theirs.events };
    const before = readFileSync(join(d, U, 'outbox.json'), 'utf8');
    for (const o of [mixed, swapped]) {
      assert.equal(saveOutbox(d, o).ok, false);
      assert.equal(readFileSync(join(d, U, 'outbox.json'), 'utf8'), before);
      assert.throws(() => ackOutbox(o, []), /another user/);
      writeFileSync(join(d, U, 'outbox.json'), JSON.stringify(o));
      assert.equal(loadOutbox(d, U).ok, false);
      writeFileSync(join(d, U, 'outbox.json'), before);
    }
    assert.equal(loadOutbox(d, U).ok, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});


test('missing directories are created one level at a time, and the parent of each is synced', () => {
  const d = dir();
  try {
    const root = join(d, 'a', 'b');
    const log = [];
    const paths = new Map();
    const fs = {
      ...realFs,
      mkdirSync: (p, ...rest) => { log.push(['mkdir', String(p)]); return realFs.mkdirSync(p, ...rest); },
      openSync: (p, ...rest) => { const fd = realFs.openSync(p, ...rest); paths.set(fd, String(p)); return fd; },
      fsyncSync: (fd) => { log.push(['fsync', paths.get(fd)]); return realFs.fsyncSync(fd); },
    };
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    assert.deepEqual(saveOutbox(root, staged, { fs }), { ok: true });
    const dirOps = log.filter(([, p]) => !p.includes('.tmp') && !p.endsWith('outbox.json'));
    const up = [];
    for (let p = join(root, U); up[up.length - 1] !== p; p = dirname(p)) up.push(p); // the folder and every ancestor
    assert.deepEqual(dirOps, [
      ['mkdir', join(d, 'a')], ['fsync', d],
      ['mkdir', root], ['fsync', join(d, 'a')],
      ['mkdir', join(root, U)], ['fsync', root],
      ...up.map((p) => ['fsync', p]), // after the rename: the user folder and every ancestor up to the filesystem root
    ]);
    // existing directories are not created or synced again
    log.length = 0;
    assert.deepEqual(saveOutbox(root, staged, { fs }), { ok: true });
    assert.equal(log.filter(([o]) => o === 'mkdir').length, 0);
    // a sync failure on a created directory's parent fails the save and leaves no outbox file
    const root2 = join(d, 'c', 'd');
    const failing = { ...fs, fsyncSync: (fd) => { if (paths.get(fd) === d) { const e = new Error('x'); e.code = 'EIO'; throw e; } return realFs.fsyncSync(fd); } };
    assert.equal(saveOutbox(root2, staged, { fs: failing }).ok, false);
    assert.equal(realFs.existsSync(join(root2, U, 'outbox.json')), false);
    // the tolerated codes still apply
    const tolerant = { ...fs, fsyncSync: (fd) => { if (paths.get(fd) === d) { const e = new Error('x'); e.code = 'ENOTSUP'; throw e; } return realFs.fsyncSync(fd); } };
    assert.equal(saveOutbox(join(d, 'e', 'f'), staged, { fs: tolerant }).ok, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the file store validates and rebuilds the outbox itself: raw data passed straight to save or found by load never reaches disk or the caller', () => {
  const d = dir();
  const D = 'RAWVALUE5581';
  try {
    const good = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const file = join(d, U, 'outbox.json');
    const before = readFileSync(file, 'utf8');
    const store = createFileStore({ root: d, userId: U });
    const key = Object.keys(good.state.workouts)[0];
    const dirty = {
      name: { ...good, name: D },
      heartRate: { ...good, heartRate: [D] },
      route: { ...good, state: { ...good.state, route: [[D]] } },
      samples: { ...good, state: { ...good.state, workouts: { [key]: { ...good.state.workouts[key], samples: [D] } } } },
      status: { ...good, status: 'unsynced' },
      another: { ...good, user: opaqueId('usr', 'person-b', ENV_ID) },
      key: { ...good, apiKey: D },
    };
    for (const [name, o] of Object.entries(dirty)) {
      const r = store.save(o);
      assert.equal(r.ok, false, name);
      assert.ok(!JSON.stringify(r).includes(D), name);
      assert.equal(readFileSync(file, 'utf8'), before, name);
      assert.equal(store.sync(o).ok, false, name);
      writeFileSync(file, JSON.stringify(o));
      const l = store.load();
      assert.equal(l.ok, false, name);
      assert.ok(!JSON.stringify(l).includes(D), name);
      writeFileSync(file, before);
    }
    // events are rebuilt: extra fields are stripped from what is written and from what is loaded
    const evil = { ...good, events: [{ ...good.events[0] ?? {}, user_properties: { name: D } }] };
    const fresh = stageSnapshot(newOutbox(U), snap(wk('2026-10-22')), { source: 'mock', env: ENV_ID });
    const withExtras = { ...fresh, events: fresh.events.map((e) => ({ ...e, user_properties: { name: D }, event_properties: { ...e.event_properties, heartRate: D } })) };
    assert.equal(store.save(withExtras).ok, true);
    assert.ok(!readFileSync(file, 'utf8').includes(D));
    writeFileSync(file, JSON.stringify(withExtras));
    const loaded = store.load();
    assert.equal(loaded.ok, true);
    assert.ok(!JSON.stringify(loaded).includes(D));
    assert.ok(evil);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('every save syncs the user folder and each ancestor up to the root parent, so a retry after a failed parent sync syncs it again', () => {
  const d = dir();
  try {
    const root = join(d, 'root');
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    let failParent = true;
    const { fs: recording, log } = recordingFs();
    const paths = new Map();
    const flaky = {
      ...recording,
      openSync: (p, ...rest) => { const fd = recording.openSync(p, ...rest); paths.set(fd, String(p)); return fd; },
      fsyncSync: (fd) => {
        if (paths.get(fd) === d && failParent) { const e = new Error('x'); e.code = 'EIO'; throw e; }
        return recording.fsyncSync(fd);
      },
    };
    // 1. the root is created, but syncing its parent fails: the save is not reported as a success
    const first = saveOutbox(root, staged, { fs: flaky });
    assert.equal(first.ok, false);
    assert.equal(realFs.existsSync(root), true); // the directory it created remains
    // 2. the retry finds the directories, and must still sync the parent before reporting success
    failParent = false;
    log.length = 0;
    assert.deepEqual(saveOutbox(root, staged, { fs: flaky }), { ok: true });
    const synced = log.filter(([o]) => o === 'fsync').map(([, p]) => p);
    for (const p of [join(root, U), root, d]) assert.ok(synced.includes(p), `not synced: ${p}`);
    // 3. and a parent sync that keeps failing keeps the save from succeeding
    failParent = true;
    assert.equal(saveOutbox(root, staged, { fs: flaky }).ok, false);
    assert.equal(createFileStore({ root, userId: U, fs: flaky }).load().ok, false);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('a host store error text is never passed on: only fixed messages survive', async () => {
  const D = 'Sam heart rate 150 key abc123';
  const opts = { host: { hmac: (secret, data) => createHmac('sha256', secret).update(data).digest('hex'), secret: ENV_ID.TRACKER_ID_SECRET }, source: 'mock' };
  const bad = (extra = {}) => ({ save: () => ({ ok: false, error: D, ...extra }), load: () => ({ ok: false, error: D }), sync: () => ({ ok: false, error: D, ...extra }) });
  const core = await import('../src/amplitude/index.mjs');
  const staged = core.stageSnapshot(core.newOutbox(U), snap(wk('2026-10-19')), opts);
  for (const extra of [{}, { unsynced: true, outbox: staged }, { unrecovered: true }]) {
    const c = core.commitSnapshot(bad(extra), core.newOutbox(U), snap(wk('2026-10-20')), opts);
    assert.equal(c.ok, false);
    assert.equal(c.error, 'store failed');
    assert.ok(!JSON.stringify(c).includes('Sam'));
    const r = await core.deliverOutbox(bad(extra), staged, async (events) => ({ acked: [{ batch: 0, insert_ids: events.map((e) => e.insert_id) }], failed: [] }));
    assert.equal(r.saved.error, 'store failed');
    assert.ok(!JSON.stringify(r).includes('Sam'));
  }
  const l = core.loadOutbox(bad(), U);
  assert.deepEqual(l, { ok: false, error: 'store failed' });
  const synced = core.syncOutbox(bad(), { ...staged, status: 'unsynced' });
  assert.equal(synced.error, 'store failed');
  assert.ok(!JSON.stringify(synced).includes('Sam'));
  // a store's own fixed messages are kept
  assert.equal(core.commitSnapshot({ save: () => ({ ok: false, error: 'outbox directory sync failed' }), load: () => ({ ok: true, outbox: null }) }, core.newOutbox(U), snap(wk('2026-10-20')), opts).error, 'outbox directory sync failed');
});

const coreMod = await import('../src/amplitude/index.mjs');
const HOSTC = { hmac: (secret, data) => createHmac('sha256', secret).update(data).digest('hex'), secret: ENV_ID.TRACKER_ID_SECRET };
const OPTS = { host: HOSTC, source: 'mock' };
const memory = () => {
  let saved = null;
  return { save: (o) => { saved = JSON.stringify(o); return { ok: true }; }, load: () => ({ ok: true, outbox: saved === null ? null : JSON.parse(saved) }), sync: () => ({ ok: true }), peek: () => saved };
};
const sdkAll = async (events) => ({ acked: [{ batch: 0, insert_ids: events.map((e) => e.insert_id) }], failed: [] });

test('a store that reports success without keeping the data fails the save and blocks the outbox until loadOutbox (stage, acknowledgement, forget)', async () => {
  const staged = coreMod.stageSnapshot(coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS);
  const liars = {
    'keeps nothing': { save: () => ({ ok: true }), load: () => ({ ok: true, outbox: null }) },
    'keeps the old content': (() => { const old = coreMod.newOutbox(U); return { save: () => ({ ok: true }), load: () => ({ ok: true, outbox: old }) }; })(),
    'keeps different content': { save: (o) => ({ ok: true, _o: o }), load: () => ({ ok: true, outbox: { ...staged, events: staged.events.map((e) => ({ ...e, event_properties: { ...e.event_properties, minutes: 99 } })) } }) },
    'load throws': { save: () => ({ ok: true }), load: () => { throw new Error('boom'); } },
    'load fails': { save: () => ({ ok: true }), load: () => ({ ok: false, error: 'x' }) },
    'load returns junk': { save: () => ({ ok: true }), load: () => 5 },
    'load returns a blocked outbox': { save: () => ({ ok: true }), load: () => ({ ok: true, outbox: { ...staged, status: 'unsynced' } }) },
  };
  for (const [name, liar] of Object.entries(liars)) {
    const store = { ...liar, sync: () => ({ ok: true }) };
    const c = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS);
    assert.equal(c.ok, false, `stage: ${name}`);
    assert.equal(c.error, 'outbox read-back did not match', name);
    assert.deepEqual(c.outbox, { ...coreMod.newOutbox(U), status: 'unrecovered' }, name); // the old state, blocked until loadOutbox
    // the acknowledgement save is proved the same way
    const r = await coreMod.deliverOutbox(store, staged, sdkAll);
    assert.equal(r.saved.ok, false, `ack: ${name}`);
    assert.deepEqual(r.outbox, { ...staged, status: 'unrecovered' }, name); // the original, still listing the events, blocked
    const f = coreMod.forgetDay(store, staged, '2026-10-19');
    assert.equal(f.ok, false, `forget: ${name}`);
    assert.deepEqual(f.outbox, { ...staged, status: 'unrecovered' }, name);
  }
  // an honest store passes
  const honest = memory();
  assert.equal(coreMod.commitSnapshot(honest, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS).ok, true);
});

const pendingOutbox = (...days) => coreMod.stageSnapshot(coreMod.newOutbox(U), snap(...days.map((d) => wk(d))), OPTS);
const active2 = (events) => active(events);

test('forgetDay: a pending event is removed and its occurrence is retracted, since its delivery may be uncertain', async () => {
  const store = memory();
  const staged = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19'), wk('2026-10-20')), OPTS).outbox;
  assert.equal(staged.events.length, 2);
  const forgottenOcc = staged.events.find((e) => e.event_properties.local_date === '2026-10-19').event_properties.occurrence_id;
  const f = coreMod.forgetDay(store, staged, '2026-10-19');
  assert.equal(f.ok, true);
  assert.deepEqual(f.outbox.events.filter((e) => e.event_type === 'workout_completed').map((e) => e.event_properties.local_date), ['2026-10-20']);
  assert.deepEqual(f.outbox.events.filter((e) => e.event_type === 'workout_retracted').map((e) => e.event_properties.occurrence_id), [forgottenOcc]);
  assert.equal(Object.keys(f.outbox.state.workouts).length, 1);
  assert.deepEqual(f.outbox.state.forgotten, ['2026-10-19']);
  assert.equal(JSON.parse(store.peek()).events.length, 2); // persisted with read-back
  // restart: the outbox is loaded and delivered; the forgotten completed event never goes out
  const sent = [];
  const restarted = coreMod.loadOutbox(store, U).outbox;
  const done = await coreMod.deliverOutbox(store, restarted, async (events) => { sent.push(...events); return sdkAll(events); });
  assert.equal(sent.filter((e) => e.event_type === 'workout_completed').length, 1);
  assert.ok(sent.filter((e) => e.event_type === 'workout_completed').every((e) => e.event_properties.local_date === '2026-10-20'));
  assert.equal(active2(sent).length, 1);
  assert.equal(done.outbox.events.length, 0);
});

test('forgetDay: a delivered event gets a retraction staged, and later snapshots of that day emit nothing', async () => {
  const store = memory();
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19'), wk('2026-10-20')), OPTS).outbox;
  ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
  assert.equal(active2(sdk).length, 2);
  const f = coreMod.forgetDay(store, ob, '2026-10-19');
  assert.equal(f.ok, true);
  assert.deepEqual(f.outbox.events.map((e) => e.event_type), ['workout_retracted']);
  assert.equal(f.outbox.events[0].event_properties.utc_offset_minutes, -480);
  assert.equal(Object.keys(f.outbox.state.workouts).length, 1);
  ob = (await coreMod.deliverOutbox(store, f.outbox, deliver)).outbox;
  assert.equal(active2(sdk).length, 1); // analytics stopped counting the forgotten day
  assert.equal(active2(sdk)[0].event_properties.local_date, '2026-10-20');
  // a later snapshot that still contains the forgotten day's workout emits nothing, whatever its content
  const again = coreMod.commitSnapshot(store, ob, snap(wk('2026-10-19'), wk('2026-10-20'), { ...wk('2026-10-19'), id: 'wk_0123abcd', durationMin: 55 }), OPTS);
  assert.equal(again.ok, true);
  assert.deepEqual(again.outbox.events, []);
  assert.deepEqual(again.outbox.state.forgotten, ['2026-10-19']);
  // forgetting is idempotent and holds dates only
  const twice = coreMod.forgetDay(store, again.outbox, '2026-10-19');
  assert.equal(twice.ok, true);
  assert.deepEqual(twice.outbox.events, []);
  assert.deepEqual(twice.outbox.state.forgotten, ['2026-10-19']);
  assert.ok(!JSON.stringify(store.peek()).includes('08:00'));
});

test('forgetDay: a pending correction of a delivered workout retracts the delivered version', async () => {
  const store = memory();
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS).outbox;
  ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
  ob = coreMod.commitSnapshot(store, ob, snap(wk('2026-10-19', 45)), OPTS).outbox; // version 2 pending, version 1 delivered
  assert.equal(ob.events[0].event_properties.supersedes != null, true);
  const f = coreMod.forgetDay(store, ob, '2026-10-19');
  const retracted = f.outbox.events.map((e) => e.event_properties.occurrence_id).sort();
  assert.deepEqual(f.outbox.events.map((e) => e.event_type), ['workout_retracted', 'workout_retracted']);
  assert.deepEqual(retracted, [ob.events[0].event_properties.occurrence_id, ob.events[0].event_properties.supersedes].sort());
  await coreMod.deliverOutbox(store, f.outbox, deliver);
  assert.equal(active2(sdk).length, 0);
  assert.throws(() => coreMod.forgetDay(store, ob, '2026-02-30'), /invalid local date/);
  assert.throws(() => coreMod.forgetDay(store, ob, 'Sam'), /invalid local date/);
});

test('forgetDay: a failed save keeps the old outbox, and the file store carries it', () => {
  const d = dir();
  try {
    const ob = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const before = readFileSync(join(d, U, 'outbox.json'), 'utf8');
    const bad = forgetDayNode(d, ob, '2026-10-19', { fs: { ...realFs, renameSync: () => { throw new Error('no rename'); } } });
    assert.equal(bad.ok, false);
    assert.equal(readFileSync(join(d, U, 'outbox.json'), 'utf8'), before);
    const good = forgetDayNode(d, ob, '2026-10-19');
    assert.equal(good.ok, true);
    assert.deepEqual(loadOutbox(d, U).outbox, good.outbox);
    assert.deepEqual(good.outbox.state.forgotten, ['2026-10-19']);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('every save syncs every ancestor up to the filesystem root, and a higher ancestor that failed is synced again on the retry', () => {
  const d = dir();
  try {
    const root = join(d, 'root');
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    const ancestors = [];
    for (let p = join(root, U); ancestors[ancestors.length - 1] !== p; p = dirname(p)) ancestors.push(p);
    assert.ok(ancestors.length >= 4);
    const high = dirname(dirname(d)); // two levels above the root's parent
    assert.ok(ancestors.includes(high));
    let failHigh = true;
    const { fs: recording, log } = recordingFs();
    const paths = new Map();
    const flaky = {
      ...recording,
      openSync: (p, ...rest) => { const fd = recording.openSync(p, ...rest); paths.set(fd, String(p)); return fd; },
      fsyncSync: (fd) => {
        if (paths.get(fd) === high && failHigh) { const e = new Error('x'); e.code = 'EIO'; throw e; }
        return recording.fsyncSync(fd);
      },
    };
    const first = saveOutbox(root, staged, { fs: flaky });
    assert.equal(first.ok, false);
    assert.equal(first.error, 'outbox directory sync failed');
    assert.deepEqual(first.outbox, staged); // the content is on disk; it is just not known durable
    failHigh = false;
    log.length = 0;
    assert.deepEqual(saveOutbox(root, staged, { fs: flaky }), { ok: true });
    const synced = new Set(log.filter(([o]) => o === 'fsync').map(([, p]) => p));
    for (const p of ancestors) assert.ok(synced.has(p), `not synced: ${p}`);
    // the tolerated codes still apply at every level
    const tolerant = { ...flaky, fsyncSync: (fd) => { if (paths.get(fd) === high) { const e = new Error('x'); e.code = 'ENOTSUP'; throw e; } return recording.fsyncSync(fd); } };
    assert.deepEqual(saveOutbox(root, staged, { fs: tolerant }), { ok: true });
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the doc states the rounding, the forget rule, the read-back proof and the ancestor sync, and stays short', () => {
  const doc = readFileSync(new URL('../docs/AMPLITUDE.md', import.meta.url), 'utf8');
  for (const word of ['forgetDay', 'rounded', 'load()']) assert.ok(doc.includes(word), word);
  assert.ok(doc.split(/\s+/).filter(Boolean).length <= 800);
});

// a store whose save really persists, but whose load can be made to fail or lie
function flakyStore() {
  let saved = null;
  const mode = { load: 'ok', fake: null };
  return {
    mode,
    save: (o) => { saved = JSON.stringify(o); return { ok: true }; },
    load: () => {
      if (mode.load === 'fail') return { ok: false, error: 'outbox could not be read' };
      if (mode.load === 'different') return { ok: true, outbox: mode.fake };
      return { ok: true, outbox: saved === null ? null : JSON.parse(saved) };
    },
    sync: () => ({ ok: true }),
    peek: () => (saved === null ? null : JSON.parse(saved)),
  };
}
const BLOCKED = (ob) => {
  assert.equal(ob.status, 'unrecovered');
  assert.throws(() => coreMod.stageSnapshot(ob, snap(wk('2026-10-21')), OPTS), /unrecovered/);
  assert.throws(() => coreMod.ackOutbox(ob, []), /unrecovered/);
  assert.throws(() => coreMod.forgetDay(memory(), ob, '2026-10-21'), /unrecovered/);
};

test('save ok but load fails: the outbox is unrecovered, and after loadOutbox the staged events are not lost', async () => {
  const store = flakyStore();
  const base = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS).outbox;
  const delivered = (await coreMod.deliverOutbox(store, base, sdkAll)).outbox;
  store.mode.load = 'fail';
  const c = coreMod.commitSnapshot(store, delivered, snap(wk('2026-10-19'), wk('2026-10-20')), OPTS);
  assert.equal(c.ok, false);
  assert.equal(c.error, 'outbox read-back did not match');
  BLOCKED(c.outbox);
  await assert.rejects(coreMod.deliverOutbox(store, c.outbox, sdkAll), /unrecovered/);
  assert.equal(store.peek().events.length, 1); // the staged event really is on disk
  // load still failing: nothing can be adopted
  assert.equal(coreMod.loadOutbox(store, U).ok, false);
  // load works again: its content (with the staged event) is adopted, nothing is lost or overwritten
  store.mode.load = 'ok';
  const back = coreMod.loadOutbox(store, U);
  assert.equal(back.ok, true);
  assert.equal(back.outbox.status, undefined);
  assert.equal(back.outbox.events.length, 1);
  assert.equal(back.outbox.events[0].event_properties.local_date, '2026-10-20');
  assert.throws(() => coreMod.stageSnapshot(back.outbox, snap(wk('2026-10-19'), wk('2026-10-20')), OPTS), /unsent events/);
  const sent = [];
  const done = await coreMod.deliverOutbox(store, back.outbox, async (events) => { sent.push(...events); return sdkAll(events); });
  assert.equal(sent.length, 1);
  assert.equal(done.outbox.events.length, 0);
});

test('save ok but load returns different content: the truth is what loadOutbox returns, and a forget is not lost', async () => {
  const store = flakyStore();
  const base = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19'), wk('2026-10-20')), OPTS).outbox;
  const delivered = (await coreMod.deliverOutbox(store, base, sdkAll)).outbox;
  // the forget is saved for real, but the read-back shows the old content
  store.mode.load = 'different';
  store.mode.fake = delivered;
  const f = coreMod.forgetDay(store, delivered, '2026-10-19');
  assert.equal(f.ok, false);
  BLOCKED(f.outbox);
  assert.deepEqual(store.peek().state.forgotten, ['2026-10-19']);
  // a retry cannot overwrite it: every operation is blocked until loadOutbox succeeds
  assert.throws(() => coreMod.forgetDay(store, f.outbox, '2026-10-20'), /unrecovered/);
  assert.deepEqual(store.peek().state.forgotten, ['2026-10-19']);
  store.mode.load = 'ok';
  const back = coreMod.loadOutbox(store, U);
  assert.equal(back.ok, true);
  assert.deepEqual(back.outbox.state.forgotten, ['2026-10-19']);
  assert.deepEqual(back.outbox.events.map((e) => e.event_type), ['workout_retracted']);
  // the adopted outbox is usable: deliver the retraction, then a snapshot still containing the forgotten day emits nothing
  const done = (await coreMod.deliverOutbox(store, back.outbox, sdkAll)).outbox;
  const again = coreMod.commitSnapshot(store, done, snap(wk('2026-10-19'), wk('2026-10-20')), OPTS);
  assert.equal(again.ok, true);
  assert.deepEqual(again.outbox.events, []);
  // an acknowledgement save that cannot be read back is unrecovered too, with the original events still listed
  const st2 = flakyStore();
  const pending = coreMod.commitSnapshot(st2, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS).outbox;
  st2.mode.load = 'different';
  st2.mode.fake = pending;
  const r = await coreMod.deliverOutbox(st2, pending, sdkAll);
  assert.equal(r.saved.ok, false);
  assert.deepEqual(r.outbox, { ...pending, status: 'unrecovered' });
  st2.mode.load = 'ok';
  assert.equal(coreMod.loadOutbox(st2, U).outbox.events.length, 0); // the ack really was saved
});

const wkId = (d, id = 'wk_0123abcd', m = 30) => ({ ...wk(d, m), id });

test('forgetting a workout stores a tombstone of its key: a start corrected to another date emits nothing', async () => {
  const store = memory();
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-10-19'), wk('2026-10-22')), OPTS).outbox;
  ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
  const f = coreMod.forgetDay(store, ob, '2026-10-19');
  assert.equal(f.ok, true);
  // the tombstone is the workout's keyed hash and a version: no raw id, date or time
  assert.equal(f.outbox.state.tombstones.length, 1);
  assert.deepEqual(Object.keys(f.outbox.state.tombstones[0]).sort(), ['key', 'restored', 'version']);
  assert.match(f.outbox.state.tombstones[0].key, /^occ_[0-9a-f]{16}$/);
  assert.ok(!JSON.stringify(f.outbox.state).includes('wk_0123abcd'));
  ob = (await coreMod.deliverOutbox(store, f.outbox, deliver)).outbox;
  // the same workout, start corrected to another day (same stable id): nothing is emitted, whatever date it carries
  for (const day of ['2026-10-19', '2026-10-25', '2026-11-02']) {
    const c = coreMod.commitSnapshot(store, ob, snap(wkId(day), wk('2026-10-22')), OPTS);
    assert.equal(c.ok, true, day);
    assert.deepEqual(c.outbox.events, [], day);
    ob = c.outbox;
  }
  assert.equal(active2(sdk).length, 1); // only the 22nd is counted
  // the other workout is unaffected and a different id on the forgotten day is also ignored (date block)
  assert.equal(coreMod.commitSnapshot(store, ob, snap(wkId('2026-10-19', 'wk_89abcdef'), wk('2026-10-22')), OPTS).outbox.events.length, 0);
});

test('a delivered workout that is forgotten: one retraction, never reactivated; restoring continues the version history', async () => {
  const store = memory();
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-10-19')), OPTS).outbox;
  ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
  const v1 = sdk[0];
  const f = coreMod.forgetDay(store, ob, '2026-10-19');
  assert.deepEqual(f.outbox.events.map((e) => e.event_type), ['workout_retracted']);
  ob = (await coreMod.deliverOutbox(store, f.outbox, deliver)).outbox;
  assert.equal(active2(sdk).length, 0);
  // forgetting again, or resending, never retracts twice and never reactivates
  const again = coreMod.forgetDay(store, ob, '2026-10-19');
  assert.deepEqual(again.outbox.events, []);
  assert.equal(coreMod.commitSnapshot(store, again.outbox, snap(wkId('2026-10-19')), OPTS).outbox.events.length, 0);
  assert.equal(sdk.filter((e) => e.event_type === 'workout_retracted').length, 1);
  // restoring is explicit; the workout then returns as a NEW version, which the earlier retraction cannot cancel
  const r = coreMod.restoreForgotten(store, again.outbox);
  assert.equal(r.ok, true);
  assert.deepEqual(r.outbox.state.forgotten, []);
  assert.equal(r.outbox.state.tombstones.every((t) => t.restored), true);
  const back = coreMod.commitSnapshot(store, r.outbox, snap(wkId('2026-10-19')), OPTS);
  assert.equal(back.outbox.events.length, 1);
  const v2 = back.outbox.events[0];
  assert.notEqual(v2.insert_id, v1.insert_id);
  assert.notEqual(v2.event_properties.occurrence_id, v1.event_properties.occurrence_id);
  assert.equal('supersedes' in v2.event_properties, false);
  await coreMod.deliverOutbox(store, back.outbox, deliver);
  assert.equal(active2(sdk).length, 1);
  assert.equal(active2(sdk)[0].insert_id, v2.insert_id);
  assert.equal(Object.values(coreMod.loadOutbox(store, U).outbox.state.workouts)[0].version, 2); // 1, forgotten and retracted, restored as 2
});

test('malformed tombstones are rejected, and old states without them load as empty', () => {
  const good = coreMod.newOutbox(U);
  const key = opaqueId('occ', 'k', ENV_ID);
  const withT = (t) => ({ ...good, state: { ...good.state, tombstones: t } });
  assert.doesNotThrow(() => coreMod.checkOutbox(withT([{ key, version: 1, restored: false }])));
  for (const bad of ['x', [null], [{ key, version: 1 }], [{ key: 'Sam', version: 1, restored: false }], [{ key, version: 0, restored: false }],
    [{ key, version: 1, restored: false, id: 'wk_0123abcd' }], [{ key, version: 1, restored: false }, { key, version: 2, restored: true }]]) {
    assert.throws(() => coreMod.checkOutbox(withT(bad)), /sent has an invalid tombstone|invalid tombstone/, JSON.stringify(bad));
  }
  const { tombstones: _t, ...legacy } = good.state;
  assert.deepEqual(coreMod.checkOutbox({ ...good, state: legacy }).state.tombstones, []);
});

test('abandoned temp files with a forgotten day are removed durably before a forget, a save or a load is accepted', () => {
  const d = dir();
  try {
    const staged = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19'), wk('2026-10-20')), { source: 'mock', env: ENV_ID });
    const userDir = join(d, U);
    const text = JSON.stringify(staged.outbox);
    const marker = staged.outbox.events[0].insert_id;
    // a crash left temp files behind: the fixed name and an old per-process name, both holding the day's events
    writeFileSync(join(userDir, '.outbox.json.tmp'), text);
    writeFileSync(join(userDir, '.outbox.json.tmp-4242'), text);
    realFs.mkdirSync(join(userDir, '.outbox.json.tmp-dir')); // not a regular file: left alone
    const filesWith = (needle) => readdirSync(userDir).filter((n) => { try { return realFs.lstatSync(join(userDir, n)).isFile() && readFileSync(join(userDir, n), 'utf8').includes(needle); } catch { return false; } });
    assert.ok(filesWith(marker).length >= 3);
    const date = staged.outbox.events[0].event_properties.local_date;
    const f = forgetDayNode(d, staged.outbox, date);
    assert.equal(f.ok, true);
    assert.deepEqual(filesWith(marker), []); // no file under the user directory holds the forgotten event any more
    assert.deepEqual(readdirSync(userDir).sort(), ['.outbox.json.tmp-dir', 'outbox.json']);
    // a load also removes abandoned temp files, and syncs the folder afterwards
    writeFileSync(join(userDir, '.outbox.json.tmp'), text);
    const { fs, log } = recordingFs();
    assert.equal(loadOutbox(d, U, { fs }).ok, true);
    assert.equal(readdirSync(userDir).includes('.outbox.json.tmp'), false);
    const unlink = idx(log, 'unlink', (p) => p.endsWith('.outbox.json.tmp'));
    assert.ok(unlink >= 0 && idx(log, 'fsync', (p) => p === userDir) > unlink, JSON.stringify(log));
    // a save removes them too
    writeFileSync(join(userDir, '.outbox.json.tmp-7'), text);
    assert.equal(saveOutbox(d, f.outbox).ok, true);
    assert.equal(readdirSync(userDir).includes('.outbox.json.tmp-7'), false);
    // if a leftover cannot be removed, the operation is refused: a forget is complete only when none remain
    writeFileSync(join(userDir, '.outbox.json.tmp'), text);
    const stuck = { ...realFs, unlinkSync: () => { throw new Error('busy'); } };
    assert.equal(saveOutbox(d, f.outbox, { fs: stuck }).ok, false);
    assert.equal(forgetDayNode(d, f.outbox, '2026-10-20', { fs: stuck }).ok, false);
    assert.equal(loadOutbox(d, U, { fs: stuck }).ok, false);
    assert.equal(realFs.existsSync(join(userDir, '.outbox.json.tmp')), true);
    // restoreForgotten is available through the Node wrapper too
    rmSync(join(userDir, '.outbox.json.tmp'));
    assert.equal(restoreNode(d, f.outbox).ok, true);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the temp file has a fixed name, with no process id', () => {
  const d = dir();
  try {
    const { fs, log } = recordingFs();
    const staged = stageSnapshot(newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID });
    assert.equal(saveOutbox(d, staged, { fs }).ok, true);
    const tmps = [...new Set(log.filter(([o, p]) => o === 'open' && p.includes('.tmp')).map(([, p]) => p))];
    assert.deepEqual(tmps, [join(d, U, '.outbox.json.tmp')]);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('removing an abandoned temp file is made durable before the operation is accepted', () => {
  const d = dir();
  try {
    const staged = commitSnapshot(d, newOutbox(U), snap(wk('2026-10-19')), { source: 'mock', env: ENV_ID }).outbox;
    const userDir = join(d, U);
    const file = join(userDir, 'outbox.json');
    const before = readFileSync(file, 'utf8');
    writeFileSync(join(userDir, '.outbox.json.tmp'), 'left behind');
    const paths = new Map();
    const noDirSync = {
      ...realFs,
      openSync: (p, ...rest) => { const fd = realFs.openSync(p, ...rest); paths.set(fd, String(p)); return fd; },
      fsyncSync: (fd) => { if (paths.get(fd) === userDir) { const e = new Error('x'); e.code = 'EIO'; throw e; } return realFs.fsyncSync(fd); },
    };
    const r = saveOutbox(d, staged, { fs: noDirSync });
    assert.equal(r.ok, false);
    assert.equal(r.error, 'outbox could not be saved'); // refused at the cleanup, before anything was written
    assert.equal(readFileSync(file, 'utf8'), before);
    writeFileSync(join(userDir, '.outbox.json.tmp'), 'left behind again'); // the failed attempt already removed the first
    assert.equal(loadOutbox(d, U, { fs: noDirSync }).error, 'outbox could not be read');
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('an accepted event whose acknowledgement was not saved is retracted when its day is forgotten', async () => {
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  const real = memory();
  let saves = 0;
  const store = { ...real, save: (o) => { saves += 1; return saves === 2 ? { ok: false, error: 'outbox could not be saved' } : real.save(o); } };
  const staged = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-10-19')), OPTS).outbox; // save 1
  const r = await coreMod.deliverOutbox(store, staged, deliver); // the SDK accepts; save 2 (the acknowledgement) fails
  assert.equal(r.saved.ok, false);
  assert.equal(sdk.length, 1); // delivered, but still pending
  assert.equal(r.outbox.events.length, 1);
  const f = coreMod.forgetDay(store, r.outbox, '2026-10-19');
  assert.equal(f.ok, true);
  assert.deepEqual(f.outbox.events.map((e) => e.event_type), ['workout_retracted']);
  assert.equal(f.outbox.events[0].event_properties.occurrence_id, sdk[0].event_properties.occurrence_id);
  assert.equal(f.outbox.state.tombstones.length, 1);
  await coreMod.deliverOutbox(store, f.outbox, deliver);
  assert.equal(active2(sdk).length, 0); // without the retraction the delivered workout would stay active
  assert.deepEqual(coreMod.commitSnapshot(store, coreMod.loadOutbox(store, U).outbox, snap(wkId('2026-10-19')), OPTS).outbox.events, []);
});

test('a delivered workout corrected from day A to day B (correction pending): forgetting A or B retracts and tombstones it', async () => {
  for (const forget of ['2026-10-19', '2026-10-25']) {
    const store = memory();
    const sdk = [];
    const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
    let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-10-19'), wk('2026-10-22')), OPTS).outbox;
    ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
    ob = coreMod.commitSnapshot(store, ob, snap(wkId('2026-10-25'), wk('2026-10-22')), OPTS).outbox; // v2 on day B, pending
    assert.equal(ob.events.length, 1);
    const entry = Object.values(ob.state.workouts).find((e) => e.day === '2026-10-25');
    assert.deepEqual(entry.prior, ['2026-10-19']); // the earlier day is kept with the entry (dates only)
    const f = coreMod.forgetDay(store, ob, forget);
    assert.equal(f.ok, true, forget);
    const types = f.outbox.events.map((e) => e.event_type);
    assert.deepEqual(types, ['workout_retracted', 'workout_retracted'], forget); // v1 and the pending v2
    assert.equal(f.outbox.state.tombstones.length, 1, forget);
    assert.equal(Object.keys(f.outbox.state.workouts).length, 1, forget); // only the 22nd remains
    await coreMod.deliverOutbox(store, f.outbox, deliver);
    assert.equal(active2(sdk).length, 1, forget);
    assert.equal(active2(sdk)[0].event_properties.local_date, '2026-10-22', forget);
    // the workout, on either date, is ignored afterwards
    const later = coreMod.commitSnapshot(store, coreMod.loadOutbox(store, U).outbox, snap(wkId('2026-10-19'), wkId('2026-11-03'), wk('2026-10-22')), OPTS);
    assert.deepEqual(later.outbox.events, [], forget);
  }
  // several corrections keep every earlier date
  const store = memory();
  const deliver = async (events) => sdkAll(events);
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-10-19')), OPTS).outbox;
  for (const day of ['2026-10-20', '2026-10-21', '2026-10-19']) {
    ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
    ob = coreMod.commitSnapshot(store, ob, snap(wkId(day)), OPTS).outbox;
  }
  const entry = Object.values(ob.state.workouts)[0];
  assert.equal(entry.day, '2026-10-19');
  assert.deepEqual(entry.prior, ['2026-10-20', '2026-10-21']); // the current day is not repeated in prior
  assert.equal(coreMod.forgetDay(store, ob, '2026-10-20').outbox.state.tombstones.length, 1);
  assert.throws(() => coreMod.checkOutbox({ ...ob, state: { ...ob.state, workouts: { [Object.keys(ob.state.workouts)[0]]: { ...entry, prior: ['Sam'] } } } }), /invalid entry/);
});

test('a workout skipped because its day was forgotten first is tombstoned: the same id on another day stays ignored', async () => {
  const store = memory();
  // the day is forgotten before the workout ever entered the outbox
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-22')), OPTS).outbox;
  ob = coreMod.forgetDay(store, ob, '2026-10-19').outbox;
  assert.equal(ob.state.tombstones.length, 0);
  const drain = async (o) => (await coreMod.deliverOutbox(store, o, sdkAll)).outbox;
  ob = await drain(ob);
  const first = coreMod.commitSnapshot(store, ob, snap(wk('2026-10-22'), wkId('2026-10-19')), OPTS); // skipped by the date block
  assert.equal(first.ok, true);
  assert.deepEqual(first.outbox.events, []);
  assert.equal(first.outbox.state.tombstones.length, 1); // its key was recorded
  assert.deepEqual(Object.keys(first.outbox.state.tombstones[0]).sort(), ['key', 'restored', 'version']);
  assert.ok(!JSON.stringify(first.outbox.state).includes('wk_0123abcd'));
  // later the same workout (same id) is corrected to another day: still ignored
  for (const day of ['2026-10-25', '2026-11-02']) {
    const later = coreMod.commitSnapshot(store, first.outbox, snap(wk('2026-10-22'), wkId(day)), OPTS);
    assert.deepEqual(later.outbox.events, [], day);
  }
  // a different workout on another day is not affected, and the tombstone is not added twice
  const other = coreMod.commitSnapshot(store, first.outbox, snap(wk('2026-10-22'), wkId('2026-10-19'), wkId('2026-10-26', 'wk_89abcdef')), OPTS);
  assert.equal(other.outbox.events.length, 1);
  assert.equal(other.outbox.state.tombstones.length, 1);
  // restoring lets it back in, continuing after version 1
  const restored = coreMod.restoreForgotten(store, await drain(other.outbox)).outbox;
  const back = coreMod.commitSnapshot(store, restored, snap(wk('2026-10-22'), wkId('2026-10-25'), wkId('2026-10-26', 'wk_89abcdef')), OPTS);
  assert.equal(back.outbox.events.length, 1);
  assert.equal(back.outbox.events[0].event_properties.local_date, '2026-10-25');
});

test('the doc says plainly that a retraction does not delete data in Amplitude, and the code does not claim a missing source file', () => {
  const doc = readFileSync(new URL('../docs/AMPLITUDE.md', import.meta.url), 'utf8');
  assert.match(doc, /Amplitude keeps the original event/);
  const src = readFileSync(new URL('../src/amplitude/events.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(src, /src\/facts\/constants/);
  assert.doesNotMatch(doc, /fact engine/);
});

test('a forgotten stable key is resolved across the whole snapshot: a live occurrence is retracted, and no other record of it is emitted', async () => {
  const store = memory();
  const sdk = [];
  const deliver = async (events) => { sdk.push(...events); return sdkAll(events); };
  let ob = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wkId('2026-11-20'), wk('2026-11-22')), OPTS).outbox;
  ob = (await coreMod.deliverOutbox(store, ob, deliver)).outbox;
  ob = coreMod.forgetDay(store, ob, '2026-11-19').outbox; // nothing is recorded on the 19th yet
  assert.equal(ob.state.tombstones.length, 0);
  // the workout recorded on the 20th is corrected (same id) onto the forgotten 19th
  const c = coreMod.commitSnapshot(store, ob, snap(wkId('2026-11-19'), wk('2026-11-22')), OPTS);
  assert.equal(c.ok, true);
  assert.deepEqual(c.outbox.events.map((e) => e.event_type), ['workout_retracted']);
  assert.equal(c.outbox.events[0].event_properties.occurrence_id, sdk.find((e) => e.event_properties.local_date === '2026-11-20').event_properties.occurrence_id);
  assert.equal(c.outbox.state.tombstones.length, 1);
  assert.equal(Object.keys(c.outbox.state.workouts).length, 1); // only the 22nd remains
  await coreMod.deliverOutbox(store, c.outbox, deliver);
  assert.equal(active2(sdk).length, 1); // the 20th occurrence is no longer live
  assert.equal(active2(sdk)[0].event_properties.local_date, '2026-11-22');

  // a snapshot containing the workout on both dates (same id) emits nothing of it, with or without an earlier record
  for (const withEarlier of [true, false]) {
    const st = memory();
    const log = [];
    let o2 = coreMod.newOutbox(U);
    if (withEarlier) {
      o2 = coreMod.commitSnapshot(st, o2, snap(wkId('2026-11-20')), OPTS).outbox;
      o2 = (await coreMod.deliverOutbox(st, o2, async (events) => { log.push(...events); return sdkAll(events); })).outbox;
    }
    o2 = coreMod.forgetDay(st, o2, '2026-11-19').outbox;
    const both = coreMod.commitSnapshot(st, o2, snap(wkId('2026-11-19'), wkId('2026-11-20')), OPTS);
    assert.equal(both.ok, true);
    assert.deepEqual(both.outbox.events.filter((e) => e.event_type === 'workout_completed'), [], `earlier=${withEarlier}`);
    assert.equal(both.outbox.events.filter((e) => e.event_type === 'workout_retracted').length, withEarlier ? 1 : 0);
    assert.equal(both.outbox.state.tombstones.length, 1);
    assert.equal(Object.keys(both.outbox.state.workouts).length, 0);
    // either order of the two records gives the same result
    const rev = coreMod.commitSnapshot(st, o2, snap(wkId('2026-11-20'), wkId('2026-11-19')), OPTS);
    assert.deepEqual(rev.outbox, both.outbox);
  }
});

// a store that really writes, and then throws (or answers with junk)
function writesThenThrows(mode) {
  const real = memory();
  const flags = { armed: false };
  return {
    flags,
    save: (o) => {
      const r = real.save(o);
      if (!flags.armed) return r;
      if (mode === 'throw') throw new Error('crash after the write');
      return 'written';
    },
    load: real.load,
    sync: real.sync,
    peek: real.peek,
  };
}

test('a store that writes and then throws leaves the outbox unrecovered until a read-back; committed events are not overwritten', async () => {
  for (const mode of ['throw', 'junk']) {
    const store = writesThenThrows(mode);
    const base = coreMod.commitSnapshot(store, coreMod.newOutbox(U), snap(wk('2026-10-19')), OPTS).outbox;
    const delivered = (await coreMod.deliverOutbox(store, base, sdkAll)).outbox;
    store.flags.armed = true;
    const c = coreMod.commitSnapshot(store, delivered, snap(wk('2026-10-19'), wk('2026-10-20')), OPTS);
    assert.equal(c.ok, false, mode);
    assert.equal(c.outbox.status, 'unrecovered', mode);
    assert.equal(JSON.parse(store.peek()).events.length, 1); // the new outbox really is persisted
    // nothing can be staged, delivered, forgotten or acknowledged on the old state
    assert.throws(() => coreMod.stageSnapshot(c.outbox, snap(wk('2026-10-21')), OPTS), /unrecovered/);
    await assert.rejects(coreMod.deliverOutbox(store, c.outbox, sdkAll), /unrecovered/);
    assert.throws(() => coreMod.forgetDay(store, c.outbox, '2026-10-19'), /unrecovered/);
    assert.throws(() => coreMod.restoreForgotten(store, c.outbox), /unrecovered/);
    // the re-read establishes the persisted state: it holds the committed event
    const back = coreMod.loadOutbox(store, U);
    assert.equal(back.ok, true);
    assert.equal(back.outbox.events.length, 1);
    assert.equal(back.outbox.events[0].event_properties.local_date, '2026-10-20');
    // the acknowledgement save and a forget behave the same way
    const ack = await coreMod.deliverOutbox(store, back.outbox, sdkAll);
    assert.equal(ack.outbox.status, 'unrecovered', mode);
    assert.equal(ack.saved.ok, false);
    const reloaded = coreMod.loadOutbox(store, U).outbox;
    assert.equal(reloaded.events.length, 0); // the ack really was written
    const f = coreMod.forgetDay(store, reloaded, '2026-10-19');
    assert.equal(f.ok, false);
    assert.equal(f.outbox.status, 'unrecovered');
    assert.deepEqual(coreMod.loadOutbox(store, U).outbox.state.forgotten, ['2026-10-19']);
  }
  // sync that throws is unrecovered as well
  const syncStore = { save: () => ({ ok: true }), load: () => ({ ok: true, outbox: null }), sync: () => { throw new Error('x'); } };
  const unsynced = { ...coreMod.newOutbox(U), status: 'unsynced' };
  assert.equal(coreMod.syncOutbox(syncStore, unsynced).outbox.status, 'unrecovered');
});
