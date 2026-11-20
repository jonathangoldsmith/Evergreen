import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { roundMinutes } from '../src/amplitude/events.mjs';
import { EVENTS, REQUIRED, buildEvent, eventsFromSnapshot as rawSnap, send as sendEvents, opaqueId as makeId, canonicalActivity } from '../src/amplitude/node/index.mjs';

const ENV_ID = { TRACKER_ID_SECRET: 'fake-' + 'a'.repeat(24) };
const opaqueId = (p, s, env = ENV_ID) => makeId(p, s, env);
// snapEvents models a fully delivered run: `sent` is the state after every event was acknowledged.
// Delivery failures are tested separately with realSnap and applyAcks.
// the tests pass the source as an option, like a caller that knows where its snapshot comes from
const realSnap = (snap, u, o) => rawSnap(snap, u, { source: 'mock', ...o });
const snapEvents = (snap, u, o) => { const r = realSnap(snap, u, o); return { ...r, sent: r.next }; };
const eventsFromSnapshot = (snap, u, o = { env: ENV_ID }) => realSnap(snap, u, o).events;

const at = new Date('2026-11-18T12:00:00Z');
const U = opaqueId('usr', 'person-a');
const U2 = opaqueId('usr', 'person-b');
const R = opaqueId('rec', 'rec-1');
const O = (n) => opaqueId('occ', `o${n}`);
const dir = new URL('../fixtures/personas/', import.meta.url);
const personas = readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => [f, JSON.parse(readFileSync(new URL(f, dir), 'utf8'))]);

test('the schema lists all ten events', () => {
  assert.deepEqual(Object.keys(EVENTS).sort(), [
    'comeback_accepted', 'memory_rolled', 'preference_learned', 'recommendation_accepted',
    'recommendation_declined', 'recommendation_outcome', 'recommendation_shown', 'workout_completed', 'workout_missed', 'workout_retracted',
  ]);
});

test('unknown event is rejected', () => {
  assert.throws(() => buildEvent('heart_rate_sample', U, at, {}, O(1)), /unknown event/);
  assert.throws(() => buildEvent('toString', U, at, {}, O(1)), /unknown event/);
});

test('properties that are not allowed are dropped', () => {
  const e = buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, heartRate: 150, name: 'Sam' }, O(1));
  assert.deepEqual(e.event_properties, { ...GOOD.workout_completed, occurrence_id: O(1) });
  assert.equal(e.time, at.getTime());
  assert.equal(e.user_id, U);
});

test('opaqueId makes <prefix>_<16 hex> from a seed, deterministically', () => {
  assert.match(opaqueId('usr', 'sam'), /^usr_[0-9a-f]{16}$/);
  assert.equal(opaqueId('rec', 'x'), opaqueId('rec', 'x'));
  assert.notEqual(opaqueId('rec', 'x'), opaqueId('rec', 'y'));
  assert.notEqual(opaqueId('rec', 'x'), opaqueId('occ', 'x'));
  assert.throws(() => opaqueId('name', 'x'), /prefix/);
  assert.throws(() => opaqueId('usr', 'x', {}), /TRACKER_ID_SECRET/);
  assert.throws(() => opaqueId('usr', 'x', { TRACKER_ID_SECRET: 'short' }), /TRACKER_ID_SECRET/);
  assert.throws(() => opaqueId('usr', ''), /seed/);
  assert.ok(!opaqueId('usr', 'sam').includes('sam'));
  // keyed: a different secret gives different ids, and the plain sha256 of the seed is not the id
  assert.notEqual(opaqueId('usr', 'sam'), opaqueId('usr', 'sam', { TRACKER_ID_SECRET: 'other-' + 'b'.repeat(24) }));
  const plain = createHash('sha256').update('usr\u0000sam').digest('hex').slice(0, 16);
  assert.notEqual(opaqueId('usr', 'sam'), `usr_${plain}`);
  // no secret and no value is echoed
  const secret = 'DISTINCTIVE-SECRET-9271';
  assert.throws(() => opaqueId('usr', 'DISTINCTIVE-SEED', { TRACKER_ID_SECRET: secret.slice(0, 5) }), (e) => !e.message.includes('DISTINCTIVE') && !e.message.includes(secret.slice(0, 5)));
  assert.throws(() => eventsFromSnapshot({ workouts: [{ activityType: 'Running', start: '2026-10-19T08:00:00-08:00', durationMin: 30 }] }, U, { env: {} }), /TRACKER_ID_SECRET/);
});

const NOT_OPAQUE = [
  'Sam', 'sam', 'mock-sam', 'mock-sam-1', 'usr_sam', 'usr_3f9a1c2', 'usr_' + 'a'.repeat(33), 'usr_3F9A1C2B',
  'usr_3f9a1c2b ', 'xusr_3f9a1c2b', 'rec_3f9a1c2b', 'occ_3f9a1c2b', // wrong prefix for a user id
  '3f9a1c2b-1111-4111-8111-aaaaaaaaaaaa', 'sam-3f9a1c2b-1111-4111-8111-aaaaaaaaaaaa', 'usr_sam_3f9a1c2b',
  'sam' + '@example' + '.com', '', 5, null, { a: 1 }, ['usr_3f9a1c2b'],
];

test('user ids must be opaque usr_ ids; names, emails and UUIDs are refused', () => {
  buildEvent('memory_rolled', 'usr_3f9a1c2b', at, GOOD.memory_rolled, O(1));
  for (const id of NOT_OPAQUE) assert.throws(() => buildEvent('memory_rolled', id, at, GOOD.memory_rolled, O(1)), /user id/, String(id));
});

test('rec_id and occurrence ids must be opaque too', () => {
  for (const id of NOT_OPAQUE.concat(['usr_3f9a1c2b', 'occ_3f9a1c2b']).filter((x) => x !== 'rec_3f9a1c2b')) {
    assert.throws(() => buildEvent('comeback_accepted', U, at, { rec_id: id, minutes: 5 }, O(1)), /rec_id/, String(id));
  }
  for (const id of NOT_OPAQUE.concat(['usr_3f9a1c2b', 'rec_3f9a1c2b']).filter((x) => x !== 'occ_3f9a1c2b')) {
    assert.throws(() => buildEvent('comeback_accepted', U, at, { rec_id: R, minutes: 5 }, id), /occurrence id/, String(id));
  }
  assert.throws(() => buildEvent('comeback_accepted', U, at, { rec_id: R, minutes: 5 }), /occurrence id/);
});

test('insert_id is sha256(user, event, occurrence) only: properties, time and extras are not in it', () => {
  const a = buildEvent('recommendation_declined', U, at, { rec_id: R, activity: 'Running', reason: 'too_early' }, O(1));
  const b = buildEvent('recommendation_declined', U, new Date(at.getTime() + 5000), { reason: 'too_hard', rec_id: opaqueId('rec', 'other'), activity: 'Yoga', heartRate: 1 }, O(1));
  assert.equal(a.insert_id, b.insert_id);
  assert.match(a.insert_id, /^[0-9a-f]{32}$/);
  assert.notEqual(a.insert_id, buildEvent('recommendation_declined', U, at, a.event_properties, O(2)).insert_id);
  assert.notEqual(a.insert_id, buildEvent('recommendation_declined', U2, at, a.event_properties, O(1)).insert_id);
  assert.notEqual(a.insert_id, buildEvent('recommendation_accepted', U, at, { rec_id: R, activity: 'Running' }, O(1)).insert_id);
});

// the default snapshot declares coverage 2026-10-01 to 2026-11-18; coverage cases are tested explicitly below
const COVER = { coverage: { from: '2026-10-01', to: '2026-11-18' } };
const EMPTY = { ...COVER, workouts: [] };
const snapOf = (durationMin, activityType, start = '2026-10-19T08:00:00-08:00', end = '2026-10-19T08:30:00-08:00') => ({ ...COVER, workouts: [{ activityType, start, end, durationMin }] });

