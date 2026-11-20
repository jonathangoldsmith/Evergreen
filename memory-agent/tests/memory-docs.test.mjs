// The examples in docs/MEMORY-LOGIC.md come from the code: each quoted line must be what the roll and the planner text produce.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { MemoryStore } from '../src/store/index.mjs';
import { rollDay } from '../src/memory/roll.mjs';
import { plannerText } from '../src/memory/planner-text.mjs';
import { makeMemoryIO } from './memory-io.mjs';

const DOC = fs.readFileSync(new URL('../docs/MEMORY-LOGIC.md', import.meta.url), 'utf8');
const snapshot = JSON.parse(fs.readFileSync(new URL('../fixtures/personas/moderate.json', import.meta.url), 'utf8'));
const fresh = () => new MemoryStore('/mem', `usr_${'e5'.repeat(8)}`, { io: makeMemoryIO().io });
const midnight = '2026-11-18T00:00:00-08:00';
const noon = '2026-11-17T12:00:00-08:00';

test('the daily-roll examples in docs/MEMORY-LOGIC.md are what the code writes', () => {
  const store = fresh();
  assert.equal(rollDay({ store, snapshot: { ...snapshot, exportDate: midnight }, now: midnight }).ok, true);
  const rolled = plannerText(store).text;
  const quoted = [...DOC.matchAll(/^Example \((midnight|noon)\): `(.+)`$/gm)].map((m) => [m[1], m[2]]);
  assert.deepEqual(quoted.map((q) => q[0]), ['midnight', 'noon']);
  assert.ok(rolled.split('\n').includes(`- ${quoted[0][1]}`), quoted[0][1]);
  const day = fresh();
  assert.equal(rollDay({ store: day, snapshot: { ...snapshot, exportDate: noon }, now: noon }).ok, true);
  assert.ok(day.view('rolling').split('\n').includes(`- ${quoted[1][1]}`), quoted[1][1]);
});

test('docs/MEMORY-LOGIC.md stays within 1150 words', () => {
  assert.ok(DOC.split(/\s+/).filter(Boolean).length <= 1150);
});
