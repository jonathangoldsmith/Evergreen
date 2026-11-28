import Foundation

/// Today's range (TODOS "Readiness, range, sleep and widgets", item 3): how
/// many training minutes today keeps the person's week in range, from their
/// own load. One pure function over plain values, like the brake's rule.
///
/// Load is Apple Fitness's training load, the same numbers as Today's "Load:
/// up 19% on your usual week" (`TrainingInsights`): effort (1–10) × minutes,
/// the last 7 days against the last 28. The ceiling keeps the rolling 7 days'
/// load at or under 1.3× the usual week's (the 28 days over 4), the top of
/// Gabbett's 0.8–1.3 band (Br J Sports Med 2016), which the hackathon's load
/// cap also used; that room becomes minutes at the person's typical effort,
/// so hard weeks leave fewer minutes than easy ones. Thresholds are
/// provisional; the backtest calibrates them.
///
/// A day is in range unless its load went past the room (`room`: easier
/// minutes count for less, so an easy long run can run past the minutes) or
/// it ran past a brake suggestion the person kept (`AppModel.rangeReport`). Wellness wording:
/// "in range", never "safe".
struct TodayRange: Equatable, Sendable {
    enum Effort: String, Equatable, Sendable { case easy, usual, any }

    /// 10 on a day with a planned workout (any workout of 10+ minutes counts), else 0.
    var floor: Int
    /// The most minutes today that keeps the rolling week in range.
    var ceiling: Int
    var effort: Effort
    /// The 7-day load against the 28-day one: 0.19 is 19% more.
    var loadChange: Double
    /// The training load (effort × minutes) today can add before the rolling
    /// week passes 1.3× the usual, and never less than the floor at typical
    /// effort. The ceiling is this in minutes at typical effort.
    var room: Double = 0

    static let maxRatio = 1.3
    static let lowRatio = 0.8
    /// Over this, or with readiness off, the effort is easy.
    static let easyRatio = 1.1
    /// Readiness off (`BodySignal`) lowers the ceiling like Tired.
    static let readinessCut = 0.8
    static let floorMinutes = 10
    /// Two weeks of history before there's a range.
    static let minimumHistoryDays = 14

    /// The range for `day`, from workouts before it. nil with under two weeks
    /// of history or no usual week to compare with.
    static func make(workouts: [Workout], on day: Date, planned: Bool, bodyOff: Bool, calendar: Calendar) -> TodayRange? {
        let today = calendar.startOfDay(for: day)
        let past = workouts.filter { $0.start < today }
        guard let first = past.map(\.start).min(),
              let enough = calendar.date(byAdding: .day, value: -minimumHistoryDays, to: today), first <= enough
        else { return nil }
        let insights = TrainingInsights(workouts: workouts, storyDay: today, calendar: calendar)
        guard insights.usualWeekLoad > 0 else { return nil }
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let lastSix = past.filter { $0.start >= sixDaysAgo }.reduce(0) { $0 + TrainingInsights.load($1) }
        let floor = planned ? floorMinutes : 0
        var room = maxRatio * insights.usualWeekLoad - lastSix
        if bodyOff { room *= readinessCut }
        let minutes = room / insights.typicalEffort
        let ceiling = max(floor, Int((minutes / 5).rounded(.down)) * 5)
        let ratio = 1 + insights.loadChange
        let effort: Effort = bodyOff || ratio > easyRatio ? .easy : ratio < lowRatio ? .any : .usual
        return TodayRange(floor: floor, ceiling: ceiling, effort: effort, loadChange: insights.loadChange,
                          room: max(room, Double(floor) * insights.typicalEffort))
    }

    /// "Today: 10–45 min, easy effort." / "Today: up to 45 min, your usual effort."
    var line: String {
        let minutes = floor == 0 ? "up to \(ceiling) min" : floor >= ceiling ? "\(ceiling) min" : "\(floor)–\(ceiling) min"
        let effortWords = switch effort {
        case .easy: "easy effort"
        case .usual: "your usual effort"
        case .any: "any effort"
        }
        return "Today: \(minutes), \(effortWords)."
    }

    /// "Your 7-day training load is 19% above your 28-day load." Apple
    /// Fitness's comparison, in its words.
    var reason: String {
        let percent = Int((loadChange * 100).rounded())
        return percent >= 5 ? "Your 7-day training load is \(percent)% above your 28-day load."
            : percent <= -5 ? "Your 7-day training load is \(-percent)% below your 28-day load."
            : "Your 7-day training load is right at your 28-day load."
    }
}
