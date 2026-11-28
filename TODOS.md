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

## Readiness, range, sleep and widgets (Athlytic comparison, 2026-11-27)

Decided: Evergreen takes the signals Athlytic shows (recovery, exertion, sleep, trends, widgets) and turns them into plan changes explained in a sentence. No 0–100 score, ring or chart; trends stay as sentences (DESIGN.md "progress is a sentence"). Copy stays wellness wording: never "safe" or "prevents injury". Suggested order: 1 → 2 → 3 → 4 → 5.

### 1. iPhone widgets (lock screen + interactive home screen) — built 2026-11-27
- **Built:** `app/EvergreenWidget/`, `app/WidgetShared/`, `Model/AppModel+Widget.swift`, `WidgetTests`. The buttons are the watch's answers (Make it / Keep, Fresh / Tired / Sore), not "Move it / Done". They are links that open Evergreen and go through `handleWatchAnswer`, not in-place App Intents, so the calendar, notifications and audit record stay on one code path. Lock Screen sizes are untested on screen.
- **What:** A phone widget extension. Lock screen (accessory families): text only, "Run 6:00 PM · 30 min easy" and "5/6 days in range", with VoiceOver labels. Home screen: today's workout with App Intent buttons ("Move it", "Done") that run the same actions as the Today card.
- **Why:** Athlytic's widgets show a number; ours can act. Cheapest of the five, and it brings people back daily.
- **Pros:** Reuses the watch widget's entry/provider pattern (`app/EvergreenWatchWidget/`).
- **Cons:** A fourth Xcode target. The phone app has no App Group today (only the watch app and watch widget carry `group.com.evergreentraining.app`), so the phone needs the entitlement and a shared store the widget reads. Intent buttons must go through the same code path as Undo/audit records.
- **Context:** `EvergreenComplications.swift`, `RangeProvider.swift`, `AppModel+Watch.swift`, `WatchStateStore.swift`.
- **Depends on / blocked by:** Nothing.

### 2. Readiness from HRV, resting heart rate and sleep
- **What:** Read `heartRateVariabilitySDNN`. Compare 7-day rolling HRV, resting heart rate and last night's sleep against the person's own 30–60 day baseline, combined with the morning "How do your legs feel?" answer. The output is a plan change plus a sentence: "Your resting heart rate is 6 above your usual and you slept 5h40, so I made today's run easy."
- **Why:** Athlytic's core feature, turned into an action. Self-report stays the main signal: Saw et al. (BJSM 2016) found subjective measures tracked training response better than objective ones.
- **Pros:** Resting heart rate and sleep are already read (`HealthReader.swift`); only HRV and the baseline math are new.
- **Cons:** Apple Watch HRV is sparse and noisy; needs rolling averages and a "not enough data" path. A new HealthKit permission.
- **Context:** `HealthReader.swift`, `HealthHistory.swift`, `TrainingInsights.swift`, `MorningCheck.swift`, the planner's readiness input (`PlannerClient.swift`). Synthetic HRV needs adding to `MockData/` personas.
- **Depends on / blocked by:** Nothing.

### 3. Today's range (exertion as a target)
- **What:** Turn the 7-day vs 28-day load ratio into a target for today: "Today: 30–40 min, easy effort." Readiness (2) narrows or widens it.
- **Why:** Athlytic's Target Exertion, in the training-range language the app already uses.
- **Pros:** The load math exists (`TrainingInsights`, guardrail rules); this is mostly copy and one Today line.
- **Cons:** Must not contradict the guardrail's own range copy; one source for the numbers.
- **Context:** `TrainingInsights.swift`, `Guardrail/`, `TodayPlanSection.swift`.
- **Depends on / blocked by:** Better with 2, works without it.

### 4. Sleep the agent defends
- **What:** The evening before a long-run or hard-workout morning, a bedtime nudge ("Lights out by 10:30 for tomorrow's long run"). After a short night, readiness (2) moves or eases the hard workout.
- **Why:** Athlytic's Target Bedtime, applied as "make sure it happens". No separate sleep score.
- **Pros:** Uses the existing notification scheduling and sleep reads.
- **Cons:** Another notification; needs a quiet-hours cap so it doesn't nag.
- **Context:** `Notifications/NotificationScheduling.swift`, `NotificationCopy.swift`, `HealthReader.swift`.
- **Depends on / blocked by:** 2 for the "after a short night" half.

### 5. Trends as sentences
- **What:** A weekly and monthly summary in plain sentences: "This month: 14 of 16 workouts, load steady, resting heart rate down 3 bpm." No chart.
- **Why:** Athlytic's Trends tab, within DESIGN.md.
- **Pros:** Facts already exist in the memory layer (`memory-phone.js`).
- **Cons:** Needs a home that isn't a card-in-a-card on Today (maybe the Done sheet or Your data).
- **Context:** `YourDataView.swift`, `DoneSummary.swift`, `MemoryEngine.swift`.
- **Depends on / blocked by:** 2 for the heart-rate and HRV lines.
