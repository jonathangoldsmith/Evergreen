# TrackerPlusPlus iOS app

SwiftUI and SwiftData, iOS 18+, iPhone portrait, Swift 6 language mode (full data-race checking). This is P0a from [the design doc](../docs/designs/trackerplusplus-hackathon.md): the miss loop shown in the app, with no calendar writes yet (eng review D14). Visual tokens come from [DESIGN.md](../DESIGN.md).

## Run it

1. Open `app/TrackerPlusPlus.xcodeproj` in Xcode.
2. For a real phone: choose your team under Signing & Capabilities. HealthKit needs a team; check early whether a free personal team works (open question in the doc).
3. Run. Onboarding asks for Health and Calendar access, then shows "Your normal".

The project uses folder-synced groups: any file added under `app/TrackerPlusPlus/` (or `app/TrackerPlusPlusTests/`) is in the build automatically, so there's no project file to merge.

Layout: `App/` (entry point and root view), `Agent/` (who answers `/tick`), `Contract/` (the JSON shapes), `Model/` (app state, personas, the pinned plan, `Storage/` for SwiftData), `Design/` (tokens, button styles, the agent font), and `Views/` by screen (`Today`, `Feed`, `Week`, `Done`, `Onboarding`, `Demo`). One type per file, except `Contract/Contract.swift`, which stays whole so it can be compared with the harness's Python models. Colors are in `Assets.xcassets` with light and dark values from DESIGN.md.

## Tests

`TrackerPlusPlusTests/StandInAgentTests.swift` covers the stand-in's rules: goal rounding, the very-active cap, thin history, the grace period, comeback length and time, no repeat or undone bookings, a missed comeback, completion points and duplicate merging. Run them with ⌘U in Xcode, or:

```
xcodebuild test -project app/TrackerPlusPlus.xcodeproj -scheme TrackerPlusPlus -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Demo controls

Off by default (design D13). Turn them on in iOS Settings → Tracker++ → Demo controls, or in the simulator:

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

## Not built yet

- Calendar writes: the TrackerPlusPlus calendar, slot defense and routines (P0b and P1, tasks T7 and T10).
- Real HealthKit reads and workout import (P2). Health permission is already requested in onboarding.
- General Sans: drop `GeneralSans-Semibold.otf` into `TrackerPlusPlus/Resources/Fonts/`. It registers at launch; until then the agent's voice falls back to SF Pro Semibold.
- The contract test that decodes the harness's golden fixtures (task T3). It goes in `TrackerPlusPlusTests/` once `contract/fixtures/` exists.
- App icon.
