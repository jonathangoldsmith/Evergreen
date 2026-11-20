// Reconstruct the six historical console sections using the current engine.
// This is not the archived transcript. Uses only checked-in synthetic fixtures,
// an isolated temporary store and a public test salt. No network or env secrets.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openNodeStore } from '../src/store/node/node-store.mjs';
import { recordFeedback, forgetRecommendation, forgetFactType } from '../src/store/index.mjs';
import { rollDay } from '../src/memory/roll.mjs';
import { computeFacts } from '../src/facts/compute.mjs';
import { plannerText } from '../src/memory/planner-text.mjs';
import { eventsFromSnapshot } from '../src/amplitude/events.mjs';
import { nodeHmac } from '../src/amplitude/node/host.mjs';
import { PERSONAS, loadPersona, userIdOf, readTree } from './lib/trial-core.mjs';

if (process.argv.length !== 2) throw new Error('Usage: node scripts/backup-demo.mjs');
const demoHost = { hmac: nodeHmac, secret: 'backup-demo-public-test-salt' };
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tm-backup-demo-'));
const indentation = (lines) => console.log(lines.join('\n').split('\n').map((line) => `  ${line}`.trimEnd()).join('\n'));
function show(title, lines) {
  console.log(`\n=== ${title}`);
  indentation(lines);
}
const blocked = ['body.sleep', 'body.resting_hr'];

console.log('RECONSTRUCTION USING CURRENT MEMORY AGENT · all inputs synthetic · network off');
try {
  for (const who of PERSONAS) {
    const snapshot = loadPersona(who);
    const uid = userIdOf(who);
    const store = openNodeStore(root, uid);
    const latest = snapshot.dailySummaries.at(-1);
    // Use the next local midnight: the current engine correctly separates
    // complete-day comparisons from unfinished-day raw totals.
    const tomorrow = new Date(Date.parse(`${latest.date}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
    const now = `${tomorrow}T00:00:00-08:00`;
    const rolledSnapshot = { ...snapshot, exportDate: now };
    console.log(`\n################ ${who}`);
    show(`INPUT: ${snapshot.persona.name}, ${snapshot.workouts.length} workouts and ${snapshot.dailySummaries.length} daily summaries, completed-day roll = ${now}`, [
      'Last 5 synthetic workouts (activity, local start, minutes):',
      ...snapshot.workouts.slice(-5).map((w) => `${w.activityType} · ${w.start} · ${Math.round(w.durationMin)} min`),
      `Last synthetic daily summary: ${latest.date}; sleep ${Math.round(latest.sleepMinutes.totalAsleep / 60)} h, resting heart rate ${latest.restingHeartRate}`,
    ]);

    const roll = () => {
      const out = rollDay({ store, snapshot: rolledSnapshot, now });
      assert.equal(out.ok, true, out.error);
      return out;
    };
    const initialRoll = roll();
    const allFacts = computeFacts(rolledSnapshot, now);
    show('OUTPUT 1: facts for the completed day (no advice or judgment)', [
      `Rolled ${initialRoll.day}; wrote ${initialRoll.wrote.join(', ')}`,
      ...allFacts.map((fact) => `[${fact.id}] ${fact.text}`),
    ]);

    assert.equal(forgetFactType(store, 'body'), true);
    roll();
    const filtered = computeFacts(rolledSnapshot, now, { suppressed: { types: blocked } });
    const bodyAfter = ['profile', 'rolling'].flatMap((file) => store.read(file)?.facts ?? []).map((fact) => fact.text).filter((line) => /sleep|resting heart rate/i.test(line));
    assert.ok(filtered.length > 0 && !filtered.some((fact) => blocked.includes(fact.id)));
    assert.ok(!bodyAfter.some((line) => /sleep|resting heart rate/i.test(line)));
    show('OUTPUT 2: stop summarising sleep and resting heart rate; reroll the same day', [
      `Suppressed: ${blocked.join(', ')}`,
      `Computed facts: ${allFacts.length} before; ${filtered.length} after`,
      `Persisted body facts after reroll: ${bodyAfter.length}`,
      'Verified: neither suppressed fact appears in the reroll or the body file.',
    ]);

    const taps = [
      { recId: 'rec_00000001', activity: 'run', weekday: 3, hour: 7, action: 'declined', reason: 'too_early' },
      { recId: 'rec_00000002', activity: 'run', weekday: 5, hour: 6, action: 'declined', reason: 'too_early' },
    ].map((tap) => ({ ...tap, now: `${latest.date}T17:00:00.000Z` }));
    for (const tap of taps) assert.equal(recordFeedback(store, tap).written, true);
    const files = readTree(path.join(root, uid));
    const feedbackText = Object.entries(files).filter(([name]) => /(?:feedback|preferences)\/.*\.md$/.test(name))
      .flatMap(([name, contents]) => [name, contents.trimEnd()]);
    assert.ok(feedbackText.some((line) => line.includes('Declined 2 suggestions')));
    show('OUTPUT 3: recommendation taps stored as Markdown', feedbackText);

    const before = plannerText(store);
    assert.match(before.text, /Declined 2 suggestions as too early/);
    show('OUTPUT 4: exactly what the current planner would receive', before.text.split('\n'));

    assert.equal(forgetRecommendation(store, taps[0].recId), true);
    assert.equal(recordFeedback(store, taps[0]).suppressed, true);
    const after = plannerText(store);
    assert.doesNotMatch(after.text, /Declined 2 suggestions as too early/);
    assert.ok(!(store.read('feedback')?.facts ?? []).some((fact) => fact.text.includes(taps[0].recId)));
    show('OUTPUT 5: forget the first recommendation and prove replay does not restore it', [
      'The first recommendation is absent, replay is refused, and the two-decline preference is no longer in the planner.',
      ...after.text.split('\n'),
    ]);

    const { events } = eventsFromSnapshot(rolledSnapshot, uid, { host: demoHost, source: 'mock' });
    assert.ok(events.every((event) => event.user_id.startsWith('usr_7e57')));
    show('OUTPUT 6: Amplitude dry run; nothing sent', [
      `${events.length} synthetic workout events built; first two:`,
      ...events.slice(0, 2).map((e) => JSON.stringify({ ...e, time: new Date(e.time).toISOString() })),
    ]);
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
