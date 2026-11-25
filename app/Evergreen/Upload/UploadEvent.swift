import Foundation

/// One guardrail event for `POST /users/{id}/events` (plan item 9). Flat, with
/// only the fields its type uses; unset fields aren't encoded. The harness
/// refuses any field it doesn't know, so nothing here may carry a pain
/// location, a calendar title or a date of a past run.
struct UploadEvent: Codable, Hashable, Sendable {
    var id: String
    var type: String
    /// ISO 8601 with the phone's UTC offset.
    var at: String

    var kind: String?
    var unit: String?
    var planned: Double?
    var suggested: Double?
    var longest30: Double?
    var injuryAdjusted: Bool?
    var runDay: String?
    var choice: String?
    var run: String?
    var answer: String?
    var ostrc: [Int]?
    var weekStart: String?
    var injured: Bool?
    var monthsAgo: Int?
    var flagged: Bool?
    var jumpPercent: Int?
    var daysCounted: Int?
    var daysInRange: Int?
    var swaps: Int?
    var comebacks: Int?
    var uploads: Bool?
    var research: Bool?
    var version: Int?
    var activityType: String?
    var minutes: Int?
    var action: String?
    var points: Int?

    init(id: String, type: String, at: Date, calendar: Calendar = .current) {
        self.id = id
        self.type = type
        self.at = Self.stamp(at, calendar: calendar)
    }

    static func stamp(_ date: Date, calendar: Calendar) -> String {
        Date.ISO8601FormatStyle(timeZone: calendar.timeZone).format(date)
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day().format(date)
    }

    // MARK: The event types

    static func flag(_ flag: GuardrailFlag, run: PlannedRun, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "flag-\(StableHash.hex(run.key + flag.kind.rawValue, length: 20))", type: "flag", at: at, calendar: calendar)
        e.kind = flag.kind.rawValue
        e.unit = flag.planned.unit.rawValue
        e.planned = flag.planned.rounded.value
        e.suggested = flag.suggested.value
        e.longest30 = flag.longest30?.rounded.value
        e.injuryAdjusted = flag.injuryAdjusted
        e.runDay = day(run.start, calendar: calendar)
        return e
    }

    static func choice(_ choice: String, kind: GuardrailFlag.Kind, run: PlannedRun, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "choice-\(UUID().uuidString.lowercased())", type: "choice", at: at, calendar: calendar)
        e.choice = choice
        e.kind = kind.rawValue
        e.run = run.swapItemId
        e.runDay = day(run.start, calendar: calendar)
        return e
    }

    static func checkIn(_ answer: MorningCheck, run: PlannedRun, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "check-\(StableHash.hex(run.key, length: 20))", type: "check_in", at: at, calendar: calendar)
        e.answer = answer.rawValue
        e.runDay = day(run.start, calendar: calendar)
        return e
    }

    /// The one-tap answer, then (with `ostrc`) the full answer as a second event.
    static func pain(_ answer: PainAnswer, ostrc: [Int]?, week: Date, at: Date, calendar: Calendar) -> UploadEvent {
        let stage = ostrc == nil || answer == .no ? "1" : "2"
        var e = UploadEvent(id: "pain-\(day(week, calendar: calendar))-\(stage)", type: "pain", at: at, calendar: calendar)
        e.answer = answer.rawValue
        e.ostrc = ostrc
        e.weekStart = day(week, calendar: calendar)
        return e
    }

    /// Injury as yes/no and months ago, never where (item 9).
    static func injury(month: Date?, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "injury-\(Int(at.timeIntervalSince1970))", type: "injury", at: at, calendar: calendar)
        e.injured = month != nil
        e.monthsAgo = month.map { max(0, min(12, calendar.dateComponents([.month], from: $0, to: at).month ?? 0)) }
        return e
    }

    /// A week's counts for the coach page (item 18); the newest upload wins.
    static func rangeWeek(_ report: RangeReport, week: Date, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "range_week-\(day(week, calendar: calendar))", type: "range_week", at: at, calendar: calendar)
        e.weekStart = day(week, calendar: calendar)
        e.daysCounted = report.daysCounted
        e.daysInRange = report.daysInRange
        e.swaps = report.swaps
        e.comebacks = 0
        return e
    }

    /// One backtest answer (R7): no date or distance, the jump rounded to 5.
    static func backtestAnswer(_ answer: String, day: Backtest.Day, seed: UInt64, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "bt-\(StableHash.hex("\(seed)-\(day.date.timeIntervalSince1970)", length: 20))",
                            type: "backtest_answer", at: at, calendar: calendar)
        e.answer = answer
        e.flagged = day.flagged
        e.jumpPercent = max(-100, day.jumpPercentRounded)
        e.monthsAgo = max(0, min(13, calendar.dateComponents([.month], from: day.date, to: at).month ?? 0))
        return e
    }

    /// A missed workout and the comeback's life (range plan item 16): offered,
    /// undone or completed. Kind and minutes only.
    static func miss(_ item: PlanItem, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "miss-\(StableHash.hex(item.id, length: 20))", type: "miss", at: at, calendar: calendar)
        e.activityType = item.slot.activityType
        e.minutes = item.slot.minutes
        return e
    }

    static func comeback(_ action: String, item: Slot, points: Int?, comebackId: String, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "comeback-\(action)-\(StableHash.hex(comebackId, length: 16))", type: "comeback", at: at, calendar: calendar)
        e.action = action
        e.activityType = item.activityType
        e.minutes = item.minutes
        e.points = points
        return e
    }

    static func consent(research: Bool, version: Int, at: Date, calendar: Calendar) -> UploadEvent {
        var e = UploadEvent(id: "consent-\(Int(at.timeIntervalSince1970))", type: "consent", at: at, calendar: calendar)
        e.uploads = true
        e.research = research
        e.version = version
        return e
    }
}
