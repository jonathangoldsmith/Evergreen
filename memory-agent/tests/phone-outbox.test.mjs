// The phone entry's Amplitude path, through the bundle with the in-memory io and no network: roll and tap stage events,
// memoryFlush hands them over, memoryAck records delivery, and forgetting a day retracts its delivered events.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createHmac } from 'node:crypto';
import { makeMemoryIO } from './memory-io.mjs';

const USER = `usr_${'e5'.repeat(8)}`;
const snapshot = JSON.parse(fs.readFileSync(new URL('../fixtures/personas/half_marathon.json', import.meta.url), 'utf8'));
const MIDNIGHT = '2026-11-18T00:00:00-08:00';
const DAY = snapshot.workouts[5].start.slice(0, 10);       // a day with a workout
const base = { root: '/mem', user: USER };

let bundle = null;
try { bundle = await (await import('../scripts/build-phone.mjs')).buildPhone(); } catch { /* esbuild is a devDependency */ }
const skip = bundle === null ? 'esbuild is not installed' : false;

function phone({ host = true } = {}) {
  const mem = makeMemoryIO();
  const context = vm.createContext({});
  context.memoryIO = host ? { ...mem.io, hmac: (secret, data) => createHmac('sha256', secret).update(data).digest('hex'), idSecret: 'phone-test-ids-0000-0000' } : mem.io;
  vm.runInContext(bundle, context);
  const call = (name, args) => JSON.parse(context[name](JSON.stringify({ ...base, ...args })));
  return { mem, call };
}
const completedOn = (events, day) => events.filter((e) => e.event_type === 'workout_completed' && e.event_properties.local_date === day);

test('a roll stages workout and memory_rolled events; flush lists them; ack empties the outbox', { skip }, () => {
  const p = phone();
  const roll = p.call('memoryRoll', { snapshot, now: MIDNIGHT });
  assert.equal(roll.ok, true, roll.error);
  assert.ok(roll.staged > snapshot.workouts.length, 'workouts plus memory_rolled');
  const { events } = p.call('memoryFlush', {});
  assert.equal(events.length, roll.staged);
  assert.equal(events.filter((e) => e.event_type === 'memory_rolled').length, 1);
  assert.equal(p.call('memoryRoll', { snapshot, now: MIDNIGHT }).staged, 0, 'the same day again stages nothing new');
  assert.deepEqual(p.call('memoryAck', { acked: events.map((e) => e.insert_id) }), { ok: true, left: 0 });
  assert.deepEqual(p.call('memoryFlush', {}).events, []);
});

test('a tap stages its recommendation events, and the second same-reason decline also stages preference_learned', { skip }, () => {
  const p = phone();
  const tap = (n, weekday) => p.call('memoryTap', { recId: `rec_0000000${n}`, activity: 'run', weekday, hour: 7, action: 'declined', reason: 'too_early', now: '2026-11-17T12:00:00.000Z' });
  assert.equal(tap(1, 3).staged, 1);
  assert.equal(tap(2, 5).staged, 2);
  assert.deepEqual(p.call('memoryFlush', {}).events.map((e) => e.event_type).sort(), ['preference_learned', 'recommendation_declined', 'recommendation_declined']);
});

test('roll, deliver, forget the day: its retraction is pending and the day does not come back on a later roll', { skip }, () => {
  const p = phone();
  p.call('memoryRoll', { snapshot, now: MIDNIGHT });
  const delivered = p.call('memoryFlush', {}).events;
  const day = completedOn(delivered, DAY);
  assert.ok(day.length >= 1);
  p.call('memoryAck', { acked: delivered.map((e) => e.insert_id) });

  assert.deepEqual(p.call('memoryForget', { what: 'day', date: DAY }), { ok: true });
  const pending = p.call('memoryFlush', {}).events;
  const retracted = pending.filter((e) => e.event_type === 'workout_retracted').map((e) => e.event_properties.occurrence_id).sort();
  assert.deepEqual(retracted, day.map((e) => e.event_properties.occurrence_id).sort());

  p.call('memoryAck', { acked: pending.map((e) => e.insert_id) });
  assert.equal(p.call('memoryRoll', { snapshot, now: '2026-11-19T00:00:00-08:00' }).ok, true);
  const later = p.call('memoryFlush', {}).events;
  assert.equal(completedOn(later, DAY).length, 0, 'the forgotten day stays forgotten');
});

test('without the host id secret and hmac the entry works as before and stages nothing', { skip }, () => {
  const p = phone({ host: false });
  const roll = p.call('memoryRoll', { snapshot, now: MIDNIGHT });
  assert.equal(roll.ok, true);
  assert.equal('staged' in roll, false);
  assert.equal(p.call('memoryFlush', {}).ok, false);
});
