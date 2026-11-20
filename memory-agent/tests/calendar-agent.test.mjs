import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildCalendarDraft } from '../src/memory/calendar-agent.mjs';

const fri = (clock) => `2026-11-20T${clock}:00-08:00`;
const sat = (clock) => `2026-11-21T${clock}:00-08:00`;
const mon = (clock) => `2026-11-23T${clock}:00-08:00`;
const now = fri('11:30');
const timeZone = 'America/Los_Angeles';
const plan = [
  { id: 'fri', activity: 'Walking', start: fri('12:00'), end: fri('12:30') },
  { id: 'sat', activity: 'Elliptical', start: sat('07:30'), end: sat('07:55') },
  { id: 'mon', activity: 'Strength', start: mon('10:00'), end: mon('10:30') },
];
const fixture = JSON.parse(readFileSync(new URL('../fixtures/personas/sedentary.json', import.meta.url)));
const busy = fixture.calendar.events.map(({ start, end }) => ({ start, end }));
const timing = [{ weekday: 6, hour: 7, direction: 'later' }];
const draft = (overrides) => buildCalendarDraft({ plan, busy, now, timeZone, ...overrides });

test('actual mock calendar handles Friday conflict; a learned preference changes only Saturday', () => {
  const before = draft();
  const learned = draft({ timing });
  const forgotten = draft({ timing: [] });
  assert.deepEqual(learned, [
    { id: 'fri', activity: 'Walking', beforeStart: fri('12:00'), start: fri('12:45'), end: fri('13:15'), reason: 'busy' },
    { id: 'sat', activity: 'Elliptical', beforeStart: sat('07:30'), start: sat('08:00'), end: sat('08:25'), reason: 'preference' },
    { id: 'mon', activity: 'Strength', beforeStart: mon('10:00'), start: mon('10:00'), end: mon('10:30'), reason: 'unchanged' },
  ]);
  assert.deepEqual(forgotten, before);
  assert.deepEqual(forgotten[0], learned[0]);
  assert.equal(forgotten[1].start, sat('07:30'));
});

test('cannot collide with another planned slot, and warns when no full-duration move fits', () => {
  const original = plan[0];
  const another = { id: 'later', activity: 'Running', start: fri('12:45'), end: fri('13:15') };
  const constrained = draft({
    plan: [original, another], busy: [{ start: fri('11:30'), end: fri('12:45') }],
  });
  const moved = constrained.find(({ id }) => id === original.id);
  assert.equal(moved.start, fri('13:15'));
  assert.equal(moved.end, fri('13:45'));
  const blocked = draft({ plan: [original], busy: [{ start: fri('11:00'), end: fri('14:00') }] });
  assert.deepEqual(blocked, [{ ...original, beforeStart: original.start, reason: 'unresolved' }]);
});

test('timing uses the selected time zone even if source timestamps are UTC; past slots do not move', () => {
  const saturday = { ...plan[1], start: '2026-11-21T15:30:00Z', end: '2026-11-21T15:55:00Z' };
  const result = draft({ plan: [saturday], busy: [], timing });
  assert.equal(result[0].start, sat('08:00'));
  assert.equal(result[0].beforeStart, saturday.start);
  const past = draft({ plan: [plan[0]], now: fri('12:10') });
  assert.equal(past[0].start, fri('12:00'));
});

test('timing shift respects 06:00–22:00 and does not fill an artificial gap', () => {
  const early = { id: 'early', activity: 'Running', start: sat('06:15'), end: sat('06:35') };
  const evening = { id: 'late', activity: 'Walking', start: sat('21:30'), end: sat('22:00') };
  const bounded = draft({
    plan: [early, evening], busy: [],
    timing: [{ weekday: 6, hour: 6, direction: 'earlier' }, { weekday: 6, hour: 21, direction: 'later' }],
  });
  assert.ok(bounded.every(({ reason }) => reason === 'unchanged'));
});

test('same inputs are deterministic and caller plan is untouched', () => {
  const inputs = plan.map(Object.freeze);
  const a = draft({ plan: inputs, timing });
  const b = draft({ plan: [...inputs].reverse(), timing });
  assert.deepEqual(a, b);
  assert.equal(inputs[0].start, fri('12:00'));
});
