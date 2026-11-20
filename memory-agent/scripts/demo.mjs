// Input -> output for one sample person, no network. Usage: node scripts/demo.mjs [sedentary|moderate|half_marathon]
// Files go to a temp folder that is removed at the end. Same arguments, same output.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openNodeStore } from '../src/store/node/node-store.mjs';
import { recordFeedback, forgetRecommendation } from '../src/store/index.mjs';
import { rollDay } from '../src/memory/roll.mjs';
import { plannerText } from '../src/memory/planner-text.mjs';
import { PERSONAS, loadPersona, userIdOf, runTrial } from './lib/trial-core.mjs';

const who = process.argv[2] ?? 'moderate';
if (!PERSONAS.includes(who)) { console.error(`unknown person "${who}"; use ${PERSONAS.join(', ')}`); process.exit(1); }
const snapshot = loadPersona(who);
const uid = userIdOf(who);
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tm-demo-'));
const store = openNodeStore(root, uid);
const rec = (n) => `rec_${String(n).padStart(8, '0')}`;
const show = (title, lines) => console.log(`\n== ${title}\n${lines.map((l) => `  ${l}`).join('\n')}`);
const facts = (name) => (store.read(name)?.facts ?? []).map((f) => `- ${f.text}`);

try {
  // (a) What goes in: a few lines of the health snapshot. Only counts and minutes are used; the rest is dropped.
  const lastDay = snapshot.dailySummaries.at(-1).date;
  const day = new Date(Date.parse(`${lastDay}T00:00:00Z`) + 86400000).toISOString().slice(0, 10);   // the roll at the next midnight
  show(`(a) Snapshot in: ${snapshot.persona.key}, ${snapshot.workouts.length} workouts, ${snapshot.dailySummaries.length} daily summaries`, [
    ...snapshot.workouts.slice(-3).map((w) => `${w.activityType} ${w.start.slice(0, 10)} ${Math.round(w.durationMin)} min`),
    `latest daily summary: ${lastDay} (the raw readings in it are used for the facts and then dropped)`,
  ]);

  // (b) The roll at local midnight writes the facts for the day that just ended.
  const now = `${day}T00:00:00-08:00`;
  const roll = rollDay({ store, snapshot: { ...snapshot, exportDate: now }, now });
  const written = [...(store.read('profile')?.facts ?? []), ...(store.read('rolling')?.facts ?? []).filter((f) => f.kind !== 'weekly' && !(f.kind === 'daily' && f.key !== lastDay))];
  show(`(b) rollDay at ${now}: wrote ${roll.wrote.join(' and ')} for ${roll.day}`, written.slice(0, 8).map((f) => `- ${f.text}`));

  // (c) Taps: one accept, two declines for the same reason (a standing entry), then forget one.
  const tap = (n, activity, weekday, hour, action, reason) =>
    recordFeedback(store, { recId: rec(n), activity, weekday, hour, action, reason, now: `${day}T12:00:00.000Z` });
  tap(1, 'run', 3, 7, 'declined', 'too_early');
  tap(2, 'run', 5, 6, 'declined', 'too_early');
  tap(3, 'walk', 2, 18, 'accepted');
  show('(c) Taps: decline, decline (same reason), accept. preferences now:', facts('preferences'));
  const before = facts('feedback');
  forgetRecommendation(store, rec(1));
  show(`(c) Forget ${rec(1)}. feedback before (${before.length} lines) and after:`, [...before, '-- after --', ...facts('feedback'), `preferences: ${facts('preferences').join(' ') || '(none left)'}`]);

  // (d) The text the planner gets: pinned files in full, rolling compact.
  const planner = plannerText(store);
  show(`(d) Planner text, exactly as sent: ${planner.words} words (limit 600)`, planner.text.split('\n'));

  // (e) The events a 28-day run would send (dry run: nothing leaves this machine).
  const trial = runTrial(who, fs.mkdtempSync(path.join(os.tmpdir(), 'tm-demo-run-')));
  const counts = {};
  for (const e of trial.events) counts[e.event_type] = (counts[e.event_type] ?? 0) + 1;
  show(`(e) Amplitude events for 28 days (dry run): ${trial.events.length}`, Object.entries(counts).map(([k, v]) => `${k}: ${v}`));
  const sample = trial.events.find((e) => e.event_type === 'recommendation_declined');
  show('(e) One event as sent', [JSON.stringify({ ...sample, time: new Date(sample.time).toISOString() })]);
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
