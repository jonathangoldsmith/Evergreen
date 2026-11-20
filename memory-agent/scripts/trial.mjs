// The four-week trial over the three sample personas. Usage: node scripts/trial.mjs [--send | --check] [--wait-minutes N]
// Default is a dry run: no network. With --send the events go to the owner's own Amplitude project (keys only from the
// environment: AMPLITUDE_API_KEY to send, AMPLITUDE_SECRET_KEY to read back) and are read back two independent ways.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runTrial, rawDataHits, activeWorkoutsOn, PERSONAS, TEST_USER_PREFIX, FORGET_DAY } from './lib/trial-core.mjs';
import { MAX_WORDS } from '../src/memory/planner-text.mjs';

const args = process.argv.slice(2);
const CHECK = args.includes('--check');           // read back only, no sending (for use after Amplitude's lag)
const SEND = args.includes('--send') || CHECK;
const WAIT_MIN = Number(args[args.indexOf('--wait-minutes') + 1]) || 10;
const out = (s = '') => console.log(s);

// 1. The dry run: each persona twice, so determinism can be checked.
const runOnce = (who) => runTrial(who, fs.mkdtempSync(path.join(os.tmpdir(), 'tm-trial-')));
const runs = PERSONAS.map((who) => {
  const a = runOnce(who);
  const b = runOnce(who);
  return { ...a, deterministic: JSON.stringify(a) === JSON.stringify(b), raw: rawDataHits(who, a) };
});

out('Trial: 28 daily rolls per person, scripted taps, one forgotten day and one forgotten recommendation\n');
for (const r of runs) {
  out(`${r.who} (${r.uid})`);
  const files = Object.keys(r.weeks.at(-1).bytes);
  out(`  files: ${files.length}  (${files.join(', ')})`);
  out('  bytes per file at week 1 / 2 / 3 / 4:');
  for (const f of files) out(`    ${f.padEnd(30)} ${r.weeks.map((w) => String(w.bytes[f] ?? '-').padStart(6)).join(' ')}`);
  out(`  total bytes     ${r.weeks.map((w) => String(Object.values(w.bytes).reduce((a, b) => a + b, 0)).padStart(6)).join(' ')}`);
  out(`  planner words   ${r.weeks.map((w) => String(w.words).padStart(6)).join(' ')}   (max over all 28 days: ${Math.max(...r.planner.map((t) => t.split(/\s+/).filter(Boolean).length))})`);
  out(`  fact lines      ${r.weeks.map((w) => String(w.facts).padStart(6)).join(' ')}`);
  out(`  deterministic: ${r.deterministic ? 'yes' : 'NO'}   raw data or names found: ${r.raw.length ? r.raw.join('; ') : 'none'}`);
}
const events = runs.flatMap((r) => r.events);
const ids = new Set(events.map((e) => e.insert_id));
const byType = {};
for (const e of events) byType[e.event_type] = (byType[e.event_type] ?? 0) + 1;
out(`\nForgotten day ${FORGET_DAY}: ${runs.map((r) => `${r.who} ${r.events.filter((e) => e.event_type === 'workout_retracted').length} retracted, ${activeWorkoutsOn(r.events, FORGET_DAY).length} active`).join('; ')}`);
out(`Events built: ${events.length}, distinct insert ids: ${ids.size}`);
out(`  ${Object.entries(byType).map(([k, v]) => `${k} ${v}`).join(', ')}`);

const maxWords = Math.max(...runs.flatMap((r) => r.planner.map((t) => t.split(/\s+/).filter(Boolean).length)));
const problems = [
  ...(maxWords > MAX_WORDS ? [`planner text over ${MAX_WORDS} words`] : []),
  ...runs.filter((r) => !r.deterministic).map((r) => `${r.who} is not deterministic`),
  ...runs.filter((r) => r.raw.length).map((r) => `${r.who} leaks raw data`),
  ...runs.filter((r) => activeWorkoutsOn(r.events, FORGET_DAY).length).map((r) => `${r.who} still has an active workout on the forgotten day`),
  ...(ids.size !== events.length ? ['duplicate insert ids'] : []),
  ...(events.some((e) => !e.user_id.startsWith(TEST_USER_PREFIX)) ? ['a user id without the test prefix'] : []),
];

