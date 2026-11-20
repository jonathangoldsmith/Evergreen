// The four-week trial for one persona, shared by scripts/trial.mjs and its test. Node only; no network here.
// 28 daily rolls at local midnight over a sample persona, scripted taps, one forgotten day, one forgotten recommendation.
// It returns what a reader could see (files, planner text, Amplitude events) so the caller can measure and check them.
import fs from 'node:fs';
import path from 'node:path';
import { openNodeStore } from '../../src/store/node/node-store.mjs';
import { recordFeedback, forgetRecommendation, forgetFactKey, FILE_KINDS } from '../../src/store/index.mjs';
import { rollDay } from '../../src/memory/roll.mjs';
import { plannerText } from '../../src/memory/planner-text.mjs';
import { buildEvent, opaqueId, newOutbox, commitStaged, acknowledge, forgetDay } from '../../src/amplitude/index.mjs';
import { nodeHost } from '../../src/amplitude/node/host.mjs';
import { sha256Hex } from '../../src/amplitude/sha256.mjs';

export const PERSONAS = ['sedentary', 'moderate', 'half_marathon'];
export const TEST_USER_PREFIX = 'usr_7e57';          // every trial user id starts with this ("test"), so test data is easy to spot
export const WEEK_ENDS = [6, 13, 20, 27];             // measure after the roll of day 7, 14, 21 and 28
const FIRST = Date.UTC(2026, 9, 21);                  // first midnight roll: 2026-10-21 (describes 10-20)
export const FORGET_DAY = '2026-11-02';
// Not a secret: ids made with it only name sample personas. Real ids use the owner's TRACKER_ID_SECRET on the phone.
const ID_SALT = 'trial-sample-ids-only-0001';
const HOST = { ...nodeHost({}), secret: ID_SALT };

export const loadPersona = (who) => JSON.parse(fs.readFileSync(new URL(`../../fixtures/personas/${who}.json`, import.meta.url), 'utf8'));
export const dateOf = (i) => new Date(FIRST + i * 86400000).toISOString().slice(0, 10);
export const userIdOf = (who) => `${TEST_USER_PREFIX}${sha256Hex(`trial|${who}`).slice(0, 8)}`;
const recId = (n) => `rec_${String(n).padStart(8, '0')}`;

// Scripted taps: [day, number, store activity, event activity, weekday (1 = Mon), hour, action, reason]. The two too_early
// declines become a standing preference; the accept is the third tap.
const TAPS = [
  [5, 1, 'run', 'Running', 3, 7, 'declined', 'too_early'],
  [7, 2, 'run', 'Running', 5, 6, 'declined', 'too_early'],
  [9, 3, 'walk', 'Walking', 2, 18, 'accepted'],
];
const WEEKDAY = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const FORGET_REC_AT = 15;                             // recommendation 1 is forgotten on this day
const FORGET_DAY_AT = 20;                             // the day 2026-11-02 is forgotten on this day

/** Workout events of `day` that still count: not superseded and not retracted (the query in docs/AMPLITUDE.md). */
export function activeWorkoutsOn(events, day) {
  const gone = new Set(events.flatMap((e) => (e.event_type === 'workout_retracted' ? [e.event_properties.occurrence_id] : e.event_properties.supersedes ? [e.event_properties.supersedes] : [])));
  return events.filter((e) => e.event_type === 'workout_completed' && e.event_properties.local_date === day && !gone.has(e.event_properties.occurrence_id));
}

/** All files under dir: relative path -> text. */
export function readTree(dir) {
  const out = {};
  const walk = (d) => {
    for (const name of fs.readdirSync(d).sort()) {
      const p = path.join(d, name);
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (!name.endsWith('.memtmp')) out[path.relative(dir, p)] = fs.readFileSync(p, 'utf8');
    }
  };
  walk(dir);
  return out;
}

const factsIn = (store, name) => store.read(name)?.facts ?? [];

