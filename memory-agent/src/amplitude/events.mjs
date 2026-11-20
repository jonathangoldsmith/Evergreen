// Amplitude events for the memory: event names, allowed properties, builder, snapshot conversion.
// Only event-level facts go out. No heart rate, no raw samples, no routes, no names.
import { sha256Hex } from './sha256.mjs';

export const MIN_WORKOUT_MIN = 10;

export const EVENTS = Object.freeze({
  workout_completed: ['activity', 'minutes', 'weekday', 'hour', 'source', 'rec_id', 'supersedes', 'occurrence_id', 'local_date', 'local_week', 'utc_offset_minutes'],
  workout_retracted: ['occurrence_id', 'utc_offset_minutes'],
  workout_missed: ['activity', 'planned_weekday', 'planned_hour'],
  recommendation_shown: ['rec_id', 'activity', 'minutes', 'weekday', 'hour', 'framing'],
  recommendation_accepted: ['rec_id', 'activity', 'weekday', 'hour'],
  recommendation_declined: ['rec_id', 'activity', 'weekday', 'hour', 'reason'],
  comeback_accepted: ['rec_id', 'minutes'],
  recommendation_outcome: ['rec_id', 'outcome'],
  memory_rolled: ['daily_lines', 'weekly_lines', 'preferences', 'prompt_words'],
  preference_learned: ['reason', 'times_said'],
});

