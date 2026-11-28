# Evergreen iOS app

SwiftUI and SwiftData, iOS 18+, iPhone portrait, Swift 6 language mode (full data-race checking). This is P0a and P0b from [the design doc](../docs/designs/evergreen-hackathon.md): the miss loop in the app, with the plan kept on a Evergreen calendar (eng review D14, task T7). Visual tokens come from [DESIGN.md](../DESIGN.md).

## Run it

1. Open `app/Evergreen.xcodeproj` in Xcode.
2. For a real phone: choose your team under Signing & Capabilities. HealthKit needs a team; check early whether a free personal team works (open question in the doc).
3. Run. Onboarding asks for Health, Calendar and notification access, then shows "Your normal". Location is asked only when gym alerts are turned on, and Live Activities the first time one starts. The usage strings are `NSHealthShareUsageDescription`, `NSCalendarsFullAccessUsageDescription` and `NSLocationWhenInUseUsageDescription`; `NSSupportsLiveActivities` is on.

The project uses folder-synced groups: any file added under `app/Evergreen/` (or `app/EvergreenTests/`) is in the build automatically, so there's no project file to merge.

Layout: `App/` (entry point and root view), `Agent/` (who answers `/tick`), `Contract/` (the JSON shapes), `CalendarSync/` (the Evergreen calendar), `Notifications/` (local notifications and the gym), `LiveActivity/` (starts and updates it), `Model/` (app state, personas, the pinned plan, `Storage/` for SwiftData), `Design/` (tokens, button styles, the agent font), and `Views/` by screen (`Today`, `Feed`, `Week`, `Done`, `Onboarding`, `Demo`). One type per file, except `Contract/Contract.swift`, which stays whole so it can be compared with the harness's Python models. Colors are in `app/Shared/Assets.xcassets` with light and dark values from DESIGN.md. `app/Shared/` is in both the app and the `EvergreenWidgets` extension (the Live Activity UI, in `app/EvergreenWidgets/`), so put anything both need there.

## Tests

`EvergreenTests/StandInAgentTests.swift` covers the stand-in's rules: goal rounding, the very-active cap, thin history, the grace period, comeback length and time, no repeat or undone bookings, a missed comeback, completion points and duplicate merging. `CalendarSyncTests.swift` covers how plan items become calendar events and what a sync creates, moves and deletes. `SlotDefenseTests.swift` covers moves, shrinks and when the agent leaves a workout alone. The brake has its own: `GuardrailRuleTests` (spikes, the injury window, Sore and Tired, floors), `RunParserTests` (which calendar events are runs, and their size), `GuardrailScheduleTests` (the 2-a-day note budget and the pain week), `GuardrailCopyTests` (the words, and no "safe"), `BodySignalTests` and `ReadinessFlowTests` (readiness), `TodayRangeTests` (today's range and training load), `BedtimeTests` (the bedtime nudge before a long or hard morning run), `TrendsTests` (trends as sentences), `BacktestTests`, `RangeReportTests`, `StorageTests` (migration, set-aside, midnight), `NotifierActionTests` (Lock Screen buttons) and `EventOutboxTests` (uploads and the Amplitude list). Run them with ⌘U in Xcode, or:

```
gtimeout 20m xcodebuild test -project app/Evergreen.xcodeproj -scheme Evergreen -destination 'platform=iOS Simulator,name=iPhone 17' -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120
```

The time limits stop a stuck test: any test still running after a minute fails (Xcode rounds the limit up to whole minutes, and a test can ask for up to two with `executionTimeAllowance`), and `gtimeout` ends the whole run after 20 minutes if something else hangs, such as the simulator. `gtimeout` comes from `brew install coreutils`; on an Apple-silicon Mac it must be the one in `/opt/homebrew/bin`, because an Intel copy in `/usr/local/bin` won't run.

## Demo controls

On by default in Debug builds, which is what Xcode installs on the simulator or a phone; off in Release (design D13). Turn them on or off in iOS Settings → Evergreen → Demo controls, or in the simulator:

```
xcrun simctl spawn booted defaults write com.evergreentraining.app demo_controls -bool YES
```

The floating button opens the clock (moves "now" within today, the story day), Log a workout, the Sam / Alex / Jordan switch, and Reset demo.