const OPTS = (sent) => ({ env: ENV_ID, sent });
const T0 = '2026-10-19T08:00:00-08:00';
const T0E = '2026-10-19T08:30:00-08:00';
// the documented query: a workout counts if its occurrence id is not named by any supersedes or any workout_retracted
const live = (all) => {
  const gone = new Set();
  for (const e of all) {
    if (e.event_properties.supersedes) gone.add(e.event_properties.supersedes);
    if (e.event_type === 'workout_retracted') gone.add(e.event_properties.occurrence_id);
  }
  return all.filter((e) => e.event_type === 'workout_completed' && !gone.has(e.event_properties.occurrence_id));
};

test('new key emits; same content emits nothing', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  assert.equal(r1.events.length, 1);
  const same = snapEvents(snapOf(30, 'Running'), U, OPTS(r1.sent));
  assert.deepEqual(same.events, []);
  assert.deepEqual(same.sent, r1.sent);
  assert.equal(r1.sent.workouts[Object.keys(r1.sent.workouts)[0]].version, 1);
});

test('a corrected end time supersedes the old occurrence (stable key is the start)', () => {
  const r1 = snapEvents(snapOf(30, 'Running', T0, T0E), U, { env: ENV_ID });
  const r2 = snapEvents(snapOf(30, 'Running', T0, '2026-10-19T08:45:00-08:00'), U, OPTS(r1.sent));
  assert.equal(r2.events.length, 1);
  assert.equal(r2.events[0].event_properties.supersedes, r1.events[0].event_properties.occurrence_id);
  assert.equal(live([...r1.events, ...r2.events]).length, 1);
  assert.deepEqual(Object.keys(r1.sent.workouts), Object.keys(r2.sent.workouts));
});

test('corrected minutes or activity supersede; the input map is not changed', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  const before = JSON.stringify(r1.sent);
  const r2 = snapEvents(snapOf(35.5, 'Cycling'), U, OPTS(r1.sent));
  assert.equal(r2.events[0].event_properties.minutes, 35.5);
  assert.equal(r2.events[0].event_properties.activity, 'Cycling');
  assert.equal(JSON.stringify(r1.sent), before);
});

test('a workout corrected below 10 minutes, or removed, is retracted once', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  for (const gone of [snapOf(9, 'Running'), EMPTY]) {
    const r2 = snapEvents(gone, U, OPTS(r1.sent));
    assert.equal(r2.events.length, 1);
    assert.equal(r2.events[0].event_type, 'workout_retracted');
    assert.equal(r2.events[0].event_properties.occurrence_id, r1.events[0].event_properties.occurrence_id);
    assert.equal(live([...r1.events, ...r2.events]).length, 0);
    assert.deepEqual(snapEvents(gone, U, OPTS(r2.sent)).events, []); // not retracted twice
  }
});

test('a retracted workout that comes back is a new live event', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  const r2 = snapEvents(EMPTY, U, OPTS(r1.sent));
  const r3 = snapEvents(snapOf(30, 'Running'), U, OPTS(r2.sent));
  assert.equal(r3.events.length, 1);
  assert.equal(r3.events[0].event_type, 'workout_completed');
  assert.notEqual(r3.events[0].insert_id, r1.events[0].insert_id);
  assert.equal('supersedes' in r3.events[0].event_properties, false);
  assert.deepEqual(live([...r1.events, ...r2.events, ...r3.events]).map((e) => e.insert_id), [r3.events[0].insert_id]);
});

test('a corrected time zone changes weekday and hour and supersedes', () => {
  const r1 = snapEvents(snapOf(30, 'Running', '2026-10-19T23:30:00-08:00', '2026-10-20T00:00:00-08:00'), U, { env: ENV_ID });
  assert.deepEqual([r1.events[0].event_properties.weekday, r1.events[0].event_properties.hour], ['Mon', 23]);
  // the same instant written in another zone
  const r2 = snapEvents(snapOf(30, 'Running', '2026-10-20T07:30:00Z', '2026-10-20T08:00:00Z'), U, OPTS(r1.sent));
  assert.equal(r2.events.length, 1);
  assert.deepEqual([r2.events[0].event_properties.weekday, r2.events[0].event_properties.hour], ['Tue', 7]);
  assert.equal(r2.events[0].event_properties.supersedes, r1.events[0].event_properties.occurrence_id);
  assert.equal(r2.events[0].time, r1.events[0].time);
});

test('a sent map is bound to its user: another user is refused, and a second user is not suppressed', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  assert.equal(r1.sent.user, U);
  assert.throws(() => snapEvents(snapOf(30, 'Running'), U2, OPTS(r1.sent)), /another user/);
  const other = snapEvents(snapOf(30, 'Running'), U2, { env: ENV_ID });
  assert.equal(other.events.length, 1);
  assert.notEqual(other.events[0].insert_id, r1.events[0].insert_id);
  assert.notEqual(Object.keys(other.sent.workouts)[0], Object.keys(r1.sent.workouts)[0]);
});

test('full round trip: send, correct end, correct minutes below 10, remove, zone change, two users', () => {
  let sent;
  const all = [];
  const step = (snap) => { const r = snapEvents(snap, U, OPTS(sent)); sent = r.sent; all.push(...r.events); return r.events; };
  sent = undefined;
  const first = snapEvents(snapOf(30, 'Running', T0, T0E), U, { env: ENV_ID }); sent = first.sent; all.push(...first.events);
  assert.equal(live(all).length, 1);
  assert.equal(step(snapOf(30, 'Running', T0, T0E)).length, 0);
  step(snapOf(30, 'Running', T0, '2026-10-19T08:50:00-08:00'));
  assert.equal(live(all).length, 1);
  assert.equal(live(all)[0].event_properties.minutes, 30);
  step(snapOf(9.5, 'Running', T0, '2026-10-19T08:50:00-08:00'));
  assert.equal(live(all).length, 0);
  step(snapOf(30, 'Running', T0, T0E));
  assert.equal(live(all).length, 1);
  step(snapOf(30, 'Running', '2026-10-19T16:00:00Z', '2026-10-19T16:30:00Z'));
  assert.equal(live(all).length, 1);
  assert.equal(live(all)[0].event_properties.hour, 16);
  step(EMPTY);
  assert.equal(live(all).length, 0);
  assert.equal(new Set(all.map((e) => e.insert_id)).size, all.length);
  // a second user with the same workout and the same persisted map shape is independent
  const u2 = snapEvents(snapOf(30, 'Running', T0, T0E), U2, { env: ENV_ID });
  assert.equal(live([...all, ...u2.events]).filter((e) => e.user_id === U2).length, 1);
});

test('a malformed sent map is refused', () => {
  const good = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID }).sent;
  const key = Object.keys(good.workouts)[0];
  const entry = good.workouts[key];
  const bad = [null, [], { x: 1 }, { user: U }, { user: U, workouts: [] }, { user: U, workouts: { [O(1)]: 1 } },
    { user: U, workouts: { [O(1)]: { ...entry, hash: 'zz' } } }, { user: U, workouts: { [O(1)]: { ...entry, occurrence_id: 'Sam' } } },
    { user: U, workouts: { [O(1)]: { ...entry, version: 0 } } }, { user: U, workouts: { [O(1)]: { ...entry, live: 'yes' } } },
    { user: U, workouts: { Sam: entry } }];
  for (const sent of bad) assert.throws(() => snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID, sent }), /sent/);
});

