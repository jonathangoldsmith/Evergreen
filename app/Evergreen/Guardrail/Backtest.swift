import Foundation

/// Onboarding's check of the last year (plan item 4, design decisions 5 and
/// 6, eng re-run R7): which past runs the spike rule would have flagged, and
/// a blind sample of flagged and unflagged days to ask about.
enum Backtest {
    static let lookbackDays = 395          // 365 to check, plus 30 for the first lookback
    static let checkedDays = 365
    static let minimumRuns = 20
    static let perGroup = 4

    struct Day: Hashable, Sendable, Identifiable {
        var date: Date
        var size: RunSize
        /// The longest comparable run in the 30 days before; nil with fewer than 2.
        var longest30: RunSize?
        var flagged: Bool
        var id: Date { date }

        /// How far past the 30-day longest, in percent; nil without a longest.
        var jumpPercent: Int? {
            guard let longest30, longest30.value > 0 else { return nil }
            return Int(((size.value / longest30.value - 1) * 100).rounded())
        }

        /// Rounded to 5 for upload (R7): the exact jump could identify a run.
        var jumpPercentRounded: Int { ((jumpPercent ?? 0) + 2).quotientRounded5 }
    }

    /// Every run in the last year, each checked as if it had been planned:
    /// distance when it has one, otherwise duration, against the 30 days
    /// before it. The tighter threshold applies within 12 months after the
    /// reported injury month.
    static func days(_ workouts: [Workout], injuryMonth: Date?, now: Date, calendar: Calendar) -> [Day] {
        let runs = workouts.filter { $0.activityType == "Running" && $0.minutes >= 5 }
        let start = calendar.date(byAdding: .day, value: -checkedDays, to: calendar.startOfDay(for: now)) ?? now
        return runs.filter { $0.start >= start && $0.start < now }.map { run in
            let size: RunSize = run.distanceKm.map(RunSize.km) ?? .minutes(run.minutes)
            let planned = PlannedRun(key: run.id, title: "", calendarTitle: "", start: run.start, end: run.end,
                                     size: size, isHard: false, isAllDay: false)
            let context = GuardrailRule.Context(history: runs, injuryMonth: injuredBefore(run.start, injuryMonth),
                                                check: nil, upcoming: [], calendar: calendar)
            let comparable = GuardrailRule.comparableRuns(before: run.start, unit: size.unit, context)
            let longest = comparable.count >= GuardrailRule.minimumComparable ? comparable.max() : nil
            let flag = GuardrailRule.flag(for: planned, context)
            return Day(date: run.start, size: size, longest30: longest.map { RunSize(value: $0, unit: size.unit) },
                       flagged: flag?.kind == .spike)
        }
        .sorted { $0.date < $1.date }
    }

    /// The injury only counts for runs after it happened.
    private static func injuredBefore(_ date: Date, _ month: Date?) -> Date? {
        guard let month, month <= date else { return nil }
        return month
    }

    /// Up to 8 questions: at most 4 flagged days and 4 unflagged, chosen with
    /// `seed` so a restarted onboarding asks the same days, and interleaved so
    /// "Skip the rest" keeps the mix balanced (outside voice #10).
    static func sample(_ days: [Day], seed: UInt64) -> [Day] {
        var rng = SeededGenerator(seed: seed)
        let flagged = Array(days.filter(\.flagged).shuffled(using: &rng).prefix(perGroup))
        let controls = Array(days.filter { !$0.flagged }.shuffled(using: &rng).prefix(perGroup))
        var mixed: [Day] = []
        for index in 0..<max(flagged.count, controls.count) {
            let pair = [index < flagged.count ? flagged[index] : nil, index < controls.count ? controls[index] : nil]
            mixed += (rng.next() % 2 == 0 ? pair : pair.reversed()).compactMap(\.self)
        }
        return mixed
    }
}

private extension Int {
    /// Down to a multiple of 5 (call with +2 to round to the nearest).
    var quotientRounded5: Int { Int((Double(self) / 5).rounded(.down)) * 5 }
}
