import Foundation

/// Onboarding's backtest (plan item 4): the last year's runs checked by the
/// rule, a blind sample to ask about, and each answer sent as a
/// `backtest_answer` (R7). "Yes" days stay on the phone too (design decision 12).
extension AppModel {
    enum BacktestAnswer: String, CaseIterable, Sendable {
        case yes, no, dontKnow

        var label: String {
            switch self {
            case .yes: "Yes"
            case .no: "No"
            case .dontKnow: "Don't know"
            }
        }
    }

    private static let seedKey = "backtest_seed"
    private static let yesDaysKey = "backtest_yes_days"

    /// The sample's seed, kept so a restarted onboarding asks the same days.
    var backtestSeed: UInt64 {
        if let saved = UserDefaults.standard.string(forKey: Self.seedKey), let seed = UInt64(saved) { return seed }
        let seed = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(String(seed), forKey: Self.seedKey)
        return seed
    }

    /// Every checked day of the last year, or nil with too little history
    /// (or Health not allowed, which looks the same: design decision 6).
    func loadBacktest() async -> [Backtest.Day]? {
        let runs = await healthReader.runs(days: Backtest.lookbackDays, calendar: calendar)
        guard runs.count >= Backtest.minimumRuns else { return nil }
        return Backtest.days(runs, injuryMonth: profile.injuryMonth, now: Date(), calendar: calendar)
    }

    func answerBacktest(_ answer: BacktestAnswer, day: Backtest.Day) {
        upload(.backtestAnswer(answer.rawValue, day: day, seed: backtestSeed, at: Date(), calendar: calendar), ownAnswer: true)
        if answer == .yes {
            var days = UserDefaults.standard.array(forKey: Self.yesDaysKey) as? [Double] ?? []
            days.append(day.date.timeIntervalSince1970)
            UserDefaults.standard.set(days, forKey: Self.yesDaysKey)
        }
    }

    func finishBacktest(answered: Int) {
        track(.backtestCompleted(answered: answered))
    }
}
