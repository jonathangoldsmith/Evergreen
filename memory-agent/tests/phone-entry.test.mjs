// The phone bundle runs in a bare JavaScript context (Node's vm: no require, no process, no timers), the way JavaScriptCore runs it,
// and gives exactly what the modules give when called directly.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { MemoryStore, recordFeedback, forgetRecommendation, forgetFactKey } from '../src/store/index.mjs';
import { rollDay } from '../src/memory/roll.mjs';
import { plannerText } from '../src/memory/planner-text.mjs';
import { makeMemoryIO } from './memory-io.mjs';

const USER = `usr_${'d4'.repeat(8)}`;
const snapshot = JSON.parse(fs.readFileSync(new URL('../fixtures/personas/half_marathon.json', import.meta.url), 'utf8'));
const MIDNIGHT = '2026-11-18T00:00:00-08:00';
const base = { root: '/mem', user: USER };

let bundle = null;
try { bundle = await (await import('../scripts/build-phone.mjs')).buildPhone(); } catch { /* esbuild is a devDependency; without it these tests are skipped */ }
const skip = bundle === null ? 'esbuild is not installed' : false;

function phone() {
  const mem = makeMemoryIO();
  const context = vm.createContext({});
  context.memoryIO = mem.io;
  vm.runInContext(bundle, context);
  const call = (name, args) => JSON.parse(context[name](JSON.stringify({ ...base, ...args })));
  return { mem, call, context };
}
const direct = () => {
  const mem = makeMemoryIO();
  return { mem, store: new MemoryStore('/mem', USER, { io: mem.io }) };
};

test('the bundle is one script with no imports, and sets the six global functions', { skip }, () => {
  assert.ok(!/^\s*(import|export)\s/m.test(bundle));
  const { context } = phone();
  for (const name of ['memoryRoll', 'memoryTap', 'memoryForget', 'memoryPlannerText', 'memoryFlush', 'memoryAck']) assert.equal(typeof context[name], 'function', name);
});

test('roll, tap, forget and planner text through the bundle equal the modules called directly', { skip }, () => {
  const p = phone();
  const d = direct();
  const tap = { recId: 'rec_00000001', activity: 'run', weekday: 3, hour: 7, action: 'declined', reason: 'too_early', now: '2026-11-17T12:00:00.000Z' };

  assert.deepEqual(p.call('memoryRoll', { snapshot, now: MIDNIGHT }), rollDay({ store: d.store, snapshot, now: MIDNIGHT }));
  assert.deepEqual(p.call('memoryTap', tap), recordFeedback(d.store, tap));
  assert.deepEqual(p.call('memoryPlannerText', {}), plannerText(d.store));
  assert.deepEqual(p.call('memoryForget', { what: 'recommendation', recId: 'rec_00000001' }), { ok: forgetRecommendation(d.store, 'rec_00000001') });
  assert.deepEqual(p.call('memoryForget', { what: 'day', date: '2026-11-10' }), { ok: forgetFactKey(d.store, 'daily', '2026-11-10') });
  assert.deepEqual(p.call('memoryPlannerText', {}), plannerText(d.store));
  assert.deepEqual(p.mem.dump('/mem'), d.mem.dump('/mem'));
  assert.ok(Object.keys(p.mem.dump('/mem')).length >= 2);
});

test('failures come back as { ok: false, error } and never throw', { skip }, () => {
  const { call, context } = phone();
  assert.deepEqual(call('memoryRoll', { snapshot: {}, now: MIDNIGHT }).ok, false);
  assert.deepEqual(call('memoryForget', { what: 'everything' }), { ok: false, error: 'unknown what' });
  assert.equal(JSON.parse(context.memoryTap('not json')).ok, false);
  context.memoryIO = undefined;
  assert.equal(JSON.parse(context.memoryPlannerText(JSON.stringify(base))).ok, false);
});
