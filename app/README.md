# TrackerPlusPlus iOS app

SwiftUI and SwiftData, iOS 18+, iPhone portrait, Swift 6 language mode (full data-race checking). This is P0a and P0b from [the design doc](../docs/designs/trackerplusplus-hackathon.md): the miss loop in the app, with the plan kept on a TrackerPlusPlus calendar (eng review D14, task T7). Visual tokens come from [DESIGN.md](../DESIGN.md).

## Run it

1. Open `app/TrackerPlusPlus.xcodeproj` in Xcode.
2. For a real phone: choose your team under Signing & Capabilities. HealthKit needs a team; check early whether a free personal team works (open question in the doc).
3. Run. Onboarding asks for Health, Calendar and notification access, then shows "Your normal". Location is asked only when gym alerts are turned on, and Live Activities the first time one starts. The usage strings are `NSHealthShareUsageDescription`, `NSCalendarsFullAccessUsageDescription` and `NSLocationWhenInUseUsageDescription`; `NSSupportsLiveActivities` is on.

The project uses folder-synced groups: any file added under `app/TrackerPlusPlus/` (or `app/TrackerPlusPlusTests/`) is in the build automatically, so there's no project file to merge.

Layout: `App/` (entry point and root view), `Agent/` (who answers `/tick`), `Contract/` (the JSON shapes), `CalendarSync/` (the TrackerPlusPlus calendar), `Notifications/` (local notifications and the gym), `LiveActivity/` (starts and updates it), `Model/` (app state, personas, the pinned plan, `Storage/` for SwiftData), `Design/` (tokens, button styles, the agent font), and `Views/` by screen (`Today`, `Feed`, `Week`, `Done`, `Onboarding`, `Demo`). One type per file, except `Contract/Contract.swift`, which stays whole so it can be compared with the harness's Python models. Colors are in `app/Shared/Assets.xcassets` with light and dark values from DESIGN.md. `app/Shared/` is in both the app and the `TrackerPlusPlusWidgets` extension (the Live Activity UI, in `app/TrackerPlusPlusWidgets/`), so put anything both need there.

## Tests

`TrackerPlusPlusTests/StandInAgentTests.swift` covers the stand-in's rules: goal rounding, the very-active cap, thin history, the grace period, comeback length and time, no repeat or undone bookings, a missed comeback, completion points and duplicate merging. `CalendarSyncTests.swift` covers how plan items become calendar events and what a sync creates, moves and deletes. `SlotDefenseTests.swift` covers moves, shrinks and when the agent leaves a workout alone. Run them with ⌘U in Xcode, or:

```
xcodebuild test -project app/TrackerPlusPlus.xcodeproj -scheme TrackerPlusPlus -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Demo controls

On by default in Debug builds, which is what Xcode installs on the simulator or a phone; off in Release (design D13). Turn them on or off in iOS Settings → Tracker++ → Demo controls, or in the simulator:

```
xcrun simctl spawn booted defaults write com.trackerplusplus.app demo_controls -bool YES
```

The floating button opens the clock (moves "now" within today, the story day), Log a workout, the Sam / Alex / Jordan switch, and Reset demo.

Sam's story: launch after 1:00 PM (or set the clock to 1:30 PM) → the agent has booked a 15-minute comeback at 6:30 PM for 40 points → set the clock to 6:45 PM → Log a workout → Done sheet, 2 of 3 this week.

## Who answers /tick

- **Harness URL empty (default):** `StandInAgent`, an offline stand-in for the harness's `decide()`. It covers only the P0 rules (normal and goal, thin history, duplicate merging, misses, comebacks, points). The harness owns the real rules; when it's deployed, put its URL in iOS Settings → Tracker++ → Harness URL.
- **Harness URL set:** `HarnessAgent` posts the snapshot to `<url>/tick`. If the call fails, the last good screen stays up with "Offline, showing last update".

## Contract

`Contract/Contract.swift` holds the snapshot and response shapes. They're provisional until the harness's Python models exist; then the harness tests write golden fixtures to `contract/fixtures/` and an XCTest decodes them with these types (eng review D10, task T3). Talk to Surya before changing a field.

## What the phone saves

The harness keeps nothing between calls, so the phone saves everything it needs to send again. That's SwiftData, in `Model/Storage.swift`:

- `Run`: the person, onboarding, the story day, the demo clock, the Done sheets already shown, and the last `/tick` answer (kept as the raw JSON so the screen stays up offline).
- `ActionRecord`: every applied action, in order, with an `undone` flag. This is the feed and the plan replay.
- `LoggedWorkout`: workouts added with "Log a workout".

The contract structs stay the wire format; the models convert to and from them. `AppModel` is the only code that reads or writes the store. If a model change can't be migrated automatically, the store is deleted and the app starts a fresh run, since it's demo state. Give new properties a default value so existing runs keep working.

## Data

`Resources/Personas/*.json` are trimmed from `MockData/output/*/health.json`. After regenerating the mock data, run:

```
/usr/bin/python3 MockData/export_for_ios.py
```

The app re-anchors each history so it ends yesterday, and today is the story day (eng review D6). Sam's week plan is pinned in `Model/PinnedPlan.swift` so the 12:00 lunchtime walk is always there (eng review D12).

## The TrackerPlusPlus calendar

With full calendar access, the app keeps the plan on its own TrackerPlusPlus calendar: on iCloud if the phone has it, otherwise on the phone (outside voice 15). Every change to the run syncs it, so the pinned week appears, a comeback is added, "Pick another time" moves the event and Undo removes it.

- Each event's URL holds a key made of the story day and the plan item's id (`trackerplusplus://plan/2026-11-19/plan-sam-d0-120`). Syncing compares those keys, so repeat ticks never duplicate an event, and the app only touches events that carry its key.
- Sync covers the story day and the 3 weeks after it. Earlier days stay as history.
- Reset demo removes the app's events in the month around the story day, then puts the fresh plan back.
- Without full access the plan stays in the app, and Today shows "Turn on Calendar" (the system prompt the first time, Settings after a denial).

