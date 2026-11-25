import Foundation
import SwiftData

/// The return-to-running plan as the person set it up (range plan item 21).
/// Its sessions are worked out from this, so a pause, resume or end never
/// leaves stale sessions behind. Not tied to the story day.
@Model
final class ReturnPlanState {
    enum Status: String, Codable { case active, paused, ended, finished }

    /// When the current stretch of sessions starts (the yes, or the resume).
    var start: Date
    /// The plan week that stretch starts at (0 at first, the paused week after a resume).
    var fromWeek: Int
    /// 1 = Sunday … 7 = Saturday, comma-separated.
    var weekdaysText: String
    var startMinute: Int
    var statusRaw: String
    /// The week the plan was in when a "Yes" pain answer paused it.
    var pausedWeek: Int?
    var createdAt: Date
    var endedAt: Date?

    init(start: Date, weekdays: Set<Int>, startMinute: Int, at date: Date) {
        self.start = start
        fromWeek = 0
        weekdaysText = weekdays.sorted().map(String.init).joined(separator: ",")
        self.startMinute = startMinute
        statusRaw = Status.active.rawValue
        createdAt = date
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .ended }
        set { statusRaw = newValue.rawValue }
    }

    var weekdays: Set<Int> { Set(weekdaysText.split(separator: ",").compactMap { Int($0) }) }
}