// 2. Send and read back (only with --send).
async function sendAndVerify() {
  const need = ['AMPLITUDE_API_KEY', 'AMPLITUDE_SECRET_KEY'].filter((k) => !process.env[k]);
  if (need.length) { out(`\nNot sent. Missing environment variable: ${need.join(', ')}`); return false; }
  (await import('node:dns')).setDefaultResultOrder('ipv4first');      // IPv6 can hang on some networks
  const { send } = await import('../src/amplitude/node/sender.mjs');
  const auth = `Basic ${Buffer.from(`${process.env.AMPLITUDE_API_KEY}:${process.env.AMPLITUDE_SECRET_KEY}`).toString('base64')}`;
  const types = Object.keys(byType);
  const ymd = (ms) => new Date(ms).toISOString().slice(0, 10).replace(/-/g, '');
  // Segmentation counts by event time, so its window is the span of the trial's own events plus a day each side.
  const span = [Math.min(...events.map((e) => e.time)) - 86400000, Math.max(...events.map((e) => e.time)) + 86400000];

  // Read-back 1: the dashboard REST API, event counts by day for each type, summed. A type Amplitude has not indexed yet
  // answers 400 and counts as 0, so a short count right after sending means lag, not loss.
  const segmentation = async () => {
    let total = 0;
    for (const t of types) {
      const url = `https://amplitude.com/api/2/events/segmentation?e=${encodeURIComponent(JSON.stringify({ event_type: t }))}&m=totals&i=1&start=${ymd(span[0])}&end=${ymd(span[1])}`;
      const res = await fetch(url, { headers: { authorization: auth } });
      if (res.status === 400) continue;
      if (res.status !== 200) throw new Error(`segmentation answered ${res.status}`);
      total += ((await res.json()).data.series[0] ?? []).reduce((a, b) => a + b, 0);
    }
    return total;
  };
  // Read-back 2: the user activity API, the raw event stream of each test user, counting distinct insert ids that match ours.
  // The export API runs hours behind, so the user activity API is used: it answers within minutes.
  const activity = async () => {
    const found = new Set();
    for (const { uid } of runs) {
      const find = await fetch(`https://amplitude.com/api/2/usersearch?user=${uid}`, { headers: { authorization: auth } });
      if (find.status !== 200) throw new Error(`user search answered ${find.status}`);
      const amplitudeId = (await find.json()).matches?.[0]?.amplitude_id;
      if (!amplitudeId) continue;                                                      // no such user yet
      const res = await fetch(`https://amplitude.com/api/2/useractivity?user=${amplitudeId}&limit=1000`, { headers: { authorization: auth } });
      if (res.status !== 200) throw new Error(`user activity answered ${res.status}`);
      for (const e of (await res.json()).events ?? []) found.add(e.$insert_id);
    }
    return found;
  };

  if (!CHECK) {
    const res = await send(events, { fetchImpl: fetch, env: process.env });
    out(`\nSent: ${res.sent} of ${events.length} events in ${res.batches} batch(es)${res.failed.length ? `; failed: ${res.failed.map((f) => f.error).join('; ')}` : ''}`);
    if (res.sent !== events.length) return false;
  }
  let seg = 0; let exp = new Set();
  for (let waited = 0; ; waited += 60) {
    [seg, exp] = [await segmentation(), await activity()];
    const expMatch = [...ids].filter((id) => exp.has(id)).length;
    out(`  read-back after ${waited}s: segmentation ${seg}, user activity ${expMatch} of ${ids.size} insert ids`);
    if (seg === events.length && expMatch === ids.size) break;
    if (waited >= WAIT_MIN * 60) break;
    await new Promise((r) => setTimeout(r, 60000));
  }
  const expMatch = [...ids].filter((id) => exp.has(id)).length;
  out(`Sent ${events.length}; segmentation read-back ${seg}; user-activity read-back ${expMatch}.`);
  const good = seg === events.length && expMatch === ids.size;
  out(good ? 'Both read-backs match the number sent.' : 'READ-BACKS DO NOT BOTH MATCH the number sent (see lines above).');
  return good;
}

let ok = problems.length === 0;
if (problems.length) out(`\nPROBLEMS: ${problems.join('; ')}`);
else out('\nChecks passed: planner text within the limit, deterministic, no raw data, no names.');
if (SEND && ok) ok = await sendAndVerify().catch((e) => { out(`\nSend or read-back failed: ${e.message}`); return false; });
else if (!SEND) out('Dry run: nothing was sent. Add --send to send and read back.');
process.exit(ok ? 0 : 1);
