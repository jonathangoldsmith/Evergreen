// The outbox as a state machine. Pure: no node: import, no Node global. Everything that needs a host is injected:
//   host  = {hmac, secret}     ids and content hashes (see events.mjs)
//   store = {save, load, sync} persistence; each returns a result object as described below
//   deliver(events)            hands events to a delivery (the Amplitude iOS SDK on the phone; a fetch sender in tests)
// The outbox is {user, state, events}: the adopted workout state and the events not yet acknowledged, saved together.
// Loop: commitSnapshot (save state + events, then adopt), deliverOutbox (hand over, acknowledge, save).
// On restart: loadOutbox, deliver whatever is still in the outbox FIRST, then build from a new snapshot.
import { eventsFromSnapshot, newSent, checkSent, checkUser, sanitizeEvent, buildEvent, parseDate } from './events.mjs';

const OUTBOX_FIELDS = ['user', 'state', 'events', 'status'];
const FAIL = (error, more = {}) => ({ ok: false, error, ...more });

export function newOutbox(userId) {
  return { user: userId, state: newSent(userId), events: [] };
}

// Rebuilds the outbox from the documented fields only: user, state (checked and rebuilt field by field) and events
// (each rebuilt by the event validator, each belonging to the outbox user). Unknown fields are rejected, never
// copied. `status` is an in-memory marker that is never saved.
export function checkOutbox(o) {
  if (!o || typeof o !== 'object' || Array.isArray(o) || !Array.isArray(o.events)) throw new Error('outbox is invalid');
  if (Object.keys(o).some((k) => !OUTBOX_FIELDS.includes(k))) throw new Error('outbox has an unknown field');
  if (o.status !== undefined && o.status !== 'unrecovered' && o.status !== 'unsynced') throw new Error('outbox is invalid');
  checkUser(o.user);
  const events = o.events.map(sanitizeEvent);
  if (events.some((e) => e.user_id !== o.user)) throw new Error('outbox event belongs to another user');
  const out = { user: o.user, state: checkSent(o.state, o.user), events };
  if (o.status !== undefined) out.status = o.status;
  return out;
}

// 'unrecovered': the saved file could not be read back after the write; load it first.
// 'unsynced': the write happened but is not known to be durable; nothing may be delivered or staged until syncOutbox
// (or loadOutbox) succeeds.
function checkUsable(o) {
  if (o.status === 'unrecovered') throw new Error('outbox state is unrecovered; load it with loadOutbox first');
  if (o.status === 'unsynced') throw new Error('outbox is not synced to disk; run syncOutbox first');
  return o;
}

// The plain, saveable form of an outbox (no status); refuses an outbox that is blocked.
export function plainOutbox(outbox) {
  const o = checkUsable(checkOutbox(outbox));
  return { user: o.user, state: o.state, events: o.events };
}

// Stage a snapshot: build events and the next state against the adopted state. Refused while events are still
// unsent and while the outbox is blocked.
export function stageSnapshot(outbox, snapshot, { host, source } = {}) {
  const o = plainOutbox(outbox);
  if (o.events.length > 0) throw new Error('outbox has unsent events; deliver them first');
  const { events, next } = eventsFromSnapshot(snapshot, o.user, { host, sent: o.state, source });
  return { user: o.user, state: next, events };
}

// Remove acknowledged events. `acked` is a list of insert_ids or an object {acked: [{insert_ids}]}.
export function ackOutbox(outbox, acked) {
  const o = plainOutbox(outbox);
  const ids = Array.isArray(acked) ? acked : (acked?.acked ?? []).flatMap((b) => b.insert_ids);
  const done = new Set(ids);
  return { user: o.user, state: o.state, events: o.events.filter((e) => !done.has(e.insert_id)) };
}

// A store's result: {ok: true}, or {ok: false, error, ...} where the store may add
//   outbox      what is really persisted (adopt it)
//   unsynced    the write happened but is not known durable
//   unrecovered the persisted content could not be read back
// Whatever a store returns is re-validated here; its error text is replaced by fixed text.
// A store that throws, or answers with something that is not a result, may have written before it failed: the
// persisted state is unknown, so the result is `unrecovered` until a successful load establishes it.
function callStore(fn, ...args) {
  try {
    const r = fn(...args);
    if (!r || typeof r !== 'object') return FAIL('outbox could not be saved', { unrecovered: true });
    return r;
  } catch {
    return FAIL('outbox could not be saved', { unrecovered: true });
  }
}

