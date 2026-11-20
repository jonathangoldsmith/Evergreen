import test from 'node:test';
import assert from 'node:assert/strict';
import { deliverCalendarDemo } from '../scripts/lib/calendar-demo-delivery.mjs';
import { buildCalendarDemoAnalytics } from '../scripts/lib/calendar-demo-analytics.mjs';
import { userIdOf } from '../scripts/lib/trial-core.mjs';

const events = buildCalendarDemoAnalytics({
  labels: ['too_early', 'too_early'],
  before: { timing: [] },
  learned: { timing: [{ weekday: 6, hour: 7, direction: 'later' }] },
});
const env = { AMPLITUDE_API_KEY: 'fake-write', AMPLITUDE_SECRET_KEY: 'fake-read' };
test('delivery refuses to send without matching the earlier trial in the project', async () => {
  let calls = 0;
  await assert.rejects(deliverCalendarDemo(events, { env, request: async () => {
    calls++;
    return { ok: true, json: async () => ({ matches: [{ user_id: 'other', amplitude_id: 9 }] }) };
  } }), /nothing was sent/);
  assert.equal(calls, 1);
  await assert.rejects(deliverCalendarDemo(events, { env: {}, request: async () => assert.fail() }), /credentials missing/);
});
test('the verified test project receives just the synthetic events from this replay', async () => {
  const calls = [];
  const result = await deliverCalendarDemo(events, { env, request: async (url, options) => {
    calls.push({ url, options });
    if (calls.length === 1) return { ok: true, json: async () => ({ matches: [{ user_id: userIdOf('sedentary'), amplitude_id: 9 }] }) };
    return { status: 200 };
  } });
  assert.equal(result.sent, 3);
  assert.equal(calls[0].url.startsWith('https://amplitude.com/api/2/usersearch?'), true);
  assert.equal(calls[1].url, 'https://api2.amplitude.com/2/httpapi');
  assert.deepEqual(JSON.parse(calls[1].options.body).events, events);
  assert.ok(calls.every(c => c.options.redirect === 'error'));
});