test('occurrence_id is on every workout event, validated, and matches the occurrence', () => {
  const e = buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1));
  assert.equal(e.event_properties.occurrence_id, O(1));
  assert.throws(() => buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, occurrence_id: O(2) }, O(1)), /occurrence_id/);
  for (const bad of ['Sam', R, 5, { a: 1 }]) {
    assert.throws(() => buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, occurrence_id: bad }, O(1)), /occurrence_id/);
  }
});

test('required properties: every event is rejected when any one is missing', () => {
  assert.deepEqual(Object.keys(REQUIRED).sort(), Object.keys(EVENTS).sort());
  for (const [name, good] of Object.entries(GOOD)) {
    for (const req of REQUIRED[name].filter((r) => r !== 'occurrence_id')) { // the builder fills occurrence_id itself
      const { [req]: _omit, ...rest } = good;
      assert.throws(() => buildEvent(name, U, at, rest, O(1)), /missing/, `${name} without ${req}`);
    }
    assert.throws(() => buildEvent(name, U, at, {}, O(1)), /missing/);
    assert.throws(() => buildEvent(name, U, at, undefined, O(1)), /missing/);
  }
});

test('snapshot workouts of 10+ minutes become events with only allowed fields', () => {
  const sedentary = personas.find(([f]) => f.startsWith('sedentary'))[1];
  const ev = eventsFromSnapshot(sedentary, U);
  assert.equal(ev.length, 8);
  for (const e of ev) {
    assert.equal(e.event_type, 'workout_completed');
    assert.ok(Object.keys(e.event_properties).every((k) => EVENTS.workout_completed.includes(k)));
    assert.equal(e.event_properties.source, 'mock');
  }
});

test('short workouts are skipped', () => {
  const snap = { workouts: [{ activityType: 'Walking', start: '2026-10-19T08:00:00-08:00', durationMin: 9.9 }] };
  assert.deepEqual(eventsFromSnapshot(snap, U), []);
});

test('no heart rate, samples, route or name in any event from the three personas', () => {
  assert.equal(personas.length, 3);
  for (const [file, snap] of personas) {
    const ev = eventsFromSnapshot(snap, opaqueId('usr', file));
    assert.ok(ev.length > 0, file);
    const text = JSON.stringify(ev).toLowerCase();
    for (const banned of ['heartrate', 'heart_rate', 'samples', 'route', 'name', 'distance', 'energy']) {
      assert.ok(!text.includes(banned), `${file} contains ${banned}`);
    }
    const values = [snap.profile?.name, snap.profile?.firstName].filter(Boolean);
    for (const v of values) assert.ok(!text.includes(String(v).toLowerCase()), `${file} leaks a name`);
  }
});

test('minutes are the duration rounded half away from zero to two decimals, always', () => {
  const snap = (m) => ({ workouts: [{ activityType: 'Running', start: '2026-10-19T08:00:00-08:00', end: '2026-10-19T08:10:24-08:00', durationMin: m }] });
  const minutes = (m) => eventsFromSnapshot(snap(m), U).map((e) => e.event_properties.minutes);
  assert.deepEqual(minutes(10.44), [10.44]);
  assert.deepEqual(minutes(28.29), [28.29]);
  assert.deepEqual(minutes(10.444), [10.44]);
  assert.deepEqual(minutes(10.4400000001), [10.44]);
  assert.deepEqual(minutes(30.123), [30.12]); // a duration with more decimals is rounded, not rejected
  assert.deepEqual(minutes(30.125), [30.13]); // exactly representable half: away from zero
  assert.deepEqual(minutes(30.1249999), [30.12]);
  assert.deepEqual(minutes(9.999), []); // under 10 unrounded: not counted, although it would round to 10.00
  assert.deepEqual(minutes(9.994), []);
  assert.deepEqual(minutes(10), [10]);
  assert.deepEqual(minutes(10.004), [10]); // 10 or more unrounded: counted, and only the property is rounded
  assert.deepEqual(minutes(600), [600]);
  assert.deepEqual(minutes(601), [601]); // a long workout does not reject the snapshot
  assert.deepEqual(minutes(1440), [1440]);
  assert.deepEqual(minutes(1439.999), [1440]);
  for (const m of [1440.001, 1441, 100000]) assert.throws(() => eventsFromSnapshot(snap(m), U), /^Error: invalid workout duration$/, String(m));
  assert.throws(() => eventsFromSnapshot(snap(-0.001), U), /invalid workout duration/);
  assert.throws(() => eventsFromSnapshot(snap(Infinity), U), /invalid workout duration/);
});

test('identical records at one start are one workout; different ones need ids; a different start is another', () => {
  const rec = (start, end, activityType = 'Running', extra = {}) => ({ activityType, start, end, durationMin: 30, ...extra });
  const A = ['2026-10-19T08:00:00-08:00', '2026-10-19T08:30:00-08:00'];
  assert.equal(eventsFromSnapshot({ workouts: [rec(...A), rec(...A)] }, U).length, 1);
  for (const other of [rec(A[0], '2026-10-19T08:31:00-08:00'), rec(...A, 'Walking'), rec(...A, 'Running', { durationMin: 31 }), rec(...A, 'Running', { source: 'watch' })]) {
    for (const order of [[rec(...A), other], [other, rec(...A)]]) {
      assert.throws(() => eventsFromSnapshot({ workouts: order }, U), /workouts at the same start need ids/);
    }
  }
  // with ids the two are told apart by id, and the same id keeps the first by canonical content
  const two = eventsFromSnapshot({ workouts: [rec(...A, 'Running', { id: 'wk_0123abcd' }), rec(...A, 'Walking', { id: 'wk_89abcdef' })] }, U);
  assert.equal(two.length, 2);
  const one = eventsFromSnapshot({ workouts: [rec(...A, 'Walking', { id: 'wk_0123abcd' }), rec(...A, 'Running', { id: 'wk_0123abcd' })] }, U);
  assert.equal(one.length, 1);
  assert.equal(one[0].event_properties.activity, 'Running');
  const diff = eventsFromSnapshot({ workouts: [rec(...A), rec('2026-10-19T09:00:00-08:00', '2026-10-19T09:30:00-08:00')] }, U);
  assert.equal(new Set(diff.map((e) => e.insert_id)).size, 2);
});

test('activity aliases map to the fact engine names; no fixture activity becomes Other by mistake', () => {
  assert.equal(canonicalActivity('HIIT'), 'HighIntensityIntervalTraining');
  assert.equal(canonicalActivity('hiit'), 'HighIntensityIntervalTraining');
  assert.equal(canonicalActivity('TraditionalStrengthTraining'), 'TraditionalStrengthTraining');
  assert.equal(canonicalActivity('FunctionalStrengthTraining'), 'FunctionalStrengthTraining');
  assert.equal(canonicalActivity('strength training'), 'TraditionalStrengthTraining');
  assert.equal(canonicalActivity('Sam Smith'), 'Other');
  assert.equal(canonicalActivity({ a: 1 }), 'Other');
  const types = new Set(personas.flatMap(([, p]) => p.workouts.map((w) => w.activityType)));
  assert.ok(types.size >= 8);
  for (const t of types) assert.notEqual(canonicalActivity(t), 'Other', t);
  for (const [, snap] of personas) {
    for (const e of eventsFromSnapshot(snap, U)) assert.notEqual(e.event_properties.activity, 'Other');
  }
});

test('workout_completed may carry a verified rec_id, but does not need one', () => {
  const base = GOOD.workout_completed;
  assert.equal(buildEvent('workout_completed', U, at, { ...base, rec_id: R }, O(1)).event_properties.rec_id, R);
  assert.throws(() => buildEvent('workout_completed', U, at, { ...base, rec_id: 'Sam' }, O(1)), /rec_id/);
  assert.equal('rec_id' in buildEvent('workout_completed', U, at, base, O(1)).event_properties, false);
});

