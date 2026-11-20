// The demo and the dry-run trial run end to end. No network: --send is never passed and the Amplitude keys are removed.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { runTrial, activeWorkoutsOn, FORGET_DAY } from '../scripts/lib/trial-core.mjs';
import { makeTmp } from './helpers/tmp.mjs';

const env = { ...process.env, AMPLITUDE_API_KEY: '', AMPLITUDE_SECRET_KEY: '' };
const run = (script, ...args) => spawnSync(process.execPath, [new URL(`../scripts/${script}`, import.meta.url).pathname, ...args], { encoding: 'utf8', env });

test('demo.mjs exits 0 and prints the five sections in under 120 lines', () => {
  const r = run('demo.mjs');
  assert.equal(r.status, 0, r.stderr);
  for (const s of ['(a) Snapshot in', '(b) rollDay', '(c) Taps', '(c) Forget', '(d) Planner text', '(e) Amplitude events']) assert.ok(r.stdout.includes(s), s);
  assert.ok(r.stdout.split('\n').length < 120);
  assert.equal(run('demo.mjs').stdout, r.stdout, 'same output twice');
});

test('demo.mjs prints no raw heart-rate numbers from the fixture', () => {
  for (const who of ['sedentary', 'moderate', 'half_marathon']) {
    const snap = JSON.parse(fs.readFileSync(new URL(`../fixtures/personas/${who}.json`, import.meta.url), 'utf8'));
    const out = run('demo.mjs', who).stdout;
    assert.ok(!/heart rate\s*\d/i.test(out) && !/heartRate/.test(out));
    // every raw value (resting rate per day, workout average, minimum, maximum) must be absent as a standalone number next to "heart"
    const raw = new Set([...snap.dailySummaries.map((d) => d.restingHeartRate), ...snap.workouts.flatMap((w) => [w.heartRate?.avg, w.heartRate?.min, w.heartRate?.max])].filter(Boolean));
    for (const n of raw) assert.ok(!new RegExp(`(heart|rate|bpm)[^\\n]{0,20}\\b${n}\\b`, 'i').test(out), `${who}: ${n}`);
  }
});

test('demo.mjs rejects an unknown person', () => {
  assert.notEqual(run('demo.mjs', 'nobody').status, 0);
});

test('trial.mjs dry run exits 0, sends nothing and says so', () => {
  const r = run('trial.mjs');
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /Dry run: nothing was sent/);
  assert.match(r.stdout, /Checks passed/);
});

test('trial.mjs --send without keys stops and names the missing variable', () => {
  const r = run('trial.mjs', '--send');
  assert.notEqual(r.status, 0);
  assert.match(r.stdout, /Missing environment variable: AMPLITUDE_API_KEY, AMPLITUDE_SECRET_KEY/);
});

test('a trial run keeps files small, planner text under 600 words, and every event under a test user', () => {
  const t = runTrial('half_marathon', makeTmp());
  assert.equal(t.weeks.length, 4);
  for (const w of t.weeks) assert.ok(w.words <= 600);
  assert.ok(t.events.every((e) => e.user_id.startsWith('usr_7e57')));
  assert.equal(new Set(t.events.map((e) => e.insert_id)).size, t.events.length);
});

test('the forgotten day has no active workout event, and its delivered workouts were retracted', () => {
  const t = runTrial('moderate', makeTmp());
  const onDay = t.events.filter((e) => e.event_type === 'workout_completed' && e.event_properties.local_date === FORGET_DAY);
  assert.ok(onDay.length >= 1, 'the persona has a workout on that day, delivered before it was forgotten');
  assert.equal(activeWorkoutsOn(t.events, FORGET_DAY).length, 0);
  assert.equal(t.events.filter((e) => e.event_type === 'workout_retracted').length, onDay.length);
});
