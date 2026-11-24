import Foundation

/// A run on one of the person's training calendars (Runna, a coach's plan),
/// read but never changed (plan item 1).
struct PlannedRun: Hashable, Sendable, Identifiable {
    /// The source calendar's identifier, the run's start day and its title.
    /// Never `eventIdentifier`, which the calendar code doesn't trust (item 8).
    var key: String
    var title: String
    var calendarTitle: String
    var start: Date
    var end: Date
    /// Nil for an all-day event with no size in its title: shown, never flagged.
    var size: RunSize?
    /// Tempo, intervals, threshold and the like (the Tired rule).
    var isHard: Bool
    var isAllDay: Bool

    var id: String { key }
    var minutes: Double { end.timeIntervalSince(start) / 60 }

    /// The plan item id of its swap: "swap-" and a short stable hash of the key.
    var swapItemId: String { "swap-\(StableHash.hex(key, length: 12))" }
}