test('no thrown error echoes a caller-supplied value', () => {
  const D = 'DISTINCTIVE9271';
  const calls = [
    () => buildEvent(D, U, at, {}, O(1)),
    () => buildEvent('memory_rolled', D, at, GOOD.memory_rolled, O(1)),
    () => buildEvent('memory_rolled', U, at, GOOD.memory_rolled, D),
    () => buildEvent('memory_rolled', U, D, GOOD.memory_rolled, O(1)),
    () => buildEvent('memory_rolled', U, at, D, O(1)),
    () => buildEvent('memory_rolled', U, at, { ...GOOD.memory_rolled, daily_lines: D }, O(1)),
    () => buildEvent('preference_learned', U, at, { reason: D, times_said: 2 }, O(1)),
    () => buildEvent('preference_learned', U, at, { reason: { [D]: D }, times_said: 2 }, O(1)),
    () => buildEvent('workout_completed', U, at, { [D]: D }, O(1)),
    () => opaqueId(D, 'x'),
    () => eventsFromSnapshot({ workouts: [{ activityType: D, start: D, durationMin: 30 }] }, U),
    () => eventsFromSnapshot({ workouts: [{ activityType: D, start: '2026-10-19T08:00:00-08:00', durationMin: 30 }] }, D),
  ];
  for (const f of calls) assert.throws(f, (e) => !String(e.message).includes(D) && !String(e.stack).includes(D));
});

const GOOD = {
  workout_completed: { activity: 'Running', minutes: 30, weekday: 'Wed', hour: 12, source: 'mock', local_date: '2026-11-18', local_week: '2026-11-16', utc_offset_minutes: 0 },
  workout_missed: { activity: 'Yoga', planned_weekday: 'Tue', planned_hour: 18 },
  recommendation_shown: { rec_id: R, activity: 'Walking', minutes: 20, weekday: 'Wed', hour: 9, framing: 'baseline' },
  recommendation_accepted: { rec_id: R, activity: 'Walking', weekday: 'Wed', hour: 9 },
  recommendation_declined: { rec_id: R, activity: 'Walking', weekday: 'Wed', hour: 9, reason: 'too_early' },
  comeback_accepted: { rec_id: R, minutes: 15 },
  recommendation_outcome: { rec_id: R, outcome: 'completed' },
  workout_retracted: { occurrence_id: O(1), utc_offset_minutes: 0 },
  memory_rolled: { daily_lines: 20, weekly_lines: 8, preferences: 2, prompt_words: 250 },
  preference_learned: { reason: 'too_hard', times_said: 2 },
};
const BAD = {
  activity: [{ heartRate: 150 }, ['Running'], 'x'.repeat(500), 'Sam Smith', 'sam' + '@example' + '.com', 5],
  planned_weekday: ['Monday', 'sam' + '@example' + '.com', { a: 1 }],
  weekday: ['Funday', ['Mon'], 3],
  planned_hour: [24, -1, 7.5, '7', NaN],
  hour: [24, -1, 7.5, '7', { a: 1 }],
  minutes: [1441, -1, NaN, Infinity, '30', [30], { heartRate: 150 }, 10.444],
  framing: ['shouting', { x: 1 }, 'x'.repeat(500)],
  reason: [{ heartRate: 150, route: [[1, 2]] }, ['too_hard'], 'because my knee hurts', 'sam' + '@example' + '.com', 'x'.repeat(500)],
  source: ['watch of Sam', { a: 1 }],
  occurrence_id: ['Sam', R, 5, { a: 1 }, O(2)],
  local_date: ['2026-02-30', '2026-11-18T12:00', '11/18/2026', 20261118, { a: 1 }, '2026-13-01', '2026-11-17'],
  local_week: ['2026-11-18', '2026-11-23', 'Monday', 5, { a: 1 }, '2026-02-30'],
  utc_offset_minutes: [841, -841, 1.5, '0', NaN, { a: 1 }, 60],
  outcome: ['done', 'Completed', 'not completed', { a: 1 }, true, 'x'.repeat(500)],
  rec_id: ['Sam', 'sam', 'Sam Smith', 'mock-sam', 'usr_3f9a1c2b', 'x'.repeat(65), { a: 1 }, [R], '', 12],
  daily_lines: [-1, 1.5, '3', {}], weekly_lines: [-1, 1e9], preferences: [-1, {}], prompt_words: [-1, 1e9, 'x'],
  times_said: [0, -1, 2.5, 'twice', {}],
};

test('every event type rejects a bad value for every allowed property', () => {
  for (const [name, good] of Object.entries(GOOD)) {
    buildEvent(name, U, at, good, O(1)); // the good one is fine
    for (const prop of Object.keys(good)) {
      for (const bad of BAD[prop]) {
        if (name === 'workout_retracted' && prop === 'utc_offset_minutes' && bad === 60) continue; // 12:00Z is also an hour start at +01:00
        assert.throws(() => buildEvent(name, U, at, { ...good, [prop]: bad }, O(1)), /invalid value for property|occurrence_id does not match|workout time fields disagree/, `${name}.${prop}=${JSON.stringify(bad)}`);
      }
    }
  }
});

test('the sender posts only clean events; adversarial payloads never reach the fake fetch', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const env = { AMPLITUDE_API_KEY: 'k'.repeat(32) };
  const posted = [];
  const fetchImpl = async (u, init) => { posted.push(init.body); return { status: 200 }; };
  // good events built by the builder, then widened by hand with extra top-level and property fields
  const events = Object.entries(GOOD).map(([n, p]) => {
    const e = buildEvent(n, U, at, p, O(1));
    return { ...e, user_properties: { name: 'Sam' }, event_properties: { ...e.event_properties, heartRate: 150, route: [[1, 2]], samples: [1] } };
  });
  await send(events, { fetchImpl, env });
  const text = posted.join('');
  for (const banned of ['heartRate', 'route', 'samples', 'user_properties', 'Sam']) assert.ok(!text.includes(banned), banned);
  assert.equal(JSON.parse(posted[0]).events.length, 10);
  const dry = await send(events, { dryRun: true, env: {} });
  assert.ok(!JSON.stringify(dry).includes('heartRate'));
  // hand-made events with bad values are refused, in a real send and in a dry run, and the whole batch is refused
  for (const prop of Object.keys(GOOD.recommendation_declined)) {
    for (const bad of BAD[prop]) {
      const e = buildEvent('recommendation_declined', U, at, GOOD.recommendation_declined, O(1));
      const evil = { ...e, event_properties: { ...e.event_properties, [prop]: bad } };
      const before = posted.length;
      await assert.rejects(send([events[0], evil], { fetchImpl, env }), /invalid value for property/);
      await assert.rejects(send([events[0], evil], { dryRun: true, env: {} }), /invalid value for property/);
      assert.equal(posted.length, before);
    }
  }
  const e = events[0];
  for (const evil of [null, 'x', { ...e, event_type: 'heart_rate_sample' }, { ...e, user_id: 'Sam' }, { ...e, user_id: 'mock-sam' }, { ...e, insert_id: 'nope' }, { ...e, time: 'now' }]) {
    await assert.rejects(send([e, evil], { dryRun: true, env: {} }));
  }
});