Sam's story: launch after 1:00 PM (or set the clock to 1:30 PM) → the agent has booked a 15-minute comeback at 6:30 PM for 40 points → set the clock to 6:45 PM → Log a workout → Done sheet, 2 of 3 this week.

## Who answers /tick

- **Harness URL empty (default):** `StandInAgent`, an offline stand-in for the harness's `decide()`. It covers only the P0 rules (normal and goal, thin history, duplicate merging, misses, comebacks, points). The harness owns the real rules; when it's deployed, put its URL in iOS Settings → Evergreen → Harness URL.
- **Harness URL set:** `HarnessAgent` posts the snapshot to `<url>/tick`. If the call fails, the last good screen stays up with "Offline, showing last update".

## Contract

`Contract/Contract.swift` holds the snapshot and response shapes. They're provisional until the harness's Python models exist; then the harness tests write golden fixtures to `contract/fixtures/` and an XCTest decodes them with these types (eng review D10, task T3). Talk to Surya before changing a field.

## What the phone saves

The harness keeps nothing between calls, so the phone saves everything it needs to send again. That's SwiftData, in `Model/Storage.swift`:

- `Run`: the person, onboarding, the story day, the demo clock, the Done sheets already shown, and the last `/tick` answer (kept as the raw JSON so the screen stays up offline).
- `ActionRecord`: every applied action, in order, with an `undone` flag. This is the feed and the plan replay.
- `LoggedWorkout`: workouts added with "Log a workout".

