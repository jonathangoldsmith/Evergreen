import ActivityKit
import Foundation

/// The Live Activity for the next workout: on the Lock Screen and in the
/// Dynamic Island from about 2 hours before it until it's done. Shared by the
/// app, which starts and updates it, and the widget extension, which draws it.
/// No push token: it's started and updated on the phone (no backend yet).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case upcoming, done
        }

        var phase: Phase
        /// "Comeback walk", "Elliptical".
        var title: String
        var symbol: String
        /// The planned start, shown as a clock time ("6:30 PM").
        var startText: String
        var minutes: Int
        var points: Int
        var isComeback: Bool
        /// The real-clock moment the countdown runs to. With the demo clock this
        /// is shifted so the countdown matches the story time, not the phone's.
        var countdownTo: Date
        /// One calm line under the title: why it's here, or what it earned.
        var note: String
    }

    /// The plan item this activity follows.
    var planItemId: String
}