test('the same instant under different offsets is one workout with an id, and a rejection without one', () => {
  const rec = (start, end, activityType = 'Running', id = 'wk_0123abcd') => ({ activityType, start, end, durationMin: 30, id });
  const snap = { workouts: [
    rec('2026-10-19T08:00:00-08:00', '2026-10-19T08:30:00-08:00'),
    rec('2026-10-19T16:00:00Z', '2026-10-19T16:30:00Z', 'Walking'),
    rec('2026-10-19T17:00:00+01:00', '2026-10-19T17:30:00+0100', 'Cycling'),
  ] };
  const ev = eventsFromSnapshot(snap, U);
  assert.equal(ev.length, 1);
  assert.equal(ev[0].time, Date.parse('2026-10-19T16:00:00Z'));
  assert.equal(ev[0].event_properties.activity, 'Cycling'); // the first by canonical content, whatever the input order
  const noId = (r) => { const { id: _i, ...rest } = r; return rest; };
  assert.throws(() => eventsFromSnapshot({ workouts: snap.workouts.map(noId) }, U), /need ids/);
  assert.throws(() => eventsFromSnapshot({ workouts: [rec('2026-10-19T08:00:00', '2026-10-19T08:30:00')] }, U), /workout time/);
  assert.throws(() => eventsFromSnapshot({ workouts: [rec('2026-10-19T08:00:00Z', 'tomorrow')] }, U), /workout time/);
});

test('a correction is a new event that supersedes the old occurrence', () => {
  const old = buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1));
  const fix = buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, minutes: 35, supersedes: O(1) }, O(2));
  assert.notEqual(old.insert_id, fix.insert_id);
  assert.equal(fix.event_properties.supersedes, O(1));
  // resending the old occurrence unchanged is still the same insert_id
  assert.equal(old.insert_id, buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1)).insert_id);
  // supersedes must be an opaque occ_ id, and cannot point at itself
  for (const bad of ['Sam', R, U, 'occ_zz', 5, { a: 1 }]) {
    assert.throws(() => buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, supersedes: bad }, O(2)), /supersedes/);
  }
  assert.throws(() => buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, supersedes: O(2) }, O(2)), /supersede itself/);
  // other events do not take it
  assert.equal('supersedes' in buildEvent('comeback_accepted', U, at, { rec_id: R, minutes: 5, supersedes: O(1) }, O(3)).event_properties, false);
});

test('the sender validates supersedes', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const fix = buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, supersedes: O(1) }, O(2));
  const r = await send([fix], { dryRun: true, env: {} });
  assert.equal(r.payloads[0].events[0].event_properties.supersedes, O(1));
  const evil = { ...fix, event_properties: { ...fix.event_properties, supersedes: 'Sam' } };
  await assert.rejects(send([evil], { dryRun: true, env: {} }), /supersedes/);
});

test('an event name must be a string, not an object that prints like one', () => {
  const sneaky = { toString: () => 'memory_rolled' };
  assert.throws(() => buildEvent(sneaky, U, at, GOOD.memory_rolled, O(1)), /unknown event type/);
});

test('the sender rejects a workout event without or with a wrong occurrence_id', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const e = buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1));
  const { occurrence_id: _o, ...without } = e.event_properties;
  await assert.rejects(send([{ ...e, event_properties: without }], { dryRun: true, env: {} }), /missing required property occurrence_id/);
  await assert.rejects(send([{ ...e, event_properties: { ...without, occurrence_id: O(2) } }], { dryRun: true, env: {} }), /insert_id does not match/);
  await send([e], { dryRun: true, env: {} });
});

test('recommendation_outcome needs rec_id and a closed outcome', () => {
  assert.equal(buildEvent('recommendation_outcome', U, at, { rec_id: R, outcome: 'not_completed' }, O(1)).event_properties.outcome, 'not_completed');
  assert.throws(() => buildEvent('recommendation_outcome', U, at, { rec_id: R }, O(1)), /missing required property outcome/);
  assert.throws(() => buildEvent('recommendation_outcome', U, at, { outcome: 'completed' }, O(1)), /missing required property rec_id/);
});

test('the sender refuses a workout that supersedes itself', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const e = buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1));
  const evil = { ...e, event_properties: { ...e.event_properties, supersedes: O(1) } };
  await assert.rejects(send([evil], { dryRun: true, env: {} }), /supersede itself/);
});

test('the sender accepts workout_retracted and refuses one whose occurrence does not match', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const e = buildEvent('workout_retracted', U, at, { utc_offset_minutes: 0 }, O(1));
  assert.equal(e.event_properties.occurrence_id, O(1));
  await send([e], { dryRun: true, env: {} });
  await assert.rejects(send([{ ...e, event_properties: { occurrence_id: O(2), utc_offset_minutes: 0 } }], { dryRun: true, env: {} }), /insert_id does not match/);
  assert.throws(() => buildEvent('workout_retracted', U, at, { occurrence_id: O(2), utc_offset_minutes: 0 }, O(1)), /occurrence_id/);
  assert.equal('activity' in buildEvent('workout_retracted', U, at, { activity: 'Running', utc_offset_minutes: 0 }, O(1)).event_properties, false);
});

test('the event time is the start of the local hour, never the exact start; sent holds no raw timestamp', () => {
  const exact = '2026-10-19T08:47:31-08:00';
  const r = snapEvents(snapOf(30, 'Running', exact, '2026-10-19T09:17:31-08:00'), U, { env: ENV_ID });
  const exactMs = Date.parse(exact);
  assert.equal(r.events[0].time, Date.parse('2026-10-19T08:00:00-08:00'));
  assert.notEqual(r.events[0].time, exactMs);
  const half = snapEvents(snapOf(30, 'Running', '2026-10-19T21:47:00+05:30', '2026-10-19T22:17:00+05:30'), U, { env: ENV_ID });
  assert.equal(half.events[0].time, Date.parse('2026-10-19T21:00:00+05:30'));
  const blob = JSON.stringify([r.events, r.sent, half.events, half.sent]);
  for (const raw of [String(exactMs), '08:47', '47:31', '09:17', String(Date.parse('2026-10-19T21:47:00+05:30')), '21:47']) {
    assert.ok(!blob.includes(raw), `leaks ${raw}`);
  }
  // a retraction carries the hour time too
  const gone = snapEvents(EMPTY, U, OPTS(r.sent));
  assert.equal(gone.events[0].time, Date.parse('2026-10-19T08:00:00-08:00'));
  assert.ok(!JSON.stringify(gone).includes(String(exactMs)));
});

test('a snapshot must have a workouts array', () => {
  for (const snap of [{}, { ...COVER }, { ...COVER, workouts: null }, { ...COVER, workouts: {} }, null, 'x', []]) {
    assert.throws(() => snapEvents(snap, U, { env: ENV_ID }), /workouts array/);
  }
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  assert.throws(() => snapEvents({ ...COVER }, U, OPTS(r1.sent)), /workouts array/);
});

test('weekly counts and the 4-week baseline use only active occurrences, grouped by local_week', () => {
  const week = (e) => e.event_properties.local_week;
  const counts = (events) => {
    const c = {};
    for (const e of live(events)) c[week(e)] = (c[week(e)] ?? 0) + 1;
    return c;
  };
  const wk = (day, m = 30) => ({ activityType: 'Running', start: `${day}T08:00:00-08:00`, end: `${day}T08:${String(10 + (m > 59 ? 0 : 20)).padStart(2, '0')}:00-08:00`, durationMin: m });
  const s1 = snapEvents({ ...COVER, workouts: [wk('2026-10-19'), wk('2026-10-21'), wk('2026-10-26')] }, U, { env: ENV_ID });
  // correct the 10-21 workout (superseded) and delete the 10-26 workout (retracted)
  const s2 = snapEvents({ ...COVER, workouts: [wk('2026-10-19'), wk('2026-10-21', 45)] }, U, OPTS(s1.sent));
  const all = [...s1.events, ...s2.events];
  assert.equal(all.filter((e) => e.event_type === 'workout_completed').length, 4);
  const c = counts(all);
  assert.deepEqual(c, { '2026-10-19': 2 }); // naive counting would say 3 and 1 more
  const naive = {};
  for (const e of all.filter((x) => x.event_type === 'workout_completed')) naive[week(e)] = (naive[week(e)] ?? 0) + 1;
  assert.notDeepEqual(naive, c);
});

