import Foundation

/// Trends as sentences (TODOS item 5): the last 7 days and the last 4 weeks
/// in plain words, never a chart, ring or score (DESIGN.md: progress is a
/// sentence). One pure function over plain values, from what's already on the
/// phone: Apple Health workouts and days, and the range reports.
///
/// Each line says only what changed against the person's own usual, with a
/// "steady" band so small wobbles read as "about your usual". Wellness
/// wording: facts, never what a number means for an injury.
struct Trends: Equatable, Sendable {
    /// "Last 7 days".
    var week: [String]
    /// "Last 4 weeks".
    var month: [String]

    /// The range report summed over the last 4 weeks.
    struct Range: Equatable, Sendable {
        var daysInRange: Int
        var daysCounted: Int
        var swaps: Int
    }

    /// Under these, a change reads as steady.
    static let steadyBeats = 2.0
    static let steadySleepMinutes = 15.0
    static let steadyFraction = 0.05
    /// Readings needed: 3 of the last 7 days, and 7 days of usual before them.
    static let minimumRecent = 3
    static let minimumUsual = 7
    /// HRV's usual reaches back 60 days (HealthReader reads that far); resting
    /// heart rate and sleep are read for 28.
    static let hrvUsualDays = 60
    static let usualDays = 28
    /// The 4 weeks before count only when the history starts by this many days ago (3 of those 4 weeks).
    static let comparedFromDays = 49

    var isEmpty: Bool { week.isEmpty && month.isEmpty }

    static func make(workouts: [Workout], days: [HealthHistory.Day], range: Range?, on day: Date,
                     calendar: Calendar) -> Trends {
        let today = calendar.startOfDay(for: day)
        func ago(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
        func workoutsBetween(_ from: Int, _ to: Int) -> [Workout] {
            workouts.filter { $0.start >= ago(from) && $0.start < ago(to) }
        }
        func daysBetween(_ from: Int, _ to: Int) -> [HealthHistory.Day] {
            days.filter { $0.date >= ago(from) && $0.date < ago(to) }
        }

        var week: [String] = []
        let lastSeven = workoutsBetween(7, 0)
        if !lastSeven.isEmpty || workouts.contains(where: { $0.start < ago(7) }) {
            week.append(workoutLine(lastSeven))
        }
        let recent = daysBetween(7, 0), before = daysBetween(usualDays, 7)
        if let now = mean(recent.compactMap(\.restingHeartRate), minimumRecent),
           let usual = mean(before.compactMap(\.restingHeartRate), minimumUsual) {
            let change = (now - usual).rounded()
            let tail = abs(now - usual) < steadyBeats ? "about your usual"
                : "\(Int(abs(change))) \(change < 0 ? "below" : "above") your usual"
            week.append("Resting heart rate: \(Int(now.rounded())) bpm, \(tail).")
        }
        if let now = mean(recent.compactMap(\.sleepMin), minimumRecent),
           let usual = mean(before.compactMap(\.sleepMin), minimumUsual) {
            let change = now - usual
            let tail = abs(change) < steadySleepMinutes ? "about your usual"
                : "\(duration(abs(change))) \(change < 0 ? "below" : "above") your usual"
            week.append("Sleep: \(GuardrailCopy.sleepLabel(now)) a night, \(tail).")
        }
        if let now = mean(recent.compactMap(\.hrv), minimumRecent),
           let usual = mean(daysBetween(hrvUsualDays, 7).compactMap(\.hrv), minimumUsual) {
            week.append("Heart rate variability: \(Int(now.rounded())) ms, \(fractionTail(now, usual, "your usual")).")
        }

        var month: [String] = []
        let lastFour = workoutsBetween(28, 0), fourBefore = workoutsBetween(56, 28)
        // Compare with the 4 weeks before only when history reaches back over most of them.
        let hasEarlier = workouts.contains { $0.start < ago(comparedFromDays) }
        let hasAny = !lastFour.isEmpty || workouts.contains { $0.start < ago(28) }
        if hasAny {
            var line = workoutLine(lastFour).dropLast().description
            if hasEarlier {
                let (now, then) = (lastFour.count, fourBefore.count)
                line += now == then ? ", the same as the 4 weeks before"
                    : ", \(now > then ? "up" : "down") from \(then) the 4 weeks before"
            }
            month.append(line + ".")
        }
        let load = lastFour.reduce(0) { $0 + TrainingInsights.load($1) }
        let loadBefore = fourBefore.reduce(0) { $0 + TrainingInsights.load($1) }
        if hasEarlier, load > 0, loadBefore > 0 {
            month.append("Training load: \(fractionTail(load, loadBefore, "the 4 weeks before", steady: "steady on")).")
        }
        if let longest = lastFour.filter({ $0.activityType == "Running" }).max(by: { $0.minutes < $1.minutes }) {
            // A fixed pattern, so it reads the same on every OS version (see `Bedtime.time`).
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d"
            let date = formatter.string(from: longest.start)
            month.append("Longest run: \(duration(longest.minutes)), on \(date).")
        }
        if let range, range.daysCounted > 0 {
            let swaps = switch range.swaps {
            case 0: ""
            case 1: ", with 1 swap"
            default: ", with \(range.swaps) swaps"
            }
            month.append("In range \(range.daysInRange) of \(range.daysCounted) days\(swaps).")
        }
        return Trends(week: week, month: month)
    }

    // MARK: Words

    /// "4 workouts, 3h 10 in all." or "No workouts."
    static func workoutLine(_ workouts: [Workout]) -> String {
        guard !workouts.isEmpty else { return "No workouts." }
        let minutes = workouts.reduce(0) { $0 + $1.minutes }
        let noun = workouts.count == 1 ? "workout" : "workouts"
        return "\(workouts.count) \(noun), \(duration(minutes)) in all."
    }

    /// "45 min", or "3h 10" from an hour.
    static func duration(_ minutes: Double) -> String {
        let rounded = (minutes / 5).rounded() * 5
        return rounded < 60 ? "\(Int(rounded)) min" : GuardrailCopy.sleepLabel(rounded)
    }

    /// "12% above the 4 weeks before", "8% under your usual" or "about your usual".
    static func fractionTail(_ now: Double, _ usual: Double, _ what: String, steady: String = "about") -> String {
        let change = now / usual - 1
        guard abs(change) >= steadyFraction else { return "\(steady) \(what)" }
        return "\(Int((abs(change) * 100).rounded()))% \(change < 0 ? "below" : "above") \(what)"
    }

    private static func mean(_ values: [Double], _ minimum: Int) -> Double? {
        values.count >= minimum ? values.reduce(0, +) / Double(values.count) : nil
    }
}
