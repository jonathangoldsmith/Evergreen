import Foundation

/// The Sunday range report (plan item 18, design decision 2): which days
/// counted, how many stayed in range, and the swaps taken. Computed on the
/// phone, so it works offline. No guilt: it never names the days out of range.
struct RangeReport: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        /// Evergreen has some sign of the day: a Health workout, a morning
        /// answer, or the app opened. Days with none are left out.
        var counted: Bool
        /// Went over the day's range (`TodayRange`'s ceiling), or ran more than
        /// a swap's suggestion after keeping the plan.
        var outOfRange: Bool
    }

    var daysCounted: Int
    var daysInRange: Int
    var swaps: Int
    /// The one swap was a long run's (for "kept your long run in range").
    var longRunSwap: Bool

    init(days: [Day], swaps: Int, longRunSwap: Bool) {
        let counted = days.filter(\.counted)
        daysCounted = counted.count
        daysInRange = counted.filter { !$0.outOfRange }.count
        self.swaps = swaps
        self.longRunSwap = longRunSwap
    }

    /// "In range 5 of 6 days. 1 swap kept your long run in range." Wellness
    /// wording only (BN3): "in range", never "safe".
    var sentence: String {
        guard daysCounted > 0 else { return "Not enough data this week." }
        let range = "In range \(daysInRange) of \(daysCounted) days."
        switch swaps {
        case 0:
            return daysInRange == daysCounted ? "\(range) Nothing needed changing." : range
        case 1:
            return "\(range) 1 swap kept your \(longRunSwap ? "long run" : "run") in range."
        default:
            return "\(range) \(swaps) swaps kept your runs in range."
        }
    }

    /// From Sunday 7 PM (or right after the pain answer) through Monday, the
    /// week sentence is the report; otherwise it's the workout count.
    static func reportWeek(at now: Date, painAnswered: (Date) -> Bool, calendar: Calendar) -> Date? {
        let thisWeek = PainWeek.monday(of: now, calendar: calendar)
        let sunday = calendar.date(byAdding: .day, value: 6, to: thisWeek) ?? thisWeek
        let sevenPM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: sunday) ?? sunday
        if calendar.isDate(now, inSameDayAs: sunday), now >= sevenPM || painAnswered(thisWeek) { return thisWeek }
        if calendar.component(.weekday, from: now) == 2 { return calendar.date(byAdding: .day, value: -7, to: thisWeek) }
        return nil
    }
}