## Slot defense

When something lands on an upcoming workout, the agent moves it before it can be missed (plan item 8, task T10, demo script step 3).

- With calendar access, every tick sends `busy`: the start and end of the person's timed events on their other calendars for the next 3 weeks. Titles never leave the phone, and all-day events, events marked free and the app's own events are left out.
- The app ticks about a second after any calendar change, so a meeting accepted elsewhere is defended while the app is open, and again when it comes back to the foreground.
- The stand-in's rule (`Agent/StandInAgent+SlotDefense.swift`): move to right after the conflict, else right before, staying within 1 hour earlier to 1½ hours later than planned. If neither fits at full length, shrink into the biggest free gap of at least 15 minutes, else leave it. One action per workout and conflict, so Undo sticks. Comebacks also avoid busy times. The harness owns the real rule.
- Demo controls → **Add a meeting on the next workout** puts a 1-hour "Team sync" on the person's own calendar 15 minutes before tomorrow's first workout. Reset demo removes it.

To check sync without the Calendar app, the log is under subsystem `com.trackerplusplus.app`, category `calendar`.

## Notifications and Live Activity

No push backend yet, so everything is local (plan item 16 and the Lock Screen):

- **Calendar trigger:** a reminder 30 minutes before each upcoming workout in the next week. They're rescheduled on every change, so a move or an undo carries over. They fire on the phone's real clock, not the demo clock.
- **Timer trigger:** demo controls → **Send a test notification in 5 seconds** repeats what the agent last did, as a notification ("Moved: Something landed on tomorrow's 7:30 AM elliptical session…"). Lock the phone to see it.
- **Location trigger:** **Gym arrival alerts** asks for location and watches a demo gym (`Notifications/Gym.swift`, a fixed spot) for arrival and departure. The iOS 27 simulator never fires location triggers (locationd logs "Couldn't get fences"), so **Arrive at the gym** and **Leave the gym** send the same notifications 3 seconds later. The real geofence is untested until it runs on a phone.
- **Mock pushes:** `app/MockPushes/*.apns` are what the harness would push once it has a backend. Send one to the booted simulator with `app/MockPushes/send.sh comeback-booked` (also `workout-moved`, `workout-reminder`, `workout-done`), or drag a `.apns` file onto the simulator window.
- **Live Activity:** the next workout on the Lock Screen and in the Dynamic Island, from 2 hours before it until it's done, then it shows the points for 15 minutes. **Show Live Activity for the next workout** starts it now. The countdown is shifted by the demo clock, so at a demo time of 1:30 PM the 6:30 PM comeback shows 5 hours. It's started and updated on the phone (no push token).
- **Copy:** every notification's words are in `Notifications/NotificationCopy.swift`, so Surya can change them in one place (plan item 16). Same tone as the app: no guilt, points only as what a workout keeps or earns.

Banners show even with the app open. Tapping one opens Today and ticks.

## Memory and Amplitude

Amplitude runs through the Amplitude-Swift SDK (Swift Package Manager, app target only), made once in `TrackerPlusPlusApp.init()` for the US region. Its key is the project API key, built in from the git-ignored `app/Secrets.xcconfig`:

```
AMPLITUDE_API_KEY = <project API key>
```

`app/TrackerPlusPlus.xcconfig` (the project's base configuration) includes that file if it exists and points `INFOPLIST_FILE` at `TrackerPlusPlus-Info.plist`, which passes the key to the app. Without the file the app builds and sends nothing.

- **Purchase Approved:** tracked when the person taps Order it on a purchase card.
- **Memory events:** `Memory/MemoryEngine.swift` runs the memory agent's phone bundle (`memory-agent/`, see its `docs/PHONE.md`) in JavaScriptCore. After every tick it rolls the person's memory into Application Support/Memory and hands the staged events (workouts and `memory_rolled`) to the SDK with their own opaque `user_id`, `insert_id` and time, then acknowledges them so each is handed over once. Ids are HMACs under a per-install secret kept in the Keychain; events carry no names or health readings. The demo controls show how many were handed over and how many are waiting.

The bundle is a built copy: after changing `memory-agent/src`, refresh it with

```
cd memory-agent && npm install && node scripts/build-phone.mjs ../app/TrackerPlusPlus/Resources/Memory/memory-phone.js
```

## Not built yet

- Routines and the load guardrail (P1 and P2, task T11).
- Real HealthKit reads and workout import (P2). Health permission is already requested in onboarding.
- General Sans: drop `GeneralSans-Semibold.otf` into `TrackerPlusPlus/Resources/Fonts/`. It registers at launch; until then the agent's voice falls back to SF Pro Semibold.
- The contract test that decodes the harness's golden fixtures (task T3). It goes in `TrackerPlusPlusTests/` once `contract/fixtures/` exists.
- App icon.
