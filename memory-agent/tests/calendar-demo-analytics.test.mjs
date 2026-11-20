import test from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeEvent } from '../src/amplitude/events.mjs';
import { buildCalendarDemoAnalytics, CALENDAR_DEMO_ANALYTICS_USER } from '../scripts/lib/calendar-demo-analytics.mjs';

const empty = { timing: [] };
const learned = { timing: [{ weekday: 6, hour: 7, direction: 'later' }] };
const input = { labels: ['too_early', 'too_early'], before: empty, learned, afterForget: empty };

test('validates existing schema, isolates IDs, and exports only fixed synthetic props', () => {
  const events = buildCalendarDemoAnalytics({
    ...input, before: { ...empty, rows: [{ activity: 'Private title', start: 'ignored' }] }, rawText: 'ignored',
  });
  assert.deepEqual(events.map((event) => sanitizeEvent(event)), events);
  assert.deepEqual(events.map((event) => event.event_type),
    ['recommendation_declined', 'recommendation_declined', 'preference_learned']);
  assert.ok(events.every((event) => event.user_id === CALENDAR_DEMO_ANALYTICS_USER && /^usr_7e57/.test(event.user_id)));
  assert.equal(new Set(events.map((event) => event.insert_id)).size, 3);
  assert.deepEqual(events[0].event_properties, {
    rec_id: 'rec_7e57ca1e00000001', activity: 'Elliptical', reason: 'too_early',
  });
  assert.deepEqual(events[2].event_properties, { reason: 'too_early', times_said: 2 });
  const json = JSON.stringify(events);
  for (const forbidden of ['Private title', 'ignored', 'weekday', 'hour', 'beforeStart', 'start', 'health']) {
    assert.ok(!json.includes(forbidden), forbidden);
  }
});

test('forget changes no prior analytics and identical replays dedupe with stable insert IDs', () => {
  const original = buildCalendarDemoAnalytics(input);
  assert.deepEqual(buildCalendarDemoAnalytics({ ...input, afterForget: learned }), original);
  assert.deepEqual(buildCalendarDemoAnalytics(input), original);
});

test('no preference event if not newly learned and no decline for an unclassified label', () => {
  assert.equal(buildCalendarDemoAnalytics({ ...input, before: learned }).length, 2);
  assert.equal(buildCalendarDemoAnalytics({ ...input, learned: empty }).length, 2);
  assert.deepEqual(buildCalendarDemoAnalytics({ ...input, labels: ['other', 'too_early'] }).map((e) => e.event_type),
    ['recommendation_declined']);
  assert.deepEqual(buildCalendarDemoAnalytics({ ...input, labels: ['other', 'other'] }), []);
  assert.throws(() => buildCalendarDemoAnalytics({ ...input, labels: ['too_early', 'unapproved'] }), TypeError);
});