export const REASONS = Object.freeze(['too_early', 'too_late', 'too_long', 'too_hard', 'not_today']);
// The closed list of activity names an event may carry; anything else is sent as Other.
export const ACTIVITIES = Object.freeze([
  'Running', 'Walking', 'Cycling', 'Hiking', 'Swimming', 'Rowing', 'Elliptical', 'StairClimbing', 'Yoga', 'Pilates',
  'Dance', 'CoreTraining', 'Flexibility', 'MixedCardio', 'FunctionalStrengthTraining', 'TraditionalStrengthTraining',
  'HighIntensityIntervalTraining', 'Boxing', 'Tennis', 'Soccer', 'Basketball', 'Golf', 'Skiing', 'Climbing', 'Other',
]);
const compact = (t) => String(t).toLowerCase().replace(/[^a-z0-9]/g, '');
const ALIASES = new Map([
  ...ACTIVITIES.map((n) => [compact(n), n]),
  ['hiit', 'HighIntensityIntervalTraining'],
  ['strengthtraining', 'TraditionalStrengthTraining'],
]);
export const FRAMINGS = Object.freeze(['none', 'neutral', 'baseline', 'streak', 'comeback', 'rank']);
export const WEEKDAYS = Object.freeze(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
export const OUTCOMES = Object.freeze(['completed', 'not_completed']);
export const SOURCES = Object.freeze(['mock', 'phone', 'watch', 'manual']);
const OPAQUE = /^(usr|rec|occ)_[0-9a-f]{8,32}$/;
export const ID_PREFIXES = Object.freeze(['usr', 'rec', 'occ']);

// The host injects the one thing the core cannot do itself: hmac(secret, data) returns the lowercase hex
// HMAC-SHA256 of data under secret. `host` is {hmac, secret}; the secret (16+ characters) is TRACKER_ID_SECRET,
// kept outside the repo. Without it nothing runs, so an email or other low-entropy seed cannot be guessed.
export function hostHmac(host, label, data) {
  const secret = host?.secret;
  if (typeof host?.hmac !== 'function') throw new Error('host hmac is required');
  if (typeof secret !== 'string' || secret.length < 16) throw new Error('TRACKER_ID_SECRET is not set or too short');
  const out = host.hmac(secret, `${label}\u0000${data}`);
  if (typeof out !== 'string' || !/^[0-9a-f]{64}$/.test(out)) throw new Error('host hmac failed');
  return out;
}

// Identifiers are opaque: <prefix>_<8 to 32 lowercase hex>, made from a seed with the host's HMAC.
export function opaqueId(prefix, seed, host) {
  if (!ID_PREFIXES.includes(prefix)) throw new Error('unknown id prefix');
  if (typeof seed !== 'string' || seed.length === 0) throw new Error('id seed must be a non-empty string');
  return `${prefix}_${hostHmac(host, prefix, seed).slice(0, 16)}`;
}
const INSIDE = (list) => (v) => typeof v === 'string' && list.includes(v);
const NUM = (lo, hi) => (v) => typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi;
const INT = (lo, hi) => (v) => Number.isInteger(v) && v >= lo && v <= hi;
const idOf = (prefix) => (v) => typeof v === 'string' && OPAQUE.test(v) && v.startsWith(`${prefix}_`);
// 'YYYY-MM-DD' that is a real calendar date, as UTC midnight milliseconds; otherwise null.
export function parseDate(v) {
  const m = typeof v === 'string' && /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (!m) return null;
  const ms = Date.UTC(+m[1], +m[2] - 1, +m[3]);
  return new Date(ms).toISOString().slice(0, 10) === v ? ms : null;
}
const WEEKDAY_OF = (ms) => WEEKDAYS[(new Date(ms).getUTCDay() + 6) % 7];
const mondayOf = (ms) => new Date(ms - ((new Date(ms).getUTCDay() + 6) % 7) * 86400000).toISOString().slice(0, 10);

// A workout event's time must be the start of its local hour, computed from local_date, hour and the offset.
// Weekday must agree with local_date and local_week must be the Monday of that local week.
// A retraction's time must be the start of a local hour in its offset.
function checkRetractionTime(props, timeMs) {
  if (timeMs % 60000 !== 0 || (((timeMs + props.utc_offset_minutes * 60000) % 3600000) + 3600000) % 3600000 !== 0) {
    throw new Error('workout time fields disagree');
  }
}

function checkWorkoutTime(props, timeMs) {
  const dayMs = parseDate(props.local_date);
  if (dayMs === null || props.weekday !== WEEKDAY_OF(dayMs) || props.local_week !== mondayOf(dayMs)
    || timeMs !== dayMs + props.hour * 3600000 - props.utc_offset_minutes * 60000) {
    throw new Error('workout time fields disagree');
  }
}

const twoDecimals = (v) => Math.round(v * 100) / 100 === v;

// Properties every event must carry.
export const REQUIRED = Object.freeze({
  workout_completed: ['activity', 'minutes', 'weekday', 'hour', 'occurrence_id', 'local_date', 'local_week', 'utc_offset_minutes'],
  workout_retracted: ['occurrence_id', 'utc_offset_minutes'],
  workout_missed: ['activity', 'planned_weekday', 'planned_hour'],
  recommendation_shown: ['rec_id', 'activity', 'weekday', 'hour', 'framing'],
  recommendation_accepted: ['rec_id', 'activity'],
  recommendation_declined: ['rec_id', 'activity', 'reason'],
  comeback_accepted: ['rec_id', 'minutes'],
  recommendation_outcome: ['rec_id', 'outcome'],
  memory_rolled: ['daily_lines', 'weekly_lines', 'preferences', 'prompt_words'],
  preference_learned: ['reason', 'times_said'],
});

// One rule per property. A value that fails its rule rejects the whole event.
const RULES = {
  activity: INSIDE(ACTIVITIES),
  planned_weekday: INSIDE(WEEKDAYS),
  weekday: INSIDE(WEEKDAYS),
  planned_hour: INT(0, 23),
  hour: INT(0, 23),
  minutes: (v) => NUM(0, 1440)(v) && twoDecimals(v),
  framing: INSIDE(FRAMINGS),
  reason: INSIDE(REASONS),
  source: INSIDE(SOURCES),
  rec_id: idOf('rec'),
  supersedes: idOf('occ'),
  occurrence_id: idOf('occ'),
  local_date: (v) => parseDate(v) !== null,
  local_week: (v) => parseDate(v) !== null,
  utc_offset_minutes: INT(-840, 840),
  outcome: INSIDE(OUTCOMES),
  daily_lines: INT(0, 10000),
  weekly_lines: INT(0, 10000),
  preferences: INT(0, 10000),
  prompt_words: INT(0, 100000),
  times_said: INT(1, 10000),
};

// Keep allowed properties, drop the rest, reject any allowed property with a bad value.
function cleanProps(name, props) {
  if (props !== undefined && props !== null && (typeof props !== 'object' || Array.isArray(props))) {
    throw new Error('event properties must be an object');
  }
  const allowed = new Set(EVENTS[name]);
  const kept = {};
  for (const k of Object.keys(props || {}).sort()) {
    if (!allowed.has(k) || props[k] === undefined) continue;
    if (!RULES[k](props[k])) throw new Error(`invalid value for property ${k}`);
    kept[k] = props[k];
  }
  for (const k of REQUIRED[name]) {
    if (!Object.hasOwn(kept, k)) throw new Error(`missing required property ${k}`);
  }
  return kept;
}

export function checkUser(userId) {
  if (!idOf('usr')(userId)) throw new Error('user id must be opaque: usr_ and 8 to 32 lowercase hex');
}
function checkOccurrence(id) {
  if (!idOf('occ')(id)) throw new Error('occurrence id must be opaque: occ_ and 8 to 32 lowercase hex');
}

function insertIdOf(userId, name, occurrenceId) {
  return sha256Hex(JSON.stringify([userId, name, occurrenceId])).slice(0, 32);
}

// Used by the sender: every event is rebuilt from known fields only.
export function sanitizeEvent(e) {
  if (!e || typeof e !== 'object' || Array.isArray(e)) throw new Error('event must be an object');
  if (typeof e.event_type !== 'string' || !Object.hasOwn(EVENTS, e.event_type)) throw new Error('unknown event type');
  checkUser(e.user_id);
  if (!Number.isSafeInteger(e.time) || e.time <= 0) throw new Error('invalid event time');
  if (typeof e.insert_id !== 'string' || !/^[0-9a-f]{32}$/.test(e.insert_id)) throw new Error('invalid insert_id');
  const props = cleanProps(e.event_type, e.event_properties);
  // an event that names its occurrence must have the insert_id of that occurrence
  if (props.occurrence_id !== undefined && e.insert_id !== insertIdOf(e.user_id, e.event_type, props.occurrence_id)) {
    throw new Error('insert_id does not match the occurrence');
  }
  if (props.supersedes !== undefined && props.supersedes === props.occurrence_id) throw new Error('an event cannot supersede itself');
  if (e.event_type === 'workout_completed') checkWorkoutTime(props, e.time);
  if (e.event_type === 'workout_retracted') checkRetractionTime(props, e.time);
  return { user_id: e.user_id, event_type: e.event_type, time: e.time, event_properties: props, insert_id: e.insert_id };
}

// insert_id = first 32 hex of sha256(user id, event type, occurrence id). Properties are NOT in the hash.
// Re-sending the same occurrence unchanged carries the same insert_id and Amplitude deduplicates it.
// A correction is a NEW event with a new occurrence id and `supersedes` set to the old occurrence id.
export function buildEvent(name, userId, date, props, occurrenceId) {
  if (typeof name !== 'string' || !Object.hasOwn(EVENTS, name)) throw new Error('unknown event type');
  checkUser(userId);
  checkOccurrence(occurrenceId);
  if (props && typeof props === 'object' && props.supersedes === occurrenceId) throw new Error('an event cannot supersede itself');
  const at = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(at.getTime())) throw new Error('invalid event time');
  let given = props;
  if ((name === 'workout_completed' || name === 'workout_retracted') && given && typeof given === 'object' && !Array.isArray(given)) {
    // a workout event always names its own occurrence, so a correction can be matched against `supersedes`
    if (given.occurrence_id !== undefined && given.occurrence_id !== occurrenceId) throw new Error('occurrence_id does not match the occurrence');
    given = { ...given, occurrence_id: occurrenceId };
  }
  const kept = cleanProps(name, given);
  if (name === 'workout_completed') checkWorkoutTime(kept, at.getTime());
  if (name === 'workout_retracted') checkRetractionTime(kept, at.getTime());
  const insertId = insertIdOf(userId, name, occurrenceId);
  return {
    user_id: userId,
    event_type: name,
    time: at.getTime(),
    event_properties: kept,
    insert_id: insertId,
  };
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// Known aliases map to the canonical name; anything else is sent as "Other", never as free text.
export function canonicalActivity(type) {
  return typeof type === 'string' ? (ALIASES.get(compact(type)) ?? 'Other') : 'Other';
}

// Timestamps must carry Z or an offset. The same instant written with any offset is one instant.
function instant(iso) {
  const m = typeof iso === 'string' && /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(Z|[+-]\d{2}(?::?\d{2})?)$/i.exec(iso);
  if (!m) throw new Error('invalid workout time');
  let zone = m[3].toUpperCase();
  if (zone !== 'Z') zone = zone.length === 3 ? `${zone}:00` : zone.length === 5 ? `${zone.slice(0, 3)}:${zone.slice(3)}` : zone;
  const ms = Date.parse(`${m[1]}T${m[2]}${zone}`);
  if (Number.isNaN(ms)) throw new Error('invalid workout time');
  const offsetMin = zone === 'Z' ? 0 : (zone[0] === '-' ? -1 : 1) * (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6)));
  return { ms, offsetMin };
}

