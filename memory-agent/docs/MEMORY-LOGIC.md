# Memory logic

How the memory turns a health snapshot and a person's taps into short facts for the planner. It writes facts only: a number and its window, never advice, judgement or prediction. Numbers in examples come from the code and are checked by a test.

Status: the fact engine, the store, the Amplitude events and the daily roll with planner text (`src/memory/`) and phone entry (`src/phone/`) are built. Preference is provisional: `docs/PREFERENCE.md`.

## Where it runs

On the phone, with no server. The app loads one bundled script (`scripts/build-phone.mjs`) in iOS JavaScriptCore and calls `memoryRoll`, `memoryTap`, `memoryForget` and `memoryPlannerText` with JSON; Swift supplies file access and hashing. The watch gets only the final recommendation; the person answers by choosing a few options.

## 1. To double-check with the recommendation side

The planner gets one block of fact sentences, rebuilt at local midnight and refreshed after a logged or missed workout; the same input gives the same text. If the memory cannot return text safely it returns an error and no text, and the planner continues without it.

Decided on our side: the text goes at the start of the prompt; ids, units and fields follow the three sample personas; the day boundary is our local midnight.

Two questions need the recommendation side's answer:

| Question | Our current answer | Needs their answer |
| --- | --- | --- |
| The person's answer | Accepted or declined (with a reason), stored at the tap | What can the person tap or say (`docs/PREFERENCE.md`)? Does an unanswered recommendation count? |
| Declines | Each tap is stored; the same reason twice gives a standing entry | Should the planner see the single decline, the standing entry, or both? |

To confirm at the end: every number the planner repeats in a recommendation appears unchanged in the memory text.

## 2. Flow

1. **Input:** a snapshot (workouts, daily summaries) with its point in time.
2. **Compute:** the engine writes facts for the day, the week and the last 28 days; the roll passes it the store's forgotten days and suppressed types. Raw values are never written.
3. **Write:** through the store only. Every write is read back. Engine sentences are stored as written (the store checks them against the engine's templates). Its thin-history, 28-day coverage and mix sentences give way to the store's `Days of data`, `Workouts logged on` and `Last 4 weeks by type`; a few long detail facts are computed but not stored, to stay near the word target.
4. **Roll:** each day facts are recomputed and replace the old ones; daily lines (28) and weekly lines (12, fully logged weeks only) are kept. The same day twice gives identical files.
5. **Output:** `plannerText` gives short bullets, at most 600 words (about 450): over that, the oldest daily and then weekly lines go, with a stated count. Or an error, no text.

Example (midnight): `On 2026-11-17: 1 counted workout (10 minutes or more) and 45.94 workout minutes.`
Example (noon): `So far today (2026-11-17): 1 counted workout (10 minutes or more) and 45.94 workout minutes, day not finished.`

No model is called anywhere; sentences come from templates.

## 3. When and what counts

- **Local midnight:** facts for the day that just ended, so the day and week are complete and comparisons mean something.
- **During the day** (after a logged or missed workout): only the raw count so far, never a comparison, rank or percentage involving today.
- A workout counts at 10 minutes or more and once it has ended; shorter ones are mentioned as not counted.
- A day without data is unknown, not zero. A comparison that needs a complete window is not written when the window has gaps.
- Under 14 days of data the only fact is `Days of data: 9 (ending 2026-11-17)`.
- Two records of one instant are one workout; conflicting records are rejected.

## 4. Facts

| Group | States |
| --- | --- |
| Volume | Counted workouts and minutes for the day, 7 days and 28 days, with logged and unlogged days |
| Against own past | The day and the week against the person's average and rank, both numbers and the ratio |
| Load | 7 days over the 28-day weekly average (effort-weighted when every workout has a score) |
| Regularity | Days since the last workout, longest stretch without one, counts per week, fixed slots (same activity, weekday, hour in 3 of 4 weeks) |
| Mix | Counts and median length by activity, start-time bands |
| Body | Sleep and resting heart rate over 7 days against the 28-day average (at least 3 readings) |
| Goal | Workouts per week against the baseline and against a target if given |

A percentage appears only for a non-zero value with a ratio between 0.1 and 10; a difference that rounds to zero keeps its direction, never "equal".

## 5. Files and reading

Five files per person: `profile`, `rolling`, `preferences`, `feedback`, `history`; each fact kind has one home file. The planner gets the pinned files and a compact `rolling` (12 weekly lines, the latest 7 daily lines, a line with the number of lines left out); `feedback` and `history` as path and count only. Sizes: `docs/PRODUCT-DIRECTION.md`.

## 6. Changing and forgetting

| Event | Result |
| --- | --- |
| A computed fact changes | Replaced by the next day's computation |
| The person changes a stated preference | Old entry moves to `history/` with the date; the count restarts at zero |
| "Forget" a stated preference | Taps, entry and history are deleted; the same recommendation id is ignored afterwards |
| "Stop summarising X" | Facts of that type and any fact restating them are deleted and not written again until restored |
| "Forget everything computed" | The derived files are deleted and not written again until restored |

After forgetting only hashes, type names and a tombstone with a forgotten day's date remain. Amplitude keeps the original events of a forgotten day, retracted so they stop counting. The day is left out of every later roll and total. "Forget for today" is not stored.

## 7. Failures

A write that cannot be read back fails and the old content stays. A half-finished change is finished or rolled back on the next read; until then no text is returned. An invalid file is refused, not repaired. Late data does not rewrite the past.

## 8. Amplitude

A record and measuring tool, never in the request path, with no raw health data or names: `docs/AMPLITUDE.md`.

## 9. Open points

- Preference: what the person can say or tap.
- No explicit consent step for health facts yet.
- Thresholds (10 minutes, 14 days, 3 readings, 3 of 4 weeks) are our choices.
