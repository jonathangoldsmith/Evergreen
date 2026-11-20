# Amplitude

Amplitude is a record and a measuring tool: write only, never in the request path, in the owner's project, keys outside the repo.

On the phone (iOS JavaScriptCore) the core in `src/amplitude/` builds and validates events and keeps correction state. It never sends: the app hands events to the Amplitude iOS SDK, which queues them and deduplicates by `insert_id`. The core imports no `node:` module or Node global (tested); the host injects `hmac(secret, data)`, the secret (16+ characters) and storage. `src/amplitude/node/` (fetch sender, file store, Node crypto) is for tests and demo. The phone keeps the outbox in the memory store's `io` (`io-store.mjs`); the host adds `memoryIO.hmac` and `memoryIO.idSecret`. Roll, tap and forgetting a day stage events or retractions; `memoryFlush` lists them, `memoryAck` records delivery.

## Events

One bad property rejects the event; unknown properties are dropped; sending re-checks. Allowed values: reason (too_early, too_late, too_long, too_hard, not_today), outcome (completed, not_completed), framing (none, neutral, baseline, streak, comeback, rank), minutes (0 to 1440, rounded half away from zero to 2 decimals), activity from a fixed list plus aliases, else `Other`. User id, `rec_id`, occurrence id and `supersedes` are opaque `usr_`, `rec_` or `occ_` plus 8 to 32 hex, made by `opaqueId` (HMAC-SHA256).

| Event | Required properties |
| --- | --- |
| `workout_completed` | activity, minutes, weekday, hour, occurrence_id, local_date, local_week, utc_offset_minutes (+ rec_id, supersedes optional) |
| `workout_retracted` | occurrence_id, utc_offset_minutes |
| `workout_missed` | activity, planned_weekday, planned_hour |
| `recommendation_shown` | rec_id, activity, weekday, hour, framing |
| `recommendation_accepted` | rec_id, activity |
| `recommendation_declined` | rec_id, activity, reason |
| `recommendation_outcome` | rec_id, outcome |
| `comeback_accepted` | rec_id, minutes |
| `memory_rolled` | daily_lines, weekly_lines, preferences, prompt_words |
| `preference_learned` | reason, times_said |

`insert_id` is sha256(user id, event type, occurrence id). Workout `time` is the start of the local hour, never the exact start, and agrees with `local_date`, `hour` and `utc_offset_minutes`; `local_week` is its Monday.

## Workouts and corrections

`eventsFromSnapshot(snapshot, userId, {host, sent})` needs a `workouts` array; each workout needs a `durationMin` from 0 to 1440, a start with Z or an offset, and a `source` (mock, phone, watch, manual) from the workout or the option, else the snapshot is rejected. A workout's key is the HMAC of the user and its `id` (`wk_` plus hex) or start instant; identical records at one start are one workout, different ones need ids.

- New key: `workout_completed`, version 1; same content: nothing; changed end, minutes, activity or time zone: version + 1, `supersedes` the previous occurrence.
- Now under 10 minutes: `workout_retracted`. Absent: retracted only inside the snapshot's explicit `coverage {from, to}`; without it nothing is retracted. Without `id`, a start change is delete-and-add.
- `forgetDay(store, outbox, localDate)`: for workouts on that day, now or earlier, drops pending events and retracts every occurrence (a pending one may be delivered already); keeps the date and a tombstone so snapshots ignore the day and its workouts until `restoreForgotten`. A retraction only stops counting: Amplitude keeps the original event.
- Active: not named by any `supersedes` or `workout_retracted`; apply before counting.

## Delivery loop

The outbox holds the adopted state and unsent events, saved together by the host's store (`save`, `load`, `sync`). The file store writes `<root>/<usr_id>/outbox.json` atomically, first removing abandoned temp files; the core accepts allowlisted fields and that user's events only.

1. Stage: `commitSnapshot` saves the next state and events, then `load()` must return the same outbox, else `unrecovered`.
2. Hand over: `deliverOutbox` gives the events to the SDK (tests: a fetch sender).
3. Acknowledge: remove accepted events, save again.
4. After a restart: `loadOutbox`, hand over what it lists, then stage. Staging is refused while events are unsent.

| Failure | Returned outbox | Next step |
| --- | --- | --- |
| Save fails or the rename throws | What is on disk, or the outbox the call started with | Retry |
| Final read or read-back fails, or the store throws | `unrecovered` | `loadOutbox`, adopt it |
| Different content on disk | What is on disk | Hand over its events first |
| Folder sync fails | Intended outbox marked `unsynced` | `syncOutbox` or `loadOutbox`; no delivery until then |
| Acknowledgement save fails | The original outbox (events listed), or the row above | Retry; same `insert_id`s |

## Queries

Grain: one `recommendation_shown` and at most one `recommendation_outcome` per `user_id` and `rec_id`; deduplicate each side (first by time) before joining. Group weeks by `local_week`.

- Acceptance rate by activity, hour and framing: accepted over shown.
- Completion rate: completed over (completed plus not_completed) from `recommendation_outcome` only; else none.
- Workouts per week against the 4-week baseline: active occurrences, four calendar weeks, empty weeks zero (4, 0, 0, 0 is 1).
- Funnel: shown, accepted, completed.