// The event time of a workout is the start of its LOCAL hour (by the offset written in the timestamp),
// never the exact start.
function floorToLocalHour({ ms, offsetMin }) {
  const off = offsetMin * 60000;
  const local = ms + off;
  return local - (((local % 3600000) + 3600000) % 3600000) - off;
}

// Weekday and hour are read from the wall clock written in the start timestamp, like the prototype.
function wallClock(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2})/.exec(iso);
  const day = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).getUTCDay();
  return { weekday: DAYS[day], hour: +m[4] };
}

// A workout has a stable key: HMAC-SHA256(TRACKER_ID_SECRET, user id + exact start instant in UTC), written as an
// occ_ id. The exact start is never sent or persisted. Its content is the end instant, minutes, canonical
// activity, weekday and hour (derived from the offset written in the timestamps) and source.
// Keyed too: an unkeyed hash of the content could be brute-forced to recover the exact end time.
const contentHash = (host, startMs, endMs, p) => hostHmac(
  host,
  'content',
  JSON.stringify([startMs, endMs, p.activity, p.minutes, p.weekday, p.hour, p.source, p.utc_offset_minutes]),
).slice(0, 16);

export function newSent(userId) {
  checkUser(userId);
  return { user: userId, workouts: {}, forgotten: [], tombstones: [] };
}

