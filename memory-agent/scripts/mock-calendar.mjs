// Writes mock calendar events into the three persona fixtures, as the last key
// `calendar: { events: [{ title, start, end }] }`. Deterministic: running it
// again gives the same bytes. The rest of each file is left as it was.
//
//   node scripts/mock-calendar.mjs
//
// Weekly events repeat from 2026-10-19 (the first fixture day) through
// 2026-11-29 (a week and a half past the export, so a planner can look ahead).
// Work events skip the Thanksgiving holiday. An event that would overlap one of
// the person's logged workouts is left out, so the calendar never claims they
// were in a meeting during a recorded run.

import fs from 'node:fs';

const FIRST = '2026-10-19';
const LAST = '2026-11-29';
const OFFSET = '-08:00'; // the fixtures use -08:00 throughout
const HOLIDAYS = new Set(['2026-11-26', '2026-11-27']);
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

// [title, days, start, end, { work }]: times are local HH:MM.
const CALENDARS = {
  // Alex: hybrid office job, regular meetings, a few personal plans.
  moderate: {
    weekly: [
      ['Team standup', WEEKDAYS, '09:30', '09:45'],
      ['Design review', ['Tue'], '14:00', '15:00'],
      ['1:1 with manager', ['Thu'], '11:00', '11:30'],
      ['Team lunch', ['Wed'], '12:00', '13:00'],
      ['Sprint demo', ['Fri'], '16:00', '17:00'],
    ],
    once: [
      ['Dentist', '2026-10-28', '08:00', '09:00'],
      ['Haircut', '2026-11-07', '13:00', '13:45'],
      ['Dinner with friends', '2026-11-14', '19:00', '22:00'],
      ['Flight to Denver', '2026-11-25', '07:00', '09:30'],
    ],
  },
  // Jordan: office job around a six-day run plan; the race is 2026-11-29.
  half_marathon: {
    weekly: [
      ['Standup', WEEKDAYS, '09:00', '09:15'],
      ['Client sync', ['Wed'], '13:00', '14:00'],
      ['Sprint planning', ['Mon'], '10:00', '11:00'],
      ['Team retro', ['Thu'], '16:00', '16:45'],
    ],
    once: [
      ['Physio', '2026-11-03', '19:30', '20:15'],
      ['Shoe fitting', '2026-11-21', '11:00', '11:30'],
      ['Race packet pickup', '2026-11-28', '10:00', '11:00'],
      ['Half marathon', '2026-11-29', '07:00', '10:00'],
    ],
  },
  // Sam: desk job, meeting-heavy days, lunch calls that eat the lunch walk.
  sedentary: {
    weekly: [
      ['Morning standup', WEEKDAYS, '09:00', '09:30'],
      ['Client check-in', ['Mon', 'Wed'], '12:00', '12:45'],
      ['Project review', ['Tue', 'Thu'], '14:00', '16:00'],
      ['Weekly report due', ['Fri'], '16:30', '17:30'],
    ],
    once: [
      ['Doctor appointment', '2026-11-05', '15:00', '15:30'],
      ['Parent-teacher conference', '2026-11-12', '19:30', '20:15'],
      // The story day: this is why the 12:00 walk didn't happen.
      ['Client call', '2026-11-20', '12:00', '12:45'],
    ],
  },
};

const at = (date, hhmm) => `${date}T${hhmm}:00${OFFSET}`;
const ms = (iso) => new Date(iso).getTime();

function dates() {
  const out = [];
  for (let d = new Date(`${FIRST}T12:00:00Z`); d <= new Date(`${LAST}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + 1)) {
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}

function events(calendar, workouts) {
  const list = [];
  for (const date of dates()) {
    const day = DAYS[new Date(`${date}T12:00:00Z`).getUTCDay()];
    for (const [title, days, start, end] of calendar.weekly) {
      if (days.includes(day) && !HOLIDAYS.has(date)) list.push({ title, start: at(date, start), end: at(date, end) });
    }
  }
  for (const [title, date, start, end] of calendar.once) list.push({ title, start: at(date, start), end: at(date, end) });
  const busy = workouts.map((w) => [ms(w.start), ms(w.end)]);
  return list
    .filter((e) => !busy.some(([s, f]) => ms(e.start) < f && s < ms(e.end)))
    .sort((a, b) => ms(a.start) - ms(b.start) || a.title.localeCompare(b.title));
}

for (const [key, calendar] of Object.entries(CALENDARS)) {
  const file = new URL(`../fixtures/personas/${key}.json`, import.meta.url);
  const text = fs.readFileSync(file, 'utf8');
  const snapshot = JSON.parse(text);
  // Drop an earlier run's calendar (always the last key), then append the new one.
  const cut = text.indexOf(',\n "calendar": ');
  const body = (cut === -1 ? text.slice(0, text.lastIndexOf('\n}')) : text.slice(0, cut));
  const value = JSON.stringify({ events: events(calendar, snapshot.workouts) }, null, 1).replaceAll('\n', '\n ');
  fs.writeFileSync(file, `${body},\n "calendar": ${value}\n}`);
  console.log(`${key}: ${JSON.parse(value).events.length} events`);
}
