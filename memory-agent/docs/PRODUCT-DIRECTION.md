# Product direction

A memory layer for a fitness agent. Each day it turns a person's health snapshot and what they said about recommendations into short **facts**: a number with its window, never advice, judgement or prediction. The recommendation side reads the facts. How the memory works is in `docs/MEMORY-LOGIC.md`.

Built for a four-person hackathon app and on the three sample personas in `fixtures/personas/`; it does not extend beyond them. It runs on the phone, in iOS JavaScriptCore, with no server; the phone builds the prompt and the watch receives only the final recommendation. Preference is provisional: `docs/PREFERENCE.md`.

## Examples

- "54.4 workout minutes on 2026-11-17, ratio 1.18 to the daily average of 46.16 minutes over the previous 28 days (28 logged days, 17.9% above)."
- "Longest stretch of logged days without a counted workout in the last 28 days: 4 days."
- "Declined 2 suggestions as too early (Wed 07:00; Fri 06:00)."

## Size and loading

| Topic | Choice |
| --- | --- |
| Files per person | `profile`, `rolling`, `preferences`, `feedback`, `history` |
| Size | `rolling` at most 28 daily and 12 weekly lines; `feedback` keeps the latest 30 taps and folds older ones into counts; about 50 KB per person per year |
| Read on every request | `profile`, `preferences`, and a compact `rolling`: 12 weekly lines, the latest 7 daily lines, and the number of daily lines |
| Read only when needed | `feedback` (path and count), the full daily lines |
| Never read by default | `history` (path and count) |
| Text for the planner | About 450 words (about 650 tokens), at most 600; anything folded away is counted, never dropped silently |
| When written | `rolling` and `profile` at local midnight and after a logged or missed workout; `feedback` and `preferences` at the tap |
| Cost | No model call anywhere; sentences come from templates; the text changes once a day, so prompt caching can reuse it |

## Rules

1. Facts only: no advice, judgement or prediction. A lint checks every line.
2. Every number is exact for its window and can be recomputed from the input.
3. Raw health data is used and dropped; it never reaches memory or output. Events carry only activity, minutes, weekday, hour and reason: no heart rate, samples, routes or names.
4. Every write is read back before it counts.
5. Running a day twice gives the same files.
6. A user-stated fact the user changes moves to `history/`; a computed fact is replaced by the next day's computation. "Forget" deletes and the fact is never output again.
7. One folder per person; no path leaves it.
8. Tests make no network call; keys come from the environment only.
9. English only.
10. Scope: one app on one phone for one user (the watch only receives the final recommendation). Hostile local processes, hand-edited files and races between a check and a write are out of scope; correctness, facts-only output, no raw data in output, no heart rate, samples, routes or names in events, forgetting through normal use and crash safety are in.

## Amplitude

A record and a measuring tool, never part of answering a request. Owner's own project; keys stay outside the repository. See `docs/AMPLITUDE.md`.
