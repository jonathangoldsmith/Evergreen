import Foundation

/// The brake (plan items 5 and 6), as one pure function over plain values so
/// every branch has a table test. Thresholds are provisional; the backtest
/// calibrates them.
enum GuardrailRule {
    /// A spike is more than this past the 30-day longest: +10%, or +5% after an injury.
    static let spikeRatio = 1.10
    static let injuredSpikeRatio = 1.05
    /// After an injury the spike suggestion is the longest minus 10%.
    static let injuredCapRatio = 0.90
    static let lookbackDays = 30
    static let injuryWindowMonths = 12
    /// Fewer comparable runs than this: no spike flags (back from a break).
    static let minimumComparable = 2
    /// The return-to-running limit: anything over this after an injury, with no recent runs.
    static let returnLimit: [RunUnit: Double] = [.minutes: 30, .km: 5]
    /// Suggestions never go below these.
    static let floor: [RunUnit: Double] = [.minutes: 20, .km: 3]
    /// "Long" for Sore and Tired: 60+ minutes or 10+ km.
    static let longThreshold: [RunUnit: Double] = [.minutes: 60, .km: 10]
    static let soreCut = 0.70
    static let tiredCut = 0.80
    /// A Sore or Tired cut smaller than this becomes "run it easy" instead.
    static let smallestCut = 0.10

    struct Context {
        /// Completed workouts; only runs count.
        var history: [Workout]
        /// The month of the most recent injury (onboarding, or a "Yes" pain answer).
        var injuryMonth: Date?
        /// This run's morning answer, if given.
        var check: MorningCheck?
        /// Planned runs in the 7 days from this run, for "the longest planned run this week".
        var upcoming: [PlannedRun]
        var calendar: Calendar
    }

    static func flag(for run: PlannedRun, _ context: Context) -> GuardrailFlag? {
        guard let planned = run.size else { return nil }
        let injured = isInjured(on: run.start, context)
        let candidates = [spike(run, planned, injured, context), feel(run, planned, injured, context)].compactMap(\.self)
        // One flag per run: the smaller suggestion wins; a spike wins a tie.
        return candidates.min { $0.suggested.value < $1.suggested.value }
    }

    // MARK: Spike

    private static func spike(_ run: PlannedRun, _ planned: RunSize, _ injured: Bool, _ context: Context) -> GuardrailFlag? {
        let comparable = comparableRuns(before: run.start, unit: planned.unit, context)
        guard comparable.count >= minimumComparable, let longest = comparable.max() else {
            // Back from a break after an injury: a return-to-running spike.
            guard injured, let limit = returnLimit[planned.unit], planned.value > limit else { return nil }
            return GuardrailFlag(kind: .returnSpike, planned: planned, suggested: RunSize(value: limit, unit: planned.unit),
                                 longest30: nil, keepEasy: false, injuryAdjusted: true)
        }
        let ratio = injured ? injuredSpikeRatio : spikeRatio
        guard planned.value > longest * ratio else { return nil }
        let cap = injured ? longest * injuredCapRatio : longest
        let suggested = withFloor(roundDown(cap, planned.unit), planned.unit)
        // A floor that lifts the suggestion to the planned size means no flag.
        guard suggested < planned.value else { return nil }
        return GuardrailFlag(kind: .spike, planned: planned, suggested: RunSize(value: suggested, unit: planned.unit),
                             longest30: RunSize(value: longest, unit: planned.unit), keepEasy: false, injuryAdjusted: injured)
    }

    /// The sizes of completed runs in the 30 days before the run's day, in the plan's unit.
    static func comparableRuns(before start: Date, unit: RunUnit, _ context: Context) -> [Double] {
        let day = context.calendar.startOfDay(for: start)
        guard let from = context.calendar.date(byAdding: .day, value: -lookbackDays, to: day) else { return [] }
        return context.history
            .filter { $0.activityType == "Running" && $0.start >= from && $0.start < day }
            .compactMap { unit == .km ? $0.distanceKm : $0.minutes }
            .filter { $0 > 0 }
    }

    static func isInjured(on date: Date, _ context: Context) -> Bool {
        guard let month = context.injuryMonth,
              let since = context.calendar.date(byAdding: .month, value: -injuryWindowMonths, to: date)
        else { return false }
        return month >= context.calendar.startOfDay(for: since) && month <= date
    }

    // MARK: Sore and Tired

    private static func feel(_ run: PlannedRun, _ planned: RunSize, _ injured: Bool, _ context: Context) -> GuardrailFlag? {
        let cut: Double
        switch context.check {
        case .sore? where isLong(run, planned, context):
            cut = soreCut
        case .tired? where isLong(run, planned, context) || run.isHard:
            cut = tiredCut
        default:
            return nil
        }
        let kind: GuardrailFlag.Kind = context.check == .sore ? .sore : .tired
        let suggested = withFloor(roundDown(planned.value * cut, planned.unit), planned.unit)
        if suggested > planned.value * (1 - smallestCut) {
            return GuardrailFlag(kind: kind, planned: planned, suggested: planned, longest30: nil,
                                 keepEasy: true, injuryAdjusted: injured)
        }
        return GuardrailFlag(kind: kind, planned: planned, suggested: RunSize(value: suggested, unit: planned.unit),
                             longest30: nil, keepEasy: false, injuryAdjusted: injured)
    }

    /// 60+ minutes, 10+ km, or the longest planned run in the next 7 days.
    static func isLong(_ run: PlannedRun, _ planned: RunSize, _ context: Context) -> Bool {
        if let threshold = longThreshold[planned.unit], planned.value >= threshold { return true }
        if !run.isAllDay, run.minutes >= (longThreshold[.minutes] ?? 60) { return true }
        guard let weekEnd = context.calendar.date(byAdding: .day, value: 7, to: run.start) else { return false }
        let week = context.upcoming.filter { $0.start >= context.calendar.startOfDay(for: run.start) && $0.start < weekEnd }
            .compactMap(\.size).filter { $0.unit == planned.unit }
        guard week.count > 1, let longest = week.map(\.value).max() else { return false }
        return planned.value >= longest
    }

    // MARK: Rounding

    /// Whole km down, or 5 minutes down, so a suggestion never exceeds its cap.
    static func roundDown(_ value: Double, _ unit: RunUnit) -> Double {
        switch unit {
        case .km: (value + 1e-9).rounded(.down)
        case .minutes: ((value + 1e-9) / 5).rounded(.down) * 5
        }
    }

    static func withFloor(_ value: Double, _ unit: RunUnit) -> Double {
        max(value, floor[unit] ?? 0)
    }
}