const SENT_FIELDS = ['user', 'workouts', 'forgotten', 'tombstones'];
const MAX_FORGOTTEN = 20000;
const ENTRY_FIELDS = ['hash', 'occurrence_id', 'version', 'day', 'prior', 'time', 'offset', 'live'];

// Validates a sent map and returns a clean copy rebuilt from the documented fields only. Any unknown field, at
// any level, is rejected rather than copied, so raw data can never ride along in the persisted state.
export function checkSent(sent, userId) {
  if (!sent || typeof sent !== 'object' || Array.isArray(sent) || !sent.workouts || typeof sent.workouts !== 'object' || Array.isArray(sent.workouts)) {
    throw new Error('sent must be a map made by newSent');
  }
  if (Object.keys(sent).some((k) => !SENT_FIELDS.includes(k))) throw new Error('sent has an unknown field');
  if (sent.user !== userId) throw new Error('sent belongs to another user');
  const workouts = {};
  for (const k of Object.keys(sent.workouts)) {
    const v = sent.workouts[k];
    if (!idOf('occ')(k) || !v || typeof v !== 'object' || Array.isArray(v) || !/^[0-9a-f]{16}$/.test(v.hash) || !idOf('occ')(v.occurrence_id)
      || !Number.isInteger(v.version) || v.version < 1 || !/^\d{4}-\d{2}-\d{2}$/.test(v.day)
      || !Number.isSafeInteger(v.time) || !Number.isInteger(v.offset) || v.offset < -840 || v.offset > 840 || typeof v.live !== 'boolean') {
      throw new Error('sent has an invalid entry');
    }
    if (Object.keys(v).some((f) => !ENTRY_FIELDS.includes(f))) throw new Error('sent has an unknown field');
    // `prior`: the local dates of earlier versions (dates only), so forgetting any day the workout was on finds it
    const prior = v.prior === undefined ? [] : v.prior;
    if (!Array.isArray(prior) || prior.length > 1000 || prior.some((d) => parseDate(d) === null)) throw new Error('sent has an invalid entry');
    workouts[k] = { hash: v.hash, occurrence_id: v.occurrence_id, version: v.version, day: v.day, prior: [...new Set(prior)].sort(), time: v.time, offset: v.offset, live: v.live };
  }
  // forgotten local dates (dates only): workouts on these days are ignored by later snapshots
  const rawForgotten = sent.forgotten === undefined ? [] : sent.forgotten;
  if (!Array.isArray(rawForgotten) || rawForgotten.length > MAX_FORGOTTEN || rawForgotten.some((d) => parseDate(d) === null)) {
    throw new Error('sent has an invalid forgotten list');
  }
  // tombstones of forgotten workouts: {key, version, restored}. The key is the keyed hash that already identifies the
  // workout (never a raw id or time); the version keeps the history, so a restored workout never reuses an old one.
  const rawTombs = sent.tombstones === undefined ? [] : sent.tombstones;
  if (!Array.isArray(rawTombs) || rawTombs.length > MAX_FORGOTTEN) throw new Error('sent has an invalid tombstone list');
  const seenKeys = new Set();
  const tombstones = rawTombs.map((t) => {
    if (!t || typeof t !== 'object' || Array.isArray(t) || Object.keys(t).some((f) => !['key', 'version', 'restored'].includes(f))
      || !idOf('occ')(t.key) || !Number.isInteger(t.version) || t.version < 1 || typeof t.restored !== 'boolean' || seenKeys.has(t.key)) {
      throw new Error('sent has an invalid tombstone');
    }
    seenKeys.add(t.key);
    return { key: t.key, version: t.version, restored: t.restored };
  }).sort((a, b) => (a.key < b.key ? -1 : 1));
  return { user: sent.user, workouts, forgotten: [...new Set(rawForgotten)].sort(), tombstones };
}

