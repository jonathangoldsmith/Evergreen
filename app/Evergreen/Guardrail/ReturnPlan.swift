import Foundation

/// The return-to-running plan (range plan item 21): 4 weeks of walk-run
/// sessions on the days the person picks, starting at 20 minutes of 1 minute
/// running and 2 walking. Each week's longest session is at most 10% over the
/// week before (20, 22, 24, 26 minutes), so it stays under the brake's return
/// limit of 30 minutes. Pure, so it has table tests.
enum ReturnPlan {
    static let weeks = 4
    static let firstMinutes = 20
    static let weeklyGrowth = 1.10
    /// Run and walk minutes per repeat, week by week: more running each week.
    static let intervals: [(run: Int, walk: Int)] = [(1, 2), (2, 2), (3, 2), (4, 1)]
    /// The brake's return limit (item 5): no session reaches it.
    static let limitMinutes = 30
    /// Without recent runs: Monday, Wednesday, Saturday (eng re-run outside voice #9).
    static let defaultWeekdays: Set<Int> = [2, 4, 7]
    static let defaultStartMinute = 7 * 60
    static let suggestedDays = 2...4

    struct Session: Hashable, Sendable, Identifiable {
        /// 0-based week of the plan.
        var week: Int
        var start: Date
        var minutes: Int
        var runMinutes: Int
        var walkMinutes: Int
        var id: Date { start }

        var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

        /// "Walk-run 20 min: 1 min run, 2 min walk"
        var title: String { "Walk-run \(minutes) min: \(runMinutes) min run, \(walkMinutes) min walk" }
    }

    /// Each week's session length: 20, then +10% rounded down.
    static var minutesByWeek: [Int] {
        var lengths = [firstMinutes]
        while lengths.count < weeks {
            lengths.append(Int(Double(lengths.last ?? firstMinutes) * weeklyGrowth))
        }
        return lengths
    }

    /// The sessions from `start` (the first day that can hold one), on the
    /// picked weekdays (1 = Sunday … 7 = Saturday), from `fromWeek` to the end.
    static func sessions(from start: Date, weekdays: Set<Int>, startMinute: Int, fromWeek: Int = 0,
                         calendar: Calendar) -> [Session] {
        guard !weekdays.isEmpty, fromWeek < weeks else { return [] }
        let first = calendar.startOfDay(for: start)
        var out: [Session] = []
        for week in fromWeek..<weeks {
            let offset = week - fromWeek
            for day in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset * 7 + day, to: first),
                      weekdays.contains(calendar.component(.weekday, from: date)),
                      let begin = calendar.date(byAdding: .minute, value: startMinute, to: date),
                      begin >= start
                else { continue }
                let interval = intervals[min(week, intervals.count - 1)]
                out.append(Session(week: week, start: begin, minutes: minutesByWeek[week],
                                   runMinutes: interval.run, walkMinutes: interval.walk))
            }
        }
        return out
    }

    /// The usual run days and time from history (HistoryPlan's usual week), or
    /// Monday, Wednesday and Saturday at 7 AM without recent runs.
    static func suggestedDays(history: [Workout], today: Date, calendar: Calendar) -> (weekdays: Set<Int>, startMinute: Int) {
        let runs = HistoryPlan.usualWeek(history, storyDay: calendar.startOfDay(for: today), calendar: calendar)
            .filter { $0.activityType == "Running" }
        guard !runs.isEmpty else { return (defaultWeekdays, defaultStartMinute) }
        let days = Set(runs.prefix(3).map(\.weekday))
        let minutes = runs.map(\.startMinute).sorted()
        return (days, minutes[minutes.count / 2])
    }
}
