import { recordFeedback, forgetRecommendation } from '../../src/store/index.mjs';
import { calendarTimingPreferences } from '../../src/memory/calendar-preferences.mjs';
import { buildCalendarDraft } from '../../src/memory/calendar-agent.mjs';

// Same synthetic workout windows as Sam's project plan. The Friday conflict
// is taken from the existing sedentary fixture, not inserted by this replay.
const plan = Object.freeze([
  { id: 'fri-walk', activity: 'Lunch walk', start: '2026-11-20T12:00:00-08:00', end: '2026-11-20T12:30:00-08:00' },
  { id: 'sat-elliptical', activity: 'Elliptical', start: '2026-11-21T07:30:00-08:00', end: '2026-11-21T07:55:00-08:00' },
  { id: 'mon-strength', activity: 'Strength', start: '2026-11-23T10:00:00-08:00', end: '2026-11-23T10:30:00-08:00' },
]);
const ids = ['rec_00000201', 'rec_00000202'];
const times = ['2026-11-07T17:00:00.000Z', '2026-11-14T17:00:00.000Z'];

export function runCalendarDemo({ store, snapshot, labels }) {
  if (!Array.isArray(labels) || labels.length !== 2 || labels.some(x => !['too_early', 'too_late', 'other'].includes(x))) {
    throw new TypeError('Invalid demo feedback labels');
  }
  const busy = snapshot.calendar.events.map(({ start, end }) => ({ start, end }));
  const draft = () => {
    const evidence = calendarTimingPreferences(store);
    if (!evidence.ok) throw new Error('Calendar timing memory is unavailable');
    return {
      timing: evidence.timing,
      rows: buildCalendarDraft({ plan, busy, timing: evidence.timing, now: '2026-11-20T11:30:00-08:00', timeZone: 'America/Los_Angeles' }),
    };
  };
  const before = draft();
  for (const [i, label] of labels.entries()) {
    const tap = recordFeedback(store, {
      action: 'declined', recId: ids[i], now: times[i], activity: 'elliptical', weekday: 6, hour: 7,
      ...(label === 'other' ? {} : { reason: label }),
    });
    if (!tap.written) throw new Error('Could not write synthetic feedback');
  }
  const learned = draft();
  if (!forgetRecommendation(store, ids[0])) throw new Error('Could not forget synthetic feedback');
  return { before, learned, afterForget: draft() };
}