// Coverage is declared by the caller: snapshot.coverage = {from, to}, local dates (YYYY-MM-DD) the caller guarantees
// are complete. It is never inferred from daily summaries or the export date. No coverage means no retraction.
function coverage(snapshot) {
  const c = snapshot.coverage;
  if (c === undefined || c === null) return null;
  if (typeof c !== 'object' || Array.isArray(c) || parseDate(c.from) === null || parseDate(c.to) === null || c.from > c.to) {
    throw new Error('invalid coverage');
  }
  return { from: c.from, to: c.to };
}

// The event's `minutes` is the duration rounded half away from zero to 2 decimals, always.
// Decimal-safe: the exponent-string method scales by 10^2 in decimal, not in binary (10.075 -> 10.08, 1.005 -> 1.01).
// A number that already prints in exponent form is tiny or huge; plain scaling is exact enough there.
export function roundMinutes(m) {
  const sign = m < 0 ? -1 : 1;
  const x = Math.abs(m);
  const str = String(x);
  if (str.includes('e')) return sign * (Math.round(x * 100) / 100);
  return sign * Number(`${Math.round(Number(`${str}e2`))}e-2`);
}

const SOURCE_ID = /^wk_[0-9a-f]{8,32}$/;

// userId must already be opaque (see opaqueId). host is {hmac, secret}.
// `sent` is the delivered state (from newSent(userId) or applyAcks); the caller persists it. It is bound to one
// user and refused for any other. It holds only keyed hashes, versions, a local date, an offset and an
// hour-level time. This function never changes it.
// The snapshot must have a `workouts` array; every workout needs a valid numeric durationMin (otherwise the
// snapshot is rejected: a missing duration is not "under 10 minutes"). A workout may carry an optional stable
// source `id` (wk_ and 8 to 32 lowercase hex); with it, the key is HMAC(user id, id) and a corrected start
// supersedes the old occurrence. Without it the key is HMAC(user id, start instant), so a corrected start is
// delete-and-add and the old one is retracted only if its local date is inside the declared coverage.
// Records with the same key are deduplicated FIRST (without ids, only identical records may share a start; others
// are rejected with 'workouts at the same start need ids'): they are sorted by canonical content (a JSON string of
// start, end, activity, minutes, offset, weekday, hour, source compared in code-unit order) and the first is kept; only
// then is the 10-minute eligibility applied. The input order therefore never changes the result.
// Per workout key:
//   new key                      -> workout_completed, version 1
//   same key, same content       -> nothing
//   same key, different content  -> workout_completed, version + 1, `supersedes` = previous occurrence id
//   sent before, absent from the snapshot, local date inside snapshot.coverage
//                                -> workout_retracted naming the last live occurrence
//      (without coverage, or outside it, an absent workout stays live)
//   sent before and now under 10 minutes -> workout_retracted (it is present, so no coverage is needed)
//   a retracted key that comes back -> workout_completed with the next version (no supersedes)
// Returns {events, next}. Do not call this directly in the delivery loop: use stageSnapshot (outbox.mjs), which
// persists `next` and `events` together as a write-ahead outbox before anything is sent. Versions only ever
// increase, so a correction made after a delivered-but-unacknowledged event is a new version with a new
// insert_id (insert_id = f(user, event type, occurrence id)) and is never dropped as a duplicate.
export function eventsFromSnapshot(snapshot, userId, { host, sent, source } = {}) {
  if (source !== undefined && !SOURCES.includes(source)) throw new Error('invalid source option');
  if (!snapshot || typeof snapshot !== 'object' || !Array.isArray(snapshot.workouts)) throw new Error('snapshot must have a workouts array');
  const prev = checkSent(sent === undefined ? newSent(userId) : sent, userId);
  const cover = coverage(snapshot);
  const forgotten = new Set(prev.forgotten);
  const tombs = new Map(prev.tombstones.map((t) => [t.key, t]));
  const newTombs = new Map();
  const forgottenKeys = new Set(); // keys of snapshot workouts that sit on a forgotten day

  const byKey = new Map();
  for (const w of snapshot.workouts) {
    if (!w || typeof w !== 'object') throw new Error('invalid workout');
    if (typeof w.durationMin !== 'number' || !Number.isFinite(w.durationMin) || w.durationMin < 0 || w.durationMin > 1440) throw new Error('invalid workout duration');
    const start = instant(w.start);
    if (w.id !== undefined && (typeof w.id !== 'string' || !SOURCE_ID.test(w.id))) throw new Error('invalid workout id');
    const basis = w.id !== undefined ? `id|${w.id}` : `start|${start.ms}`;
    const key = opaqueId('occ', `${userId}|${basis}`, host);
    const src = w.source !== undefined ? w.source : source;
    if (src === undefined) throw new Error('workout source is required');
    if (!SOURCES.includes(src)) throw new Error('invalid workout source');
    const endMs = w.end === undefined || w.end === null ? '' : instant(w.end).ms;
    const { weekday, hour } = wallClock(w.start);
    const localDate = w.start.slice(0, 10);
    if (forgotten.has(localDate)) {
      // the person forgot this day: the workout's stable key is forgotten, whatever other record carries it
      forgottenKeys.add(key);
      continue;
    }
    if (tombs.has(key) && !tombs.get(key).restored) continue; // the person forgot this workout: whatever date it carries
    const props = {
      activity: canonicalActivity(w.activityType),
      minutes: roundMinutes(w.durationMin),
      weekday,
      hour,
      source: src,
      local_date: localDate,
      local_week: mondayOf(parseDate(localDate)),
      utc_offset_minutes: start.offsetMin,
    };
    // the unrounded duration is part of the identity, so two records that round alike but differ in eligibility never tie
    const content = JSON.stringify([start.ms, endMs, props.activity, props.minutes, props.utc_offset_minutes, props.weekday, props.hour, props.source, w.durationMin]);
    const rec = { key, basis, start, endMs, props, content, localDate, raw: w.durationMin };
    const have = byKey.get(key);
    // identical records are one workout; different records at the same start need source ids to tell them apart
    if (have && w.id === undefined && content !== have.content) throw new Error('workouts at the same start need ids');
    if (!have || content < have.content) byKey.set(key, rec);
  }

  // Forgotten keys are resolved across the whole snapshot FIRST: every record with such a key is dropped, whatever
  // date it carries, any live occurrence already recorded is retracted and removed, and the key is tombstoned.
  for (const key of forgottenKeys) byKey.delete(key);
  const workoutsNext = { ...prev.workouts };
  const events = [];
  for (const key of [...forgottenKeys].sort()) {
    const old = prev.workouts[key];
    if (old) {
      if (old.live) events.push(buildEvent('workout_retracted', userId, new Date(old.time), { utc_offset_minutes: old.offset }, old.occurrence_id));
      delete workoutsNext[key];
    }
    if (!tombs.has(key)) newTombs.set(key, { key, version: old ? old.version : 1, restored: false });
  }
  const tombstones = [...prev.tombstones, ...newTombs.values()].sort((a, b) => (a.key < b.key ? -1 : 1));
  const next = { user: userId, workouts: workoutsNext, forgotten: prev.forgotten, tombstones };
  const eligible = new Set();
  for (const rec of [...byKey.values()].sort((a, b) => (a.key < b.key ? -1 : 1))) {
    if (rec.raw < MIN_WORKOUT_MIN) continue; // eligibility uses the unrounded duration, like the fact engine
    eligible.add(rec.key);
    const hash = contentHash(host, rec.start.ms, rec.endMs, rec.props);
    const old = prev.workouts[rec.key];
    if (old && old.live && old.hash === hash) continue;
    // a restored tombstone keeps the history: the version continues after the forgotten one, never restarts at 1
    const floor = tombs.has(rec.key) ? tombs.get(rec.key).version : 0;
    const version = Math.max(old ? old.version : 0, floor) + 1;
    const occ = opaqueId('occ', `${userId}|${rec.basis}|${version}`, host);
    const extra = old && old.live ? { supersedes: old.occurrence_id } : {};
    const time = floorToLocalHour(rec.start);
    events.push(buildEvent('workout_completed', userId, new Date(time), { ...rec.props, ...extra }, occ));
    const prior = old ? [...new Set([...old.prior, old.day])].filter((d) => d !== rec.localDate).sort() : [];
    next.workouts[rec.key] = { hash, occurrence_id: occ, version, day: rec.localDate, prior, time, offset: rec.start.offsetMin, live: true };
  }
  for (const key of Object.keys(prev.workouts).sort()) {
    const old = prev.workouts[key];
    if (!old.live || eligible.has(key) || forgottenKeys.has(key)) continue;
    const present = byKey.has(key); // present but shorter than 10 minutes now
    const covered = cover && old.day >= cover.from && old.day <= cover.to;
    if (!present && !covered) continue;
    events.push(buildEvent('workout_retracted', userId, new Date(old.time), { utc_offset_minutes: old.offset }, old.occurrence_id));
    next.workouts[key] = { ...old, live: false };
  }
  return { events, next };
}