// What the caller should hold after a failed save: what is really persisted, the same outbox marked unsynced or
// unrecovered, or the outbox it started from (nothing was changed).
function afterFailedSave(saved, original) {
  try {
    if (saved.unsynced && saved.outbox) {
      const { status: _s, ...plain } = checkOutbox(saved.outbox);
      return { ...plain, status: 'unsynced' };
    }
    if (saved.outbox) {
      const { status: _s, ...plain } = checkOutbox(saved.outbox);
      return plain;
    }
  } catch {
    return { ...original, status: 'unrecovered' };
  }
  if (saved.unrecovered) return { ...original, status: 'unrecovered' };
  return original;
}

// A host store's error text is never passed on. It is kept only if it equals one of these fixed messages; anything
// else, which could carry a name, health data or a key, becomes 'store failed'.
const STORE_ERRORS = [
  'outbox could not be saved', 'outbox could not be read', 'outbox could not be synced', 'outbox is invalid',
  'outbox directory sync failed', 'outbox state unrecovered', 'outbox on disk differs from the intended content',
  'outbox read-back did not match',
];
const fixedError = (r) => (typeof r?.error === 'string' && STORE_ERRORS.includes(r.error) ? r.error : 'store failed');

// Saves and then PROVES it: after the store reports success the core calls load() and requires the loaded outbox to
// equal the one it saved (canonical form). If it does not (the load fails, or returns something else) the new outbox
// may still be what is persisted, so the result is marked `unrecovered`: the caller holds the old outbox marked
// unrecovered, and nothing may be staged, delivered, acknowledged or forgotten until loadOutbox succeeds and its
// content is adopted.
function persist(store, plain) {
  const saved = callStore((o) => store.save(o), plain);
  if (!saved.ok) return saved;
  try {
    const r = store.load();
    if (!r || r.ok !== true || !r.outbox) return FAIL('outbox read-back did not match', { unrecovered: true });
    const back = checkOutbox(r.outbox);
    if (back.status !== undefined || JSON.stringify(back) !== JSON.stringify(plain)) return FAIL('outbox read-back did not match', { unrecovered: true });
  } catch {
    return FAIL('outbox read-back did not match', { unrecovered: true });
  }
  return { ok: true };
}

// Stage a snapshot and save it. The staged outbox is adopted (returned as `outbox`) only if the save succeeded;
// otherwise `outbox` is what is really persisted, the old outbox, or a marked outbox (see the doc's table).
export function commitSnapshot(store, outbox, snapshot, { host, source } = {}) {
  const staged = stageSnapshot(outbox, snapshot, { host, source });
  const saved = persist(store, staged);
  if (saved.ok) return { ok: true, outbox: staged };
  return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
}

// The phone delivers asynchronously, so a new day or tap can arrive while earlier events are still unsent. This stages
// more events on top of the unsent ones: the events of a snapshot (built against the adopted state) and/or ready-made
// events. An event already in the outbox (same insert_id) is not added twice. Saved and proved like every save.
export function commitStaged(store, outbox, { snapshot, events = [], host, source } = {}) {
  const o = plainOutbox(outbox);
  let state = o.state;
  let built = [];
  if (snapshot) ({ events: built, next: state } = eventsFromSnapshot(snapshot, o.user, { host, sent: o.state, source }));
  const have = new Set(o.events.map((e) => e.insert_id));
  const added = [...built, ...events].map(sanitizeEvent).filter((e) => !have.has(e.insert_id) && have.add(e.insert_id));
  const staged = { user: o.user, state, events: [...o.events, ...added] };
  const saved = persist(store, staged);
  if (saved.ok) return { ok: true, outbox: staged, added: added.length };
  return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
}

// Record a delivery result from the host (a list of insert_ids, or {acked: [{insert_ids}]}): acknowledged events leave the outbox.
export function acknowledge(store, outbox, acked) {
  const after = ackOutbox(outbox, acked);
  const saved = persist(store, after);
  if (saved.ok) return { ok: true, outbox: after };
  return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
}

// Hand the outbox events to `deliver` (async; returns {acked: [{insert_ids}], failed: [...]} or a list of acknowledged
// insert_ids), remove the acknowledged ones and save. If that save fails the ORIGINAL outbox is returned (or what is
// really persisted), still listing the events, so they are handed over again with the same insert_ids and nothing
// is staged over events that were never durably acknowledged.
export async function deliverOutbox(store, outbox, deliver) {
  const o = plainOutbox(outbox);
  if (o.events.length === 0) return { outbox: o, delivery: null, saved: { ok: true } };
  const delivery = await deliver(o.events);
  const after = ackOutbox(o, delivery);
  const saved = persist(store, after);
  if (saved.ok) return { outbox: after, delivery, saved };
  return { outbox: afterFailedSave(saved, o), delivery, saved: { ok: false, error: fixedError(saved) } };
}

