import Foundation

/// Readiness (TODOS "Readiness, range, sleep and widgets", item 2): this
/// morning's Apple Health readings against the person's own normal. One pure
/// function over plain values, like the brake's rule, so every branch has a
/// test. Thresholds are provisional; the backtest calibrates them.
///
/// The morning check stays the main signal (self-report tracked training
/// response better than heart-rate measures in Saw et al., BJSM 2016), so the
/// rule only uses this when the person hasn't answered. Wellness wording:
/// it says which readings are off, never that a run is or isn't safe.
struct BodySignal: Codable, Hashable, Sendable {
    enum Reading: String, Codable, Hashable, Sendable { case restingHeartRate, hrv, sleep }

    /// One reading away from the person's usual.
    struct Off: Codable, Hashable, Sendable {
        var reading: Reading
        /// This morning's value: bpm, ms, or minutes asleep.
        var now: Double
        var usual: Double
    }

    var off: [Off]

    /// Resting heart rate this many bpm or more over the usual.
    static let restingRise = 5.0
    /// HRV's 7-day average this fraction or more under the usual.
    static let hrvDrop = 0.10
    /// Last night this many minutes or more under the usual.
    static let sleepShortMinutes = 60.0
    /// Two readings off before it counts: one alone is too noisy to act on.
    static let offNeeded = 2
    /// The usual for resting heart rate and sleep: the 28 days before.
    static let usualDays = 28
    /// HRV: the last 7 days against the days before them, back to 60.
    static let hrvRecentDays = 7
    static let hrvUsualDays = 60
    /// Readings needed: at least half the usual window, and 3 recent HRV days.
    static let minimumUsual = 14
    static let minimumRecentHRV = 3

    var isOff: Bool { off.count >= Self.offNeeded }

    /// This morning's signal for `day`, from the days Evergreen read. Readings
    /// without enough history to know the usual are left out.
    static func read(_ days: [HealthHistory.Day], on day: Date, calendar: Calendar) -> BodySignal {
        let today = calendar.startOfDay(for: day)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
        func window(_ from: Int, _ to: Int) -> [HealthHistory.Day] {
            // Days from `from` days ago up to, not including, `to` days ago.
            days.filter { $0.date >= daysAgo(from) && $0.date < daysAgo(to) }
        }
        let todays = days.first { calendar.isDate($0.date, inSameDayAs: today) }
        var off: [Off] = []

        let usualDays = window(usualDays, 0)
        if let now = todays?.restingHeartRate, let usual = mean(usualDays.compactMap(\.restingHeartRate)),
           now >= usual + restingRise {
            off.append(Off(reading: .restingHeartRate, now: now, usual: usual))
        }
        if let now = todays?.sleepMin, let usual = mean(usualDays.compactMap(\.sleepMin)),
           now <= usual - sleepShortMinutes {
            off.append(Off(reading: .sleep, now: now, usual: usual))
        }
        // The last 7 days, today included, against the days before them back to 60.
        if let now = mean(window(hrvRecentDays - 1, -1).compactMap(\.hrv), minimum: minimumRecentHRV),
           let usual = mean(window(hrvUsualDays, hrvRecentDays - 1).compactMap(\.hrv)),
           now <= usual * (1 - hrvDrop) {
            off.append(Off(reading: .hrv, now: now, usual: usual))
        }
        return BodySignal(off: off)
    }

    private static func mean(_ values: [Double], minimum: Int = minimumUsual) -> Double? {
        values.count >= minimum ? values.reduce(0, +) / Double(values.count) : nil
    }
}
