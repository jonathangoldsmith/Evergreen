import { buildEvent } from '../../src/amplitude/events.mjs';

// Public synthetic aliases, isolated from every persona/trial/user ID.
// These are not hashes of actual accounts, appointments, or HealthKit data.
export const CALENDAR_DEMO_ANALYTICS_USER = 'usr_7e57ca1e00000001';
const REC_IDS = ['rec_7e57ca1e00000001', 'rec_7e57ca1e00000002'];
const OCC_IDS = ['occ_7e57ca1e00000001', 'occ_7e57ca1e00000002', 'occ_7e57ca1e00000003'];
// Fixed synthetic feedback observation times from the calendar replay, not calendar-event bounds.
const OBSERVED_AT = ['2026-11-07T17:00:00.000Z', '2026-11-14T17:00:00.000Z'];
const LABELS = new Set(['too_early', 'too_late', 'other']);

function hasSignal(stage, direction) {
  return stage.timing.some((row) => row.weekday === 6 && row.hour === 7 && row.direction === direction);
}

/**
 * Builds, but never sends, the append-only analytics history of the fixed
 * calendar demo. Forgetting removes local evidence, not events already
 * observed. The replay's calendar moves and conflicts are local only.
 */
export function buildCalendarDemoAnalytics({ labels, before, learned }) {
  if (!Array.isArray(labels) || labels.length !== 2 || labels.some((x) => !LABELS.has(x))
      || !Array.isArray(before?.timing) || !Array.isArray(learned?.timing)) {
    throw new TypeError('invalid calendar analytics replay');
  }
  const history = labels.flatMap((reason, i) => reason === 'other' ? [] : [
    buildEvent('recommendation_declined', CALENDAR_DEMO_ANALYTICS_USER, OBSERVED_AT[i], {
      rec_id: REC_IDS[i], activity: 'Elliptical', reason,
    }, OCC_IDS[i]),
  ]);
  const reason = labels[0];
  const direction = reason === 'too_early' ? 'later' : 'earlier';
  if (reason !== 'other' && labels[1] === reason && !hasSignal(before, direction) && hasSignal(learned, direction)) {
    history.push(buildEvent('preference_learned', CALENDAR_DEMO_ANALYTICS_USER, OBSERVED_AT[1], {
      reason, times_said: 2,
    }, OCC_IDS[2]));
  }
  return history;
}
