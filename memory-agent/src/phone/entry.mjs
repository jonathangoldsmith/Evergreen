// The phone entry: six functions Swift calls in JavaScriptCore. Each takes one JSON string and returns one JSON string;
// none throws. The host sets `globalThis.memoryIO` first: the store's io object (docs/PHONE.md).
//
//   memoryRoll({ root, user, snapshot, now, mode? })                  -> { ok, mode, day, wrote }
//   memoryTap({ root, user, recId, activity, weekday, hour, action, reason?, now })  -> the store's tap result
//   memoryForget({ root, user, what, ... })                           -> { ok }   what: recommendation | day | type | key | derived | preference
//   memoryPlannerText({ root, user })                                 -> { ok, text, words, ... } or { ok: false, error }
//   memoryFlush({ root, user })                                       -> { ok, events: [...] }   unsent Amplitude events, for the host to hand to the SDK
//   memoryAck({ root, user, acked })                                  -> { ok, left }            acked: insert ids the SDK took; they leave the outbox
//
// Amplitude events are staged only when the host also sets memoryIO.hmac(secret, data) and memoryIO.idSecret (docs/AMPLITUDE.md):
// a roll stages the day's workout events, a tap its recommendation events, forgetting a day retracts that day's delivered events.
import { MemoryStore, recordFeedback, forgetRecommendation, forgetFactType, forgetFactKey, forgetDerived, forget } from '../store/index.mjs';
import { rollDay } from '../memory/roll.mjs';
import { plannerText } from '../memory/planner-text.mjs';
import { buildEvent, opaqueId, newOutbox, loadOutbox, commitStaged, acknowledge, forgetDay, createIoStore } from '../amplitude/index.mjs';

const open = (a) => {
  const io = globalThis.memoryIO;
  if (!io) throw new Error('memoryIO is not set');
  return new MemoryStore(a.root, a.user, { io });
};

// Parses the arguments, opens the store, runs fn, and turns any failure into { ok: false, error } (the error name only).
const call = (argsJson, fn) => {
  try {
    const args = JSON.parse(argsJson);
    return JSON.stringify(fn(open(args), args));
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e && e.name ? e.name : 'Error') });
  }
};

const FORGET = {
  recommendation: (s, a) => forgetRecommendation(s, a.recId),
  day: (s, a) => forgetFactKey(s, 'daily', a.date),
  type: (s, a) => forgetFactType(s, a.type),
  key: (s, a) => forgetFactKey(s, a.type, a.key),
  derived: (s, a) => forgetDerived(s, a.kind),
  preference: (s, a) => forget(s, 'preferences', a.prefix),
};

// The Amplitude outbox of this user, or null when the host gave no id secret and hmac (memory-only use).
const outboxOf = (store, a) => {
  const io = globalThis.memoryIO;
  if (!io || typeof io.hmac !== 'function' || !io.idSecret) return null;
  const outStore = createIoStore({ io, dir: store.dir, userId: a.user });
  const loaded = loadOutbox(outStore, a.user);
  if (!loaded.ok) throw new Error(loaded.error);
  return { outStore, outbox: loaded.outbox ?? newOutbox(a.user), host: { hmac: io.hmac, secret: io.idSecret } };
};
const EVENT_ACTIVITY = { run: 'Running', walk: 'Walking', cycle: 'Cycling', swim: 'Swimming', strength: 'TraditionalStrengthTraining', yoga: 'Yoga', hike: 'Hiking', row: 'Rowing', elliptical: 'Elliptical', hiit: 'HighIntensityIntervalTraining', pilates: 'Pilates', dance: 'Dance' };
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const stage = (out, args) => {
  const r = commitStaged(out.outStore, out.outbox, { ...args, host: out.host, source: 'phone' });
  return r.ok ? { staged: r.added } : { stageError: r.error };
};

globalThis.memoryRoll = (argsJson) => call(argsJson, (store, a) => {
  const rolled = rollDay({ store, snapshot: a.snapshot, now: a.now, mode: a.mode });
  const out = rolled.ok ? outboxOf(store, a) : null;
  if (!out) return rolled;
  const events = [];
  if (rolled.mode === 'completed') {
    const rolling = store.read('rolling')?.facts ?? [];
    const planner = plannerText(store);
    events.push(buildEvent('memory_rolled', a.user, a.now, {
      daily_lines: rolling.filter((f) => f.kind === 'daily').length, weekly_lines: rolling.filter((f) => f.kind === 'weekly').length,
      preferences: store.read('preferences')?.facts.length ?? 0, prompt_words: planner.ok ? planner.words : 0,
    }, opaqueId('occ', `${a.user}|rolled|${rolled.day}`, out.host)));
  }
  return { ...rolled, ...stage(out, { snapshot: a.snapshot, events }) };
});
globalThis.memoryTap = (argsJson) => call(argsJson, (store, a) => {
  const tap = recordFeedback(store, a);
  const out = tap.written ? outboxOf(store, a) : null;
  if (!out) return tap;
  const props = { rec_id: a.recId, activity: EVENT_ACTIVITY[a.activity] ?? 'Other', weekday: WEEKDAYS[a.weekday - 1], hour: a.hour };
  const occ = (label) => opaqueId('occ', `${a.user}|${label}|${a.recId}`, out.host);
  const events = [];
  if (a.action === 'accepted') events.push(buildEvent('recommendation_accepted', a.user, a.now, props, occ('accepted')));
  else if (a.reason) events.push(buildEvent('recommendation_declined', a.user, a.now, { ...props, reason: a.reason }, occ('declined')));
  if (tap.promoted) events.push(buildEvent('preference_learned', a.user, a.now, { reason: a.reason, times_said: 2 }, opaqueId('occ', `${a.user}|learned|${a.reason}`, out.host)));
  return { ...tap, ...stage(out, { events }) };
});
globalThis.memoryForget = (argsJson) => call(argsJson, (store, a) => {
  if (!Object.hasOwn(FORGET, a.what)) return { ok: false, error: 'unknown what' };
  const ok = FORGET[a.what](store, a) === true;
  const out = ok && a.what === 'day' ? outboxOf(store, a) : null;
  if (!out) return { ok };
  const r = forgetDay(out.outStore, out.outbox, a.date);       // pending events of the day are dropped, delivered ones retracted
  return r.ok ? { ok } : { ok: false, error: r.error };
});
globalThis.memoryFlush = (argsJson) => call(argsJson, (store, a) => {
  const out = outboxOf(store, a);
  return out ? { ok: true, events: out.outbox.events } : { ok: false, error: 'no id secret or hmac set' };
});
globalThis.memoryAck = (argsJson) => call(argsJson, (store, a) => {
  const out = outboxOf(store, a);
  if (!out) return { ok: false, error: 'no id secret or hmac set' };
  const r = acknowledge(out.outStore, out.outbox, a.acked);
  return r.ok ? { ok: true, left: r.outbox.events.length } : { ok: false, error: r.error };
});
globalThis.memoryPlannerText = (argsJson) => call(argsJson, (store) => plannerText(store));