test('the content hash in sent is keyed: it cannot be brute-forced to recover the end time', () => {
  const end = '2026-10-19T08:30:00-08:00';
  const r = snapEvents(snapOf(30, 'Running', T0, end), U, { env: ENV_ID });
  const entry = Object.values(r.sent.workouts)[0];
  const w = r.events[0].event_properties;
  const plain = createHash('sha256').update(JSON.stringify([Date.parse(end), w.activity, w.minutes, w.weekday, w.hour, w.source])).digest('hex').slice(0, 16);
  assert.notEqual(entry.hash, plain);
  const other = snapEvents(snapOf(30, 'Running', T0, end), U, { env: { TRACKER_ID_SECRET: 'other-' + 'b'.repeat(24) } });
  assert.notEqual(Object.values(other.sent.workouts)[0].hash, entry.hash);
});

// ---- explicit coverage cases, with expected results written out by hand ----
const day = (d, extra = {}) => ({ activityType: 'Running', start: `${d}T08:00:00-08:00`, end: `${d}T08:30:00-08:00`, durationMin: 30, ...extra });
const three = (cov) => snapEvents({ ...cov, workouts: [day('2026-10-10'), day('2026-10-19'), day('2026-11-01')] }, U, { env: ENV_ID });
const retractedDays = (r1, snap) => {
  const r2 = snapEvents(snap, U, OPTS(r1.sent));
  const byOcc = new Map(r1.events.map((e) => [e.event_properties.occurrence_id, e.event_properties.local_date]));
  return r2.events.filter((e) => e.event_type === 'workout_retracted').map((e) => byOcc.get(e.event_properties.occurrence_id)).sort();
};

test('coverage cases: partial coverage retracts only inside it', () => {
  const r1 = three({});
  assert.equal(r1.events.length, 3);
  const partial = { coverage: { from: '2026-10-15', to: '2026-10-25' }, workouts: [] };
  assert.deepEqual(retractedDays(r1, partial), ['2026-10-19']);
  const edges = { coverage: { from: '2026-10-10', to: '2026-10-19' }, workouts: [] };
  assert.deepEqual(retractedDays(r1, edges), ['2026-10-10', '2026-10-19']);
});

test('coverage cases: no coverage retracts nothing, whatever else the snapshot says', () => {
  const r1 = three({});
  assert.deepEqual(retractedDays(r1, { workouts: [] }), []);
  // daily summaries and an export date are NOT coverage
  const summaries = { exportDate: '2026-11-18T07:30:00-08:00', dailySummaries: [{ date: '2026-10-01' }, { date: '2026-11-18' }], workouts: [] };
  assert.deepEqual(retractedDays(r1, summaries), []);
  assert.deepEqual(retractedDays(r1, { coverage: null, workouts: [] }), []);
});

test('coverage cases: full coverage retracts every absent workout, and keeps present ones', () => {
  const r1 = three({});
  const full = { coverage: { from: '2026-10-01', to: '2026-11-18' }, workouts: [] };
  assert.deepEqual(retractedDays(r1, full), ['2026-10-10', '2026-10-19', '2026-11-01']);
  assert.deepEqual(retractedDays(r1, { ...full, workouts: [day('2026-10-19')] }), ['2026-10-10', '2026-11-01']);
});

test('coverage cases: a rolling window moving forward retracts nothing outside its coverage', () => {
  const r1 = three({});
  const later = { coverage: { from: '2026-11-10', to: '2026-11-25' }, workouts: [day('2026-11-12')] };
  assert.deepEqual(retractedDays(r1, later), []);
  const r2 = snapEvents(later, U, OPTS(r1.sent));
  assert.equal(live([...r1.events, ...r2.events]).length, 4);
});

test('an invalid coverage is rejected', () => {
  for (const coverage of ['2026-10-01', [], { from: '2026-10-01' }, { from: '2026-02-30', to: '2026-03-01' }, { from: '2026-11-18', to: '2026-10-01' }, { from: 5, to: 6 }]) {
    assert.throws(() => snapEvents({ coverage, workouts: [] }, U, { env: ENV_ID }), /invalid coverage/);
  }
});

test('an invalid duration rejects the snapshot and never retracts', () => {
  const r1 = snapEvents(snapOf(30, 'Running'), U, { env: ENV_ID });
  for (const durationMin of [undefined, null, 'forty', '30', NaN, Infinity, -5, {}, [30]]) {
    const snap = { ...COVER, workouts: [{ ...day('2026-10-19'), durationMin }] };
    assert.throws(() => snapEvents(snap, U, OPTS(r1.sent)), /invalid workout duration/, String(durationMin));
    assert.throws(() => snapEvents(snap, U, { env: ENV_ID }), /invalid workout duration/);
  }
  const { durationMin: _d, ...noDuration } = day('2026-10-19');
  assert.throws(() => snapEvents({ ...COVER, workouts: [noDuration] }, U, OPTS(r1.sent)), /invalid workout duration/);
  // a valid number under 10 is ineligible and retracts
  const short = snapEvents({ ...COVER, workouts: [day('2026-10-19', { durationMin: 9.99 })] }, U, OPTS(r1.sent));
  assert.deepEqual(short.events.map((e) => e.event_type), ['workout_retracted']);
  assert.throws(() => snapEvents({ ...COVER, workouts: [null] }, U, { env: ENV_ID }), /invalid workout/);
});

test('workout events carry local_date, local_week and utc_offset_minutes; time is the local hour start', () => {
  const r = snapEvents({ ...COVER, workouts: [{ ...day('2026-11-22'), start: '2026-11-22T23:30:00-08:00', end: '2026-11-23T00:00:00-08:00' }] }, U, { env: ENV_ID });
  const p = r.events[0].event_properties;
  assert.deepEqual([p.local_date, p.local_week, p.utc_offset_minutes, p.weekday, p.hour], ['2026-11-22', '2026-11-16', -480, 'Sun', 23]);
  assert.equal(r.events[0].time, Date.UTC(2026, 10, 23, 7, 0, 0)); // 23:00 local = 07:00Z on the Monday
  const half = snapEvents({ ...COVER, workouts: [{ ...day('2026-10-19'), start: '2026-10-19T21:47:00+05:30', end: '2026-10-19T22:17:00+05:30' }] }, U, { env: ENV_ID });
  assert.equal(half.events[0].event_properties.utc_offset_minutes, 330);
});

test('the builder and the sender reject any workout time that is not the local hour start', async () => {
  const { send } = await import('../src/amplitude/node/index.mjs');
  const ok = buildEvent('workout_completed', U, at, GOOD.workout_completed, O(1));
  const exact = new Date(at.getTime() + 31 * 60000 + 7000); // 12:31:07, an exact timestamp
  assert.throws(() => buildEvent('workout_completed', U, exact, GOOD.workout_completed, O(1)), /workout time fields disagree/);
  assert.throws(() => buildEvent('workout_completed', U, new Date(at.getTime() + 3600000), GOOD.workout_completed, O(1)), /disagree/);
  await assert.rejects(send([{ ...ok, time: exact.getTime() }], { dryRun: true, env: {} }), /workout time fields disagree/);
  // weekday, week, date and offset must agree with the time
  for (const change of [{ weekday: 'Thu' }, { local_week: '2026-11-09' }, { local_date: '2026-11-19' }, { utc_offset_minutes: 60 }, { hour: 13 }]) {
    assert.throws(() => buildEvent('workout_completed', U, at, { ...GOOD.workout_completed, ...change }, O(1)), /disagree/, JSON.stringify(change));
    await assert.rejects(send([{ ...ok, event_properties: { ...ok.event_properties, ...change } }], { dryRun: true, env: {} }), /disagree/);
  }
  // a non-zero offset: local 12:00 at +05:30 is 06:30Z
  const kolkata = { ...GOOD.workout_completed, utc_offset_minutes: 330 };
  assert.equal(buildEvent('workout_completed', U, new Date(Date.UTC(2026, 10, 18, 6, 30)), kolkata, O(1)).time, Date.UTC(2026, 10, 18, 6, 30));
  // the required fields cannot be left out
  for (const f of ['local_date', 'local_week', 'utc_offset_minutes']) {
    const { [f]: _x, ...rest } = GOOD.workout_completed;
    assert.throws(() => buildEvent('workout_completed', U, at, rest, O(1)), /missing required property/);
  }
});