Outside the run, and never cleared by a new day: `GuardrailDecision` (a swap taken or a plan kept), `CheckInRecord` (Fresh / Tired / Sore), `PainRecord` (Sunday's answer and its OSTRC answers) and `Profile` (injury month, training calendars, consent, onboarding version).

A new day starts a demo person's run over; a real person (`.me`) keeps their actions and logged workouts (eng review D4).

The contract structs stay the wire format; the models convert to and from them. `AppModel` is the only code that reads or writes the store. The store is versioned (`EvergreenSchemaV1`, `EvergreenSchemaV2`, `EvergreenMigrationPlan`). If it still can't be opened, the file is renamed to `Evergreen-unreadable-<time>.store` and a fresh store starts; it's never deleted (eng review D5). Give new properties a default value so existing runs keep working, and freeze a copy of a model inside its schema version before changing a stored property.

## Data

`Resources/Personas/*.json` are trimmed from `MockData/output/*/health.json`. After regenerating the mock data, run:

```
/usr/bin/python3 MockData/export_for_ios.py
```

The app re-anchors each history so it ends yesterday, and today is the story day (eng review D6). Sam's week plan is pinned in `Model/PinnedPlan.swift` so the 12:00 lunchtime walk is always there (eng review D12).

## The Evergreen calendar

With full calendar access, the app keeps the plan on its own Evergreen calendar: on iCloud if the phone has it, otherwise on the phone (outside voice 15). Every change to the run syncs it, so the pinned week appears, a comeback is added, "Pick another time" moves the event and Undo removes it.

- Each event's URL holds a key made of the story day and the plan item's id (`evergreen://plan/2026-11-19/plan-sam-d0-120`). Syncing compares those keys, so repeat ticks never duplicate an event, and the app only touches events that carry its key.
- Sync covers the story day and the 3 weeks after it. Earlier days stay as history.
- Reset demo removes the app's events in the month around the story day, then puts the fresh plan back.
- Without full access the plan stays in the app, and Today shows "Turn on Calendar" (the system prompt the first time, Settings after a denial).

## Slot defense

When something lands on an upcoming workout, the agent moves it before it can be missed (plan item 8, task T10, demo script step 3).

- With calendar access, every tick sends `busy`: the start and end of the person's timed events on their other calendars for the next 3 weeks. Titles never leave the phone, and all-day events, events marked free and the app's own events are left out.
- The app ticks about a second after any calendar change, so a meeting accepted elsewhere is defended while the app is open, and again when it comes back to the foreground.
- The stand-in's rule (`Agent/StandInAgent+SlotDefense.swift`): move to right after the conflict, else right before, staying within 1 hour earlier to 1½ hours later than planned. If neither fits at full length, shrink into the biggest free gap of at least 15 minutes, else leave it. One action per workout and conflict, so Undo sticks. Comebacks also avoid busy times. The harness owns the real rule.
- Demo controls → **Add a meeting on the next workout** puts a 1-hour "Team sync" on the person's own calendar 15 minutes before tomorrow's first workout. Reset demo removes it.

To check sync without the Calendar app, the log is under subsystem `com.evergreentraining.app`, category `calendar`.

## Notifications and Live Activity

No push backend yet, so everything is local (plan item 16 and the Lock Screen):

- **Calendar trigger:** a reminder 30 minutes before each upcoming workout in the next week. They're rescheduled on every change, so a move or an undo carries over. They fire on the phone's real clock, not the demo clock.
- **Timer trigger:** demo controls → **Send a test notification in 5 seconds** repeats what the agent last did, as a notification ("Moved: Something landed on tomorrow's 7:30 AM elliptical session…"). Lock the phone to see it.
- **Location trigger:** **Gym arrival alerts** asks for location and watches a demo gym (`Notifications/Gym.swift`, a fixed spot) for arrival and departure. The iOS 27 simulator never fires location triggers (locationd logs "Couldn't get fences"), so **Arrive at the gym** and **Leave the gym** send the same notifications 3 seconds later. The real geofence is untested until it runs on a phone.
- **Mock pushes:** `app/MockPushes/*.apns` are what the harness would push once it has a backend. Send one to the booted simulator with `app/MockPushes/send.sh comeback-booked` (also `workout-moved`, `workout-reminder`, `workout-done`), or drag a `.apns` file onto the simulator window.
- **Live Activity:** the next workout on the Lock Screen and in the Dynamic Island, from 2 hours before it until it's done, then it shows the points for 15 minutes. **Show Live Activity for the next workout** starts it now. The countdown is shifted by the demo clock, so at a demo time of 1:30 PM the 6:30 PM comeback shows 5 hours. It's started and updated on the phone (no push token).
- **Copy:** every notification's words are in `Notifications/NotificationCopy.swift`, so Surya can change them in one place (plan item 16). Same tone as the app: no guilt, points only as what a workout keeps or earns.

Banners show even with the app open. Tapping one opens Today and ticks.

## Jordan's shoes from the harness

Surya's harness (`harness/`, live at `https://trackerplusplus-harness.vercel.app`, see [harness/INTEGRATION.md](../harness/INTEGRATION.md)) picks Jordan's next pair from real review sites, ranks it on Superlinked SIE, cites Senso and logs every decision in SingleStore. `Agent/RecommendClient.swift` asks its `POST /shoes/recommend` when the stand-in's shoe rule fires (375 miles, race within 14 days), and the answer is the card's `Purchase`. Swift keeps the trigger, the `shoes-<boughtOn>` id, Order it / Not now / Cancel order, the break-in runs and the calendar.

- **Turn it on:** put the shared secret (Surya has it) in `app/Secrets.xcconfig` as `HARNESS_SECRET = …`, or in iOS Settings → Evergreen → Harness secret. The URL defaults to the deployed harness; Shoes URL overrides it (for example `http://localhost:8000`).
- **Fallback:** no secret, no answer within 6 seconds, any error, or the harness reading the pair as fresh → the stand-in's own pick (Pacer 9) with cached passages.
- **Before the demo:** `curl -X POST https://trackerplusplus-harness.vercel.app/warm -H "X-Harness-Secret: $SECRET"` so the first pick doesn't wait for a cold model.
- Why this pair shows the first 5 options and a "Show N more" button for the rest.

**Next 7 days from the planner:** with the same secret, a row under Today's plan opens the harness's `POST /workouts/recommend` (`Agent/PlannerClient.swift`, `Views/Today/WeekPlanView.swift`). It sends the demo clock, the shoe wear and race from the shoe beat, the new pair's arrival once one is ordered, and the busy times, and shows the 7 days with each reason and source, plus optional suggestions marked "not booked". It's a read-only preview: nothing is added to the plan or the calendar. The harness plans from the memory agent's bundled copy, since the app doesn't send its own memory yet.

`harness_url` is different: it swaps the whole agent. Leave it empty.

## You, from Apple Health

Besides Jordan's demo week, the app plans for a real person (`PersonaKey.me`):

- **Reading Health:** `Health/HealthReader.swift` reads 60 days of workouts (type, times, average heart rate, distance, indoors) and 28 days of sleep and resting heart rate. It's cached in Application Support and read again on launch and whenever the app comes forward.
- **The week:** `Model/HistoryPlan.swift` turns each weekday the person trained on at least twice in the last 4 weeks into a workout at their usual time, kind and length. The longest usual run becomes the long run. With no pattern yet, it plans two short starter walks. Today's usual workouts that had already started when the plan was made are left out.
- **When it's used:** after onboarding, when Apple Health has workouts (otherwise Jordan's demo week stays), or from Demo → **You, from Apple Health**. The other demo beats switch back to Jordan.
- **The planner:** "Next 7 days" sends the history and this install's anonymous id (`Agent/DeviceIdentity.swift`, an HMAC under the Keychain secret) to the harness, which keeps the latest copy per id. **Your data** on Today shows what's kept and deletes it.
- **Simulator:** Debug builds have Demo → **Add a month of sample data to Apple Health**, which writes Jordan's mock month into Health as real samples.

