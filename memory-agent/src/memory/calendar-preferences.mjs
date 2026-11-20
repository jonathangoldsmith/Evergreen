import { recover } from '../store/index.mjs';
import { SHOWN_TAPS, tapsOf } from '../store/derive.mjs';

export function calendarTimingPreferences(store) {
  if (!recover(store).ok) return { ok: false, error: 'memory unavailable' };
  const preferences = store.read('preferences');
  const feedback = store.read('feedback');
  const timing = [];
  for (const [reason, direction] of [['too_early', 'later'], ['too_late', 'earlier']]) {
    if (!preferences?.facts.some((fact) => fact.kind === 'standing' && fact.reason === reason)) continue;
    const slots = new Set();
    for (const { weekday, hour } of tapsOf(feedback, reason).slice(-SHOWN_TAPS)) {
      const key = weekday + ':' + hour;
      if (slots.has(key)) continue;
      slots.add(key);
      timing.push({ weekday, hour, direction });
    }
  }
  return { ok: true, timing };
}