// {ok: true, outbox} (outbox is null when nothing was saved yet) or {ok: false, error}. The outbox must belong to userId.
export function loadOutbox(store, userId) {
  let r;
  try {
    r = store.load();
  } catch {
    return FAIL('outbox could not be read');
  }
  if (!r || typeof r !== 'object' || r.ok !== true) return FAIL(r && typeof r === 'object' ? fixedError(r) : 'outbox could not be read');
  if (r.outbox === null) return { ok: true, outbox: null };
  try {
    const o = checkOutbox(r.outbox);
    if (o.status !== undefined || o.user !== userId) throw new Error('outbox is invalid');
    return { ok: true, outbox: o };
  } catch {
    return FAIL('outbox is invalid');
  }
}

// Retry making an 'unsynced' outbox durable: the store re-verifies what it holds and syncs. Success returns the
// outbox without the marker; otherwise the same kinds of result as a failed save.
export function syncOutbox(store, outbox) {
  let o;
  try {
    o = checkOutbox(outbox);
    if (o.status !== 'unsynced') throw new Error('not unsynced');
  } catch {
    return FAIL('outbox could not be synced');
  }
  const { status: _s, ...plain } = o;
  const r = callStore((x) => store.sync(x), plain);
  if (r.ok) return { ok: true, outbox: plain };
  return { ok: false, error: fixedError(r), outbox: afterFailedSave(r, o) };
}

// Forget a local day. Pending events of that day are removed so they are never delivered; occurrences of that day
// that were already delivered get a `workout_retracted` staged (so analytics stops counting them); the day's
// occurrences leave the state; and the date (a date only) is kept in the state, so a later snapshot's workouts on
// that day emit nothing. Saved atomically and proved by read-back like every save; on failure the old outbox is kept.
export function forgetDay(store, outbox, localDate) {
  if (parseDate(localDate) === null) throw new Error('invalid local date');
  const o = plainOutbox(outbox);
  const dropIds = new Set();
  const retract = new Map(); // occurrence id -> {time, offset}
  const isCompleted = (e) => e.event_type === 'workout_completed';
  // A pending event may already have reached the SDK (its acknowledgement may never have been saved), so a dropped
  // event is retracted too, and so is the version its correction replaced.
  const dropEvent = (e, time, offset) => {
    dropIds.add(e.insert_id);
    retract.set(e.event_properties.occurrence_id, { time, offset });
    if (e.event_properties.supersedes) retract.set(e.event_properties.supersedes, { time, offset });
  };
  for (const e of o.events) if (isCompleted(e) && e.event_properties.local_date === localDate) dropEvent(e, e.time, e.event_properties.utc_offset_minutes);
  const tombs = new Map(o.state.tombstones.map((t) => [t.key, t]));
  const workouts = {};
  for (const [key, entry] of Object.entries(o.state.workouts)) {
    // a workout is forgotten if the day is its current day or the day of any earlier version
    if (entry.day !== localDate && !entry.prior.includes(localDate)) { workouts[key] = entry; continue; }
    tombs.set(key, { key, version: entry.version, restored: false }); // the workout itself, on any date
    for (const e of o.events) if (isCompleted(e) && e.event_properties.occurrence_id === entry.occurrence_id) dropEvent(e, entry.time, entry.offset);
    if (entry.live) retract.set(entry.occurrence_id, { time: entry.time, offset: entry.offset });
  }
  const pendingRetractions = new Set(o.events.filter((e) => e.event_type === 'workout_retracted').map((e) => e.event_properties.occurrence_id));
  const events = o.events.filter((e) => !dropIds.has(e.insert_id));
  for (const [occ, { time, offset }] of [...retract.entries()].sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (pendingRetractions.has(occ)) continue;
    events.push(buildEvent('workout_retracted', o.user, new Date(time), { utc_offset_minutes: offset }, occ));
  }
  const next = { user: o.user, state: { user: o.user, workouts, forgotten: [...new Set([...o.state.forgotten, localDate])].sort(), tombstones: [...tombs.values()].sort((a, b) => (a.key < b.key ? -1 : 1)) }, events };
  const saved = persist(store, next);
  if (saved.ok) return { ok: true, outbox: next };
  return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
}

// Explicitly undo forgetting: the forgotten dates are cleared and every tombstone is marked restored, so the
// workouts can be emitted again. A restored workout continues after its forgotten version (never version 1 again),
// so it is not cancelled by the earlier retraction. Saved and proved like every save.
export function restoreForgotten(store, outbox) {
  const o = plainOutbox(outbox);
  const next = {
    user: o.user,
    state: { user: o.user, workouts: o.state.workouts, forgotten: [], tombstones: o.state.tombstones.map((t) => ({ ...t, restored: true })) },
    events: o.events,
  };
  const saved = persist(store, next);
  if (saved.ok) return { ok: true, outbox: next };
  return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
}