test('a source id makes a corrected start a supersede; without one a corrected start is delete-and-add', () => {
  const withId = (d, id = 'wk_0123abcd') => ({ ...day(d), id });
  const a1 = snapEvents({ ...COVER, workouts: [withId('2026-10-19')] }, U, { env: ENV_ID });
  const a2 = snapEvents({ coverage: { from: '2026-11-01', to: '2026-11-18' }, workouts: [withId('2026-11-02')] }, U, OPTS(a1.sent));
  assert.deepEqual(a2.events.map((e) => e.event_type), ['workout_completed']);
  assert.equal(a2.events[0].event_properties.supersedes, a1.events[0].event_properties.occurrence_id);
  assert.equal(live([...a1.events, ...a2.events]).length, 1);
  assert.equal(Object.keys(a2.sent.workouts).length, 1);
  // same id, same content: nothing; a different id is a different workout
  assert.deepEqual(snapEvents({ ...COVER, workouts: [withId('2026-10-19')] }, U, OPTS(a1.sent)).events, []);
  assert.equal(snapEvents({ ...COVER, workouts: [withId('2026-10-19'), withId('2026-10-19', 'wk_89abcdef')] }, U, { env: ENV_ID }).events.length, 2);
  // without an id: the old date is outside the new coverage, so both stay live (documented)
  const b1 = snapEvents({ ...COVER, workouts: [day('2026-10-19')] }, U, { env: ENV_ID });
  const b2 = snapEvents({ coverage: { from: '2026-11-01', to: '2026-11-18' }, workouts: [day('2026-11-02')] }, U, OPTS(b1.sent));
  assert.equal(live([...b1.events, ...b2.events]).length, 2);
  // inside the coverage the old one is retracted
  const b3 = snapEvents({ ...COVER, workouts: [day('2026-11-02')] }, U, OPTS(b1.sent));
  assert.deepEqual(b3.events.map((e) => e.event_type).sort(), ['workout_completed', 'workout_retracted']);
  assert.equal(live([...b1.events, ...b3.events]).length, 1);
  for (const id of ['Sam', 'wk_zz', 'wk_0123', 'WK_0123ABCD', 5, 'wk_' + 'a'.repeat(33)]) {
    assert.throws(() => snapEvents({ ...COVER, workouts: [{ ...day('2026-10-19'), id }] }, U, { env: ENV_ID }), /invalid workout id/);
  }
});

test('a Sunday 23:30 local workout at a non-UTC offset belongs to its local week', () => {
  const sun = { ...day('2026-11-22'), start: '2026-11-22T23:30:00-08:00', end: '2026-11-23T00:00:00-08:00' };
  const mon = day('2026-11-23');
  const r = snapEvents({ ...COVER, workouts: [sun, mon] }, U, { env: ENV_ID });
  const byWeek = {};
  for (const e of live(r.events)) byWeek[e.event_properties.local_week] = (byWeek[e.event_properties.local_week] ?? 0) + 1;
  assert.deepEqual(byWeek, { '2026-11-16': 1, '2026-11-23': 1 });
  // grouping by the absolute time would put both in the week of 2026-11-23
  const utcWeek = (t) => { const d = new Date(t); return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - ((d.getUTCDay() + 6) % 7))).toISOString().slice(0, 10); };
  assert.deepEqual(r.events.map((e) => utcWeek(e.time)), ['2026-11-23', '2026-11-23']);
});

const wk = (d, extra = {}) => ({ activityType: 'Running', start: `${d}T08:00:00-08:00`, end: `${d}T08:30:00-08:00`, durationMin: 30, ...extra });

test('a retraction time must be the start of a local hour in its offset, in the builder and the sender', async () => {
  const exact = new Date(Date.UTC(2026, 10, 18, 12, 31, 7));
  assert.throws(() => buildEvent('workout_retracted', U, exact, { utc_offset_minutes: 0 }, O(1)), /disagree/);
  assert.throws(() => buildEvent('workout_retracted', U, new Date(Date.UTC(2026, 10, 18, 12, 30)), { utc_offset_minutes: 0 }, O(1)), /disagree/);
  assert.throws(() => buildEvent('workout_retracted', U, at, {}, O(1)), /missing required property utc_offset_minutes/);
  // 12:30Z is a local hour start at +05:30
  const half = buildEvent('workout_retracted', U, new Date(Date.UTC(2026, 10, 18, 12, 30)), { utc_offset_minutes: 330 }, O(1));
  assert.equal(half.time, Date.UTC(2026, 10, 18, 12, 30));
  const ok = buildEvent('workout_retracted', U, at, { utc_offset_minutes: 0 }, O(1));
  await assert.rejects(sendEvents([{ ...ok, time: exact.getTime() }], { dryRun: true, env: {} }), /disagree/);
  await assert.rejects(sendEvents([{ ...ok, event_properties: { ...ok.event_properties, utc_offset_minutes: 30 } }], { dryRun: true, env: {} }), /disagree/);
  await assert.rejects(sendEvents([{ ...ok, event_properties: { occurrence_id: O(1) } }], { dryRun: true, env: {} }), /missing required property/);
});

test('a retraction from a snapshot carries the stored offset and an hour-start time', () => {
  const r1 = snapEvents({ ...COVER, workouts: [{ ...wk('2026-10-19'), start: '2026-10-19T21:47:00+05:30', end: '2026-10-19T22:17:00+05:30' }] }, U, { env: ENV_ID });
  const gone = snapEvents(EMPTY, U, OPTS(r1.sent));
  const e = gone.events[0];
  assert.equal(e.event_type, 'workout_retracted');
  assert.equal(e.event_properties.utc_offset_minutes, 330);
  assert.equal(e.time, Date.parse('2026-10-19T21:00:00+05:30'));
});

test('duplicate keys are deduplicated before eligibility, in any input order', () => {
  const short = wk('2026-10-19', { durationMin: 9, activityType: 'Walking', id: 'wk_0123abcd' });
  const long = wk('2026-10-19', { durationMin: 30, activityType: 'Running', id: 'wk_0123abcd' });
  const a = realSnap({ ...COVER, workouts: [short, long] }, U, { env: ENV_ID });
  const b = realSnap({ ...COVER, workouts: [long, short] }, U, { env: ENV_ID });
  assert.deepEqual(a.events, b.events);
  assert.deepEqual(a.next, b.next);
  // the kept record is the first by canonical content (Running sorts before Walking), so the workout is eligible
  assert.equal(a.events.length, 1);
  assert.equal(a.events[0].event_properties.activity, 'Running');
  // when the short one sorts first it is the kept record, and the long duplicate is ignored in both orders
  const short2 = wk('2026-10-19', { durationMin: 9, activityType: 'Cycling', id: 'wk_0123abcd' });
  const c = realSnap({ ...COVER, workouts: [short2, long] }, U, { env: ENV_ID });
  const d = realSnap({ ...COVER, workouts: [long, short2] }, U, { env: ENV_ID });
  assert.deepEqual(c.events, []);
  assert.deepEqual(c.events, d.events);
  assert.deepEqual(c.next, d.next);
  // several keys: the output order does not depend on the input order
  const many = [wk('2026-10-20'), wk('2026-10-19'), wk('2026-10-21')];
  assert.deepEqual(realSnap({ ...COVER, workouts: many }, U, { env: ENV_ID }).events, realSnap({ ...COVER, workouts: [...many].reverse() }, U, { env: ENV_ID }).events);
});

