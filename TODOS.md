# TODOS

## Shopping beat follow-ups (from /plan-eng-review, 2026-11-20)

### Python purchase rules in the harness's decide()
- **What:** Mirror the shoes and day-pass rules from `StandInAgent+Purchases.swift` in the harness's `decide()`, and have `/tick` return purchase actions.
- **Why:** Restores eng review decision D3 (the harness owns every rule) for purchases. D1 kept them Swift-only for the hackathon.
- **Pros:** One server-side brain; the phone goes back to only rendering.
- **Cons:** Two copies of each rule need shared snapshot→actions fixtures (contract/fixtures, D10) to stay in sync.
- **Context:** On demo day the harness only serves `POST /evidence` (Senso search, 2.5 s cap, cached fallback). Start from the Swift rules and the PurchaseTests cases.
- **Depends on / blocked by:** The harness's P0 `decide()` existing in this repo.

### "Demo Gym" as the calendar event's location
- **What:** Carry `Slot.place` into `CalendarEntry` (init, equality, EventKit `location`) with a CalendarSyncTests case.
- **Why:** D2 cut it to protect calendar sync on demo day; today the moved event keeps "Walk" with no location.
- **Pros:** The Calendar app matches the agent's move exactly.
- **Cons:** Touches calendar diffing (9 tests).
- **Context:** `app/Evergreen/CalendarSync/CalendarEntry.swift`, `CalendarSync.swift`.
- **Depends on / blocked by:** `Slot.place` landing with the shopping beat.
