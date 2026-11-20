import { parseTimestamp } from '../contract/time.mjs';

const MINUTE = 60_000;
const STEP = 15 * MINUTE;
const EARLIER = 60 * MINUTE;
const LATER = 90 * MINUTE;
const WEEKDAY = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

function readTime(value) {
  const parsed = parseTimestamp(value);
  if (!parsed) throw new TypeError('invalid calendar timestamp');
  return parsed.ms;
}

function bounds(row) {
  const start = readTime(row.start);
  const end = readTime(row.end);
  if (end <= start) throw new RangeError('calendar interval must have positive duration');
  return { start, end };
}

function clock(timeZone) {
  const dateFormat = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', timeZoneName: 'longOffset',
  });
  return (ms) => {
    const p = Object.fromEntries(dateFormat.formatToParts(ms).map(({ type, value }) => [type, value]));
    return {
      date: `${p.year}-${p.month}-${p.day}`, weekday: WEEKDAY[p.weekday], hour: Number(p.hour),
      minute: Number(p.minute), second: Number(p.second),
      offset: p.timeZoneName === 'GMT' ? 'Z' : p.timeZoneName.slice(3),
    };
  };
}

const overlaps = (a, b) => a.start < b.end && a.end > b.start;
const two = (n) => String(n).padStart(2, '0');
const toLocal = (parts, ms) => {
  const { date, hour, minute, second, offset } = parts;
  const fraction = new Date(ms).getUTCMilliseconds();
  const decimal = fraction ? `.${String(fraction).padStart(3, '0')}` : '';
  return `${date}T${two(hour)}:${two(minute)}:${two(second)}${decimal}${offset}`;
};

/**
 * Locally build a workout-calendar preview on already reserved slots. The caller
 * supplies only busy interval bounds and explicit timing signals. No mutations
 * to caller data, writes, provider calls, or use of event titles.
 */
export function buildCalendarDraft({ plan, busy = [], timing = [], now, timeZone }) {
  const nowMs = readTime(now);
  const local = clock(timeZone);
  const busyBounds = busy.map(bounds).sort((a, b) => a.start - b.start || a.end - b.end);
  const rows = plan.map((item) => ({ item, ...bounds(item) }))
    .sort((a, b) => a.start - b.start || (a.item.id < b.item.id ? -1 : a.item.id > b.item.id ? 1 : 0));
  const ids = new Set(rows.map(({ item }) => item.id));
  if (ids.size !== rows.length) throw new TypeError('calendar plan has duplicate ids');

  const matching = (t) => timing.filter(({ weekday, hour }) => weekday === t.weekday && hour === t.hour);
  const output = [];
  for (const row of rows) {
    const { item, start, end } = row;
    const date = local(start);
    const duration = end - start;
    const affected = busyBounds.find((block) => overlaps(row, block));
    const reserved = [...busyBounds, ...rows.filter((other) => other !== row)];
    const free = (candidate) => {
      if (candidate <= nowMs || candidate < start - EARLIER || candidate > start + LATER) return false;
      const candidateEnd = candidate + duration;
      const from = local(candidate);
      const to = local(candidateEnd);
      return from.date === date.date && to.date === date.date && from.hour >= 6
        && (to.hour < 22 || (to.hour === 22 && !to.minute && !to.second && candidateEnd % 1000 === 0))
        && !reserved.some((block) => overlaps({ start: candidate, end: candidateEnd }, block));
    };
    let proposed;
    let reason = 'unchanged';
    if (start > nowMs && affected) {
      // Prefer the first full-duration slot immediately after the overlapping
      // event, following a chain of adjacent reservations as needed.
      let after = affected.end;
      for (;;) {
        const blockers = reserved.filter((block) => overlaps({ start: after, end: after + duration }, block));
        if (!blockers.length || after > start + LATER) break;
        after = Math.max(...blockers.map((block) => block.end));
      }
      if (free(after)) proposed = after;
      for (let delta = STEP; proposed === undefined && delta <= LATER; delta += STEP) {
        if (delta <= EARLIER && free(start - delta)) proposed = start - delta;
        else if (free(start + delta)) proposed = start + delta;
      }
      reason = proposed === undefined ? 'unresolved' : 'busy';
    } else if (start > nowMs) {
      const directions = new Set(matching(date).map(({ direction }) => direction));
      const direction = directions.size === 1 ? [...directions][0] : undefined;
      if (direction === 'earlier' || direction === 'later') {
        const sign = direction === 'earlier' ? -1 : 1;
        const limit = direction === 'earlier' ? EARLIER : LATER;
        for (let delta = STEP; delta <= limit; delta += STEP) {
          const candidate = start + sign * delta;
          if (!matching(local(candidate)).length && free(candidate)) {
            proposed = candidate;
            reason = 'preference';
            break;
          }
        }
      }
    } else if (affected) {
      reason = 'unresolved';
    }
    if (proposed !== undefined) {
      row.start = proposed;
      row.end = proposed + duration;
    }
    output.push({
      id: item.id, activity: item.activity, beforeStart: item.start,
      start: proposed === undefined ? item.start : toLocal(local(row.start), row.start),
      end: proposed === undefined ? item.end : toLocal(local(row.end), row.end),
      reason,
    });
  }
  return output.sort((a, b) => readTime(a.start) - readTime(b.start) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}