test('the four-week baseline fills missing weeks with zero before averaging', () => {
  const r = snapEvents({ ...COVER, workouts: [wk('2026-11-02'), wk('2026-11-03'), wk('2026-11-04'), wk('2026-11-05')] }, U, { env: ENV_ID }); // 4 workouts in the week of 2026-11-02
  const gone = new Set();
  const active = r.events.filter((e) => !gone.has(e.event_properties.occurrence_id));
  const countByWeek = {};
  for (const e of active) countByWeek[e.event_properties.local_week] = (countByWeek[e.event_properties.local_week] ?? 0) + 1;
  assert.deepEqual(countByWeek, { '2026-11-02': 4 });
  // the target week is 2026-11-30; its baseline weeks are the four calendar weeks before it
  const weeks = ['2026-11-02', '2026-11-09', '2026-11-16', '2026-11-23'];
  const filled = weeks.map((w) => countByWeek[w] ?? 0);
  assert.deepEqual(filled, [4, 0, 0, 0]);
  const baseline = filled.reduce((a, b) => a + b, 0) / 4;
  assert.equal(baseline, 1); // averaging only the weeks that have workouts would give 4
  const present = Object.values(countByWeek);
  assert.notEqual(present.reduce((a, b) => a + b, 0) / present.length, baseline);
});


test('the doc lists every event with its required properties, and stays short', () => {
  const doc = readFileSync(new URL('../docs/AMPLITUDE.md', import.meta.url), 'utf8');
  for (const name of Object.keys(EVENTS)) {
    const row = doc.split('\n').find((l) => l.startsWith(`| \`${name}\` |`));
    assert.ok(row, `no row for ${name}`);
    for (const prop of REQUIRED[name]) assert.ok(row.includes(prop), `${name} row lacks ${prop}`);
  }
  assert.ok(doc.split(/\s+/).filter(Boolean).length <= 800);
});

test('the source comes from the workout or the source option, is allowlisted, and is required', () => {
  const w = (extra = {}) => ({ activityType: 'Running', start: '2026-10-19T08:00:00-08:00', end: '2026-10-19T08:30:00-08:00', durationMin: 30, ...extra });
  const run = (workout, opts = {}) => rawSnap({ workouts: [workout] }, U, { env: ENV_ID, ...opts });
  assert.throws(() => run(w()), /workout source is required/);
  assert.equal(run(w(), { source: 'phone' }).events[0].event_properties.source, 'phone');
  assert.equal(run(w({ source: 'watch' })).events[0].event_properties.source, 'watch');
  assert.equal(run(w({ source: 'manual' }), { source: 'phone' }).events[0].event_properties.source, 'manual'); // the workout wins
  for (const ok of ['mock', 'phone', 'watch', 'manual']) assert.equal(run(w(), { source: ok }).events[0].event_properties.source, ok);
  for (const bad of ['device', 'Mock', '', 5, null, {}]) {
    assert.throws(() => run(w({ source: bad })), /invalid workout source/, String(bad));
    assert.throws(() => run(w(), { source: bad }), /invalid source option/, String(bad));
  }
  // a different source is different content: it is a correction, not a duplicate
  const first = rawSnap({ workouts: [w()] }, U, { env: ENV_ID, source: 'mock' });
  const again = rawSnap({ workouts: [w()] }, U, { env: ENV_ID, source: 'phone', sent: first.next });
  assert.equal(again.events[0].event_properties.supersedes, first.events[0].event_properties.occurrence_id);
  assert.deepEqual(rawSnap({ workouts: [w()] }, U, { env: ENV_ID, source: 'mock', sent: first.next }).events, []);
});

test('framing is required on recommendation_shown, with none for no framing', () => {
  const { framing: _f, ...noFraming } = GOOD.recommendation_shown;
  assert.throws(() => buildEvent('recommendation_shown', U, at, noFraming, O(1)), /missing required property framing/);
  assert.equal(buildEvent('recommendation_shown', U, at, { ...GOOD.recommendation_shown, framing: 'none' }, O(1)).event_properties.framing, 'none');
  assert.throws(() => buildEvent('recommendation_shown', U, at, { ...GOOD.recommendation_shown, framing: 'loud' }, O(1)), /invalid value for property framing/);
  assert.ok(REQUIRED.recommendation_shown.includes('framing'));
});

test('rounding is decimal-safe, half away from zero', () => {
  const cases = [
    [10.075, 10.08], [1.005, 1.01], [0.285, 0.29], [8.345, 8.35], [10.005, 10.01], [33.335, 33.34], [99.995, 100],
    [600.005, 600.01], [1439.995, 1440], [1.255, 1.26], [2.675, 2.68], [4.35, 4.35], [30.125, 30.13], [30.124, 30.12],
    [0, 0], [10, 10], [1440, 1440], [0.005, 0.01], [0.004, 0],
    [-1.005, -1.01], [-10.075, -10.08], [-0.285, -0.29],
    [1e-7, 0], [5e-324, 0], [1.5e21, 1.5e21], [123456789.125, 123456789.13],
  ];
  for (const [x, want] of cases) assert.equal(roundMinutes(x), want, String(x));
  // through the snapshot: eligible workouts only (10 or more unrounded)
  const snap = (m) => ({ workouts: [{ activityType: 'Running', start: '2026-10-19T08:00:00-08:00', end: '2026-10-19T08:10:24-08:00', durationMin: m }] });
  for (const [m, want] of [[10.075, 10.08], [10.005, 10.01], [33.335, 33.34], [99.995, 100], [600.005, 600.01], [1439.995, 1440]]) {
    assert.deepEqual(eventsFromSnapshot(snap(m), U).map((e) => e.event_properties.minutes), [want], String(m));
  }
});

test('same-id duplicates that round alike but differ in eligibility give the same result in either order', () => {
  const rec = (m) => ({ activityType: 'Running', start: '2026-10-19T08:00:00-08:00', end: '2026-10-19T08:30:00-08:00', durationMin: m, id: 'wk_0123abcd' });
  const a = realSnap({ workouts: [rec(9.999), rec(10)] }, U, { env: ENV_ID });
  const b = realSnap({ workouts: [rec(10), rec(9.999)] }, U, { env: ENV_ID });
  assert.deepEqual(a.events, b.events);
  assert.deepEqual(a.next, b.next);
  assert.equal(a.events.length, 1); // the winner is decided by content, not by input order
  const c = realSnap({ workouts: [rec(10.004), rec(9.9951)] }, U, { env: ENV_ID });
  const d = realSnap({ workouts: [rec(9.9951), rec(10.004)] }, U, { env: ENV_ID });
  assert.deepEqual(c.events, d.events);
  assert.deepEqual(c.next, d.next);
  // without ids the same difference is a rejection, in both orders
  const noId = (m) => { const { id: _i, ...r } = rec(m); return r; };
  for (const order of [[noId(9.999), noId(10)], [noId(10), noId(9.999)]]) assert.throws(() => eventsFromSnapshot({ workouts: order }, U), /need ids/);
});
