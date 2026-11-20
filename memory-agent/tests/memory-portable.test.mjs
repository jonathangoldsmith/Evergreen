// src/memory (the roll and the planner text) and src/phone (the entry) must load in iOS JavaScriptCore: no Node module, no Node-only global.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { scanDir } from './helpers/core-scan.mjs';

for (const dir of ['src/memory', 'src/phone']) {
  test(`${dir} imports no Node module and uses no Node-only global`, () => {
    const url = new URL(`../${dir}/`, import.meta.url);
    assert.ok(readdirSync(url).some((f) => f.endsWith('.mjs')));
    assert.deepEqual(scanDir(url.pathname), []);
  });
}
