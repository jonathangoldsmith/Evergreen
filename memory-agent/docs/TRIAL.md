# Four-week trial

`node scripts/trial.mjs` runs 28 daily rolls per sample person with scripted taps, a forgotten day and a forgotten recommendation. It checks that two runs are identical, planner text stays within 600 words, and no names, heart-rate data, routes or exact workout times reach files, text or events. Dry run by default.

`--send` sends them to the owner's own project (keys from the environment; test users start `usr_7e57`) and reads them back two ways: counts by day, and each test user's raw event stream by insert id. `--check` only reads back.

## Result (run 2026-11-20)

| Person | Bytes, weeks 1-4 | Planner words, weeks 1-4 | Fact lines, week 4 |
| --- | --- | --- | --- |
| sedentary | 609, 3270, 3180, 3316 | 40, 391, 417, 433 | 27 |
| moderate | 609, 3535, 3422, 3660 | 40, 414, 427, 438 | 36 |
| half_marathon | 609, 3636, 3636, 4206 | 40, 412, 421, 475 | 46 |

Four files each, largest 2356 bytes. Top planner text 475; runs identical.

| Events | Count |
| --- | --- |
| Built (incl. 2 retractions) | 161 |
| Sent | 161 |
| Read back, counts by day | 161 |
| Read back, user event stream | 161 |

New event types took over 10 minutes to show in the counts (an earlier run: 54 of 159). The export API stayed empty, so the event stream replaced it.
