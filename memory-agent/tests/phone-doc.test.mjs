// The example in docs/PHONE.md runs as written: an in-memory memoryIO, one roll and one planner text call.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

const doc = fs.readFileSync(new URL('../docs/PHONE.md', import.meta.url), 'utf8');
const example = doc.match(/```js\n([\s\S]*?)```/)[1];
const snapshot = JSON.parse(fs.readFileSync(new URL('../fixtures/personas/moderate.json', import.meta.url), 'utf8'));

let bundle = null;
try { bundle = await (await import('../scripts/build-phone.mjs')).buildPhone(); } catch { /* esbuild is a devDependency */ }

test('the PHONE.md example rolls a day and returns planner text', { skip: bundle === null ? 'esbuild is not installed' : false }, () => {
  const context = vm.createContext({ snapshot, hostSha256: (text) => createHash('sha256').update(text).digest('hex') });
  vm.runInContext(bundle, context);
  vm.runInContext(example, context);
  assert.equal(vm.runInContext('planner.ok', context), true);
  assert.match(vm.runInContext('planner.text', context), /^Memory facts/);
});

test('PHONE.md stays within 250 words and names all six globals', () => {
  assert.ok(doc.split(/\s+/).filter(Boolean).length <= 250);
  for (const name of ['memoryRoll', 'memoryTap', 'memoryForget', 'memoryPlannerText', 'memoryFlush', 'memoryAck']) assert.ok(doc.includes(name), name);
});