## Memory and Amplitude

Amplitude runs through the Amplitude-Swift SDK (Swift Package Manager, app target only), made once in `EvergreenApp.init()` for the US region. Its key is the project API key, built in from the git-ignored `app/Secrets.xcconfig`:

```
AMPLITUDE_API_KEY = <project API key>
```

`app/Evergreen.xcconfig` (the project's base configuration) includes that file if it exists and points `INFOPLIST_FILE` at `Evergreen-Info.plist`, which passes the key to the app. Without the file the app builds and sends nothing.

- **Purchase Approved:** tracked when the person taps Order it on a purchase card.
- **Memory events:** `Memory/MemoryEngine.swift` runs the memory agent's phone bundle (`memory-agent/`, see its `docs/PHONE.md`) in JavaScriptCore. After every tick it rolls the person's memory into Application Support/Memory and hands the staged events (workouts and `memory_rolled`) to the SDK with their own opaque `user_id`, `insert_id` and time, then acknowledges them so each is handed over once. Ids are HMACs under a per-install secret kept in the Keychain; events carry no names or health readings. The demo controls show how many were handed over and how many are waiting.

The bundle is a built copy: after changing `memory-agent/src`, refresh it with

```
cd memory-agent && npm install && node scripts/build-phone.mjs ../app/Evergreen/Resources/Memory/memory-phone.js
```

## The brake (training range, milestone 1)

The plan is [docs/designs/evergreen-training-range.md](../docs/designs/evergreen-training-range.md). In short: Evergreen reads the runs on the calendars the person picks (Runna, TrainingPeaks, a coach's), checks each against their longest run in the last 30 days, and offers a shorter run before a big jump. It never changes the training calendar; a swap is Evergreen's own event.

- `Guardrail/`: the pure parts, each with table tests. `RunParser` (which events are runs, how big), `GuardrailRule` (+10% past the 30-day longest, +5% within 12 months of an injury; Sore and Tired from the morning check; with no answer, an off body signal cuts like Tired; floors of 3 km or 20 min), `BodySignal` (readiness: this morning's resting heart rate, last night's sleep and the 7-day HRV against the person's usual; two of three off counts; HRV stays on the phone), `TodayRange` (today's range: the minutes that keep the rolling 7-day training load, Apple Fitness's effort × minutes, at or under 1.3× the usual week; a run today longer than that gets a load flag, and a day over its ceiling is out of range in the report, the watch and the coach page), `Bedtime` (the evening before a long or hard morning run, on a training calendar, or 60+ minutes in Evergreen's own plan, lights out so the usual night of sleep, at least 7h, ends an hour before the run; between 9 and 11 PM, one a night, two a week, the note an hour earlier and first dropped from the budget), `GuardrailSchedule` (at most 2 notes a day, the Sunday pain note never dropped; a bedtime note goes first), `PainWeek`, `RangeReport`, `Backtest` and `OSTRC`.
- `Model/AppModel+Guardrail.swift`: flags, decisions, swap plan items and the week count. `+Notes` (scheduling and Lock Screen buttons), `+Pain`, `+Range`, `+Setup`, `+Backtest`.
- Onboarding after Permissions: What leaves your phone (consent and a separate research opt-in), training calendars, the injury question, then the backtest. People who onboarded earlier see these once (`Profile.onboardingVersion`).
- Today stacks cards in urgency order: the run decision (morning check, swap, or the choice with Undo), the Sunday pain check-in, then the agent's latest action. From Sunday 7 PM through Monday the week line is the range report.
- `Upload/`: after "Allow and continue", events go to `POST /users/{id}/events` through `EventOutbox`, which keeps each one until the harness returns its id. Amplitude gets only `AnalyticsEvent`'s fixed words.
- Demo controls: "A big jump on tomorrow's long run" adds a "Runna (demo)" calendar with a 2½-hour long run for Jordan, whose longest this month was under 2 hours.

## The push and the buddy (milestone 2)

- **The push** (range plan items 10–16): people at 2 workouts a week or fewer get one comeback after a miss, at about 60% of their usual length in the next free time within a day, for 2× points (`StandInAgent+Comeback.swift`). A missed comeback gets a quiet note, never another. The card says what the points keep, and finishing a plan item shows the Done sheet with the buddy celebrating. Sam is the newcomer persona; the demo controls have "A missed walk books a comeback" and "Finish the comeback".
- **The buddy** (item 22): Your data → People invites a friend with a code or pairs with a friend's code; Welcome has "Have a code from a friend?" for the short path. A paired inviter's finished workouts go up as `workout_completed`, on every Health read and from HealthKit's background observer (`WorkoutObserver`), and the harness sends the friend one note per workout over APNs. `EvergreenAppDelegate` sends the push token. The entitlements include `aps-environment` and HealthKit background delivery, so device builds need those capabilities on the App ID (automatic signing adds them).

## The coach page, device auth and CI (milestone 3)

- The coach page is the harness's (`harness/`); the app shares a link from Your data → People. Every `/users/{id}/...` call carries a per-device token from `POST /devices`, kept in the Keychain (`DeviceAuth`) and sent by `HarnessRequest.send`.
- The rule has a Python twin (`harness/guardrail.py`); `contract/fixtures/guardrail.json` runs against both. CI (`.github/workflows/tests.yml`) runs pytest and the app tests in UTC.

## The return plan and the watch (milestone 4)

- **Return to running** (range plan item 21): after an injury in the last 3 months, Today offers a 4-week walk-run plan (`Guardrail/ReturnPlan.swift`: 20 to 26 minutes, 1:2 up to 4:1 run:walk) on the person's usual run days, which the weekday toggles change (Mon/Wed/Sat at 7 AM with no history). While it's active, training-calendar runs and Evergreen's own runs pause, and a session wins its day. A "Yes" to the pain check-in pauses it; End has Undo. Stored as `ReturnPlanState` in schema V3. Demo controls: "Coming back from an injury".
- **The watch** (item 19): `EvergreenWatch/` shows the next run's question (Make it / Keep, or the morning check) and today's line, and sends taps back over WatchConnectivity (`Watch/PhoneWatchLink.swift`, `Model/AppModel+Watch.swift`). The rule runs only on the phone; the first answer wins, from the watch, the app or the Lock Screen. A tap made while the phone is away is queued and sent later.
- **Complications** (`EvergreenWatchWidget/`): circular "in range" days and a rectangular next-run line, read from the App Group the watch app writes, with an entry at midnight so tomorrow's line rolls over without the phone.
- **Phone widget** (`EvergreenWidget/`, shared code in `WidgetShared/`): Lock Screen (inline, circular "5/6", rectangular) and Home Screen (small, medium). It shows the same state the watch gets, which the app saves to the App Group in `pushWatchState()` and reloads only when it changes (`Model/AppModel+Widget.swift`). The medium size asks the run's question (Make it / Keep, or Fresh / Tired / Sore). Its buttons are `evergreen://answer` links that open Evergreen and go through `handleWatchAnswer`, so a widget answer is the same single decision as a watch tap. Each link carries a token from the App Group, so a web page or another app can't answer for the person. Its colors are copies of the app's in `EvergreenWidget/Assets.xcassets`: change both together. Tests: `WidgetTests`.
- To run the watch: pair a watch simulator with the iPhone simulator, build the Evergreen scheme (it embeds the watch app), install `EvergreenWatch.app` on the watch, and launch both.

## Not built yet

- Routines (P1, task T11).
- From the range plan: the device checks on a real paired watch (task E14).
- Real HealthKit reads and workout import (P2). Health permission is already requested in onboarding.
- General Sans: drop `GeneralSans-Semibold.otf` into `Evergreen/Resources/Fonts/`. It registers at launch; until then the agent's voice falls back to SF Pro Semibold.
- The contract test that decodes the harness's golden fixtures (task T3). It goes in `EvergreenTests/` once `contract/fixtures/` exists.
- App icon.