/** Runs the 28 days in `root` (an empty folder). Returns { who, uid, weeks, events, files, planner, plannerFinal, steps }. */
export function runTrial(who, root) {
  const snapshot = loadPersona(who);
  const uid = userIdOf(who);
  const store = openNodeStore(root, uid);
  const occ = (label) => opaqueId('occ', `${uid}|${label}`, HOST);
  // Events go through the outbox as on the phone: each day stages, then everything staged counts as delivered and is
  // acknowledged (the sample snapshot holds all four weeks, so every workout is staged on the first roll). Forgetting the day retracts its delivered workout events; the day stays out of later rolls.
  const events = [];
  let held = null;
  const outStore = { save: (o) => { held = JSON.parse(JSON.stringify(o)); return { ok: true }; }, load: () => ({ ok: true, outbox: held }), sync: () => ({ ok: true }) };
  let outbox = newOutbox(uid);
  const stage = (args) => {
    const r = commitStaged(outStore, outbox, { ...args, host: HOST, source: 'mock' });
    if (!r.ok) throw new Error(`outbox: ${r.error}`);
    outbox = r.outbox;
  };
  const deliver = () => {
    events.push(...outbox.events);
    const r = acknowledge(outStore, outbox, outbox.events.map((e) => e.insert_id));
    if (!r.ok) throw new Error(`outbox: ${r.error}`);
    outbox = r.outbox;
  };
  const result = { who, uid, weeks: [], steps: [], planner: [] };
  for (let i = 0; i < 28; i++) {
    const day = dateOf(i);
    const tapAt = `${day}T12:00:00.000Z`;
    for (const [at, n, activity, eventActivity, weekday, hour, action, reason] of TAPS) {
      if (at !== i) continue;
      const tap = recordFeedback(store, { recId: recId(n), activity, weekday, hour, action, reason, now: tapAt });
      if (!tap.written) throw new Error(`tap ${n} not written: ${tap.why}`);
      const rec = { rec_id: recId(n), activity: eventActivity, weekday: WEEKDAY[weekday - 1], hour };
      const tapEvents = [buildEvent('recommendation_shown', uid, tapAt, { ...rec, framing: 'none' }, occ(`shown|${n}`))];
      tapEvents.push(action === 'accepted'
        ? buildEvent('recommendation_accepted', uid, tapAt, rec, occ(`accepted|${n}`))
        : buildEvent('recommendation_declined', uid, tapAt, { ...rec, reason }, occ(`declined|${n}`)));
      if (tap.promoted) tapEvents.push(buildEvent('preference_learned', uid, tapAt, { reason, times_said: 2 }, occ(`learned|${reason}`)));
      stage({ events: tapEvents });
      result.steps.push(`day ${i + 1}: ${action} ${recId(n)}${tap.promoted ? ' (standing preference written)' : ''}`);
    }
    if (i === FORGET_REC_AT && forgetRecommendation(store, recId(1)) !== true) throw new Error('forget recommendation failed');
    if (i === FORGET_REC_AT) result.steps.push(`day ${i + 1}: forgot ${recId(1)}`);
    if (i === FORGET_DAY_AT && forgetFactKey(store, 'daily', FORGET_DAY) !== true) throw new Error('forget day failed');
    if (i === FORGET_DAY_AT) {
      const f = forgetDay(outStore, outbox, FORGET_DAY);
      if (!f.ok) throw new Error(`outbox: ${f.error}`);
      outbox = f.outbox;
    }
    if (i === FORGET_DAY_AT) result.steps.push(`day ${i + 1}: forgot the day ${FORGET_DAY}`);

    const midnight = `${day}T00:00:00-08:00`;
    const roll = rollDay({ store, snapshot: { ...snapshot, exportDate: midnight }, now: midnight });
    if (!roll.ok) throw new Error(`roll ${day}: ${roll.error}`);
    const planner = plannerText(store);
    if (!planner.ok) throw new Error(`planner ${day}: ${planner.error}`);
    result.planner.push(planner.text);
    const rolling = factsIn(store, 'rolling');
    stage({ snapshot, events: [buildEvent('memory_rolled', uid, midnight, {
      daily_lines: rolling.filter((f) => f.kind === 'daily').length,
      weekly_lines: rolling.filter((f) => f.kind === 'weekly').length,
      preferences: factsIn(store, 'preferences').length,
      prompt_words: planner.words,
    }, occ(`rolled|${day}`))] });
    deliver();

    if (WEEK_ENDS.includes(i)) {
      const tree = readTree(store.dir);
      result.weeks.push({
        week: WEEK_ENDS.indexOf(i) + 1,
        bytes: Object.fromEntries(Object.entries(tree).map(([f, t]) => [f, Buffer.byteLength(t)])),
        words: planner.words,
        facts: Object.keys(FILE_KINDS).reduce((n, name) => n + factsIn(store, name).length, 0),
      });
    }
  }
  result.events = events;
  result.files = readTree(store.dir);
  return result;
}

/** What must never appear in files, planner text or events: names, raw samples and routes, exact workout times. */
export function rawDataHits(who, run) {
  const snapshot = loadPersona(who);
  const texts = { files: Object.values(run.files).join('\n'), planner: run.planner.join('\n'), events: JSON.stringify(run.events) };
  const bad = [snapshot.persona.name, 'heartRate', 'latitude', 'longitude', 'route', 'samples', ...snapshot.workouts.flatMap((w) => [w.start, w.end])];
  const hits = [];
  for (const [where, text] of Object.entries(texts)) {
    for (const word of bad) if (new RegExp(`(^|[^A-Za-z])${word.replace(/[+.]/g, '\\$&')}([^A-Za-z]|$)`).test(text)) hits.push(`${where}: ${word}`);
  }
  return hits;
}
