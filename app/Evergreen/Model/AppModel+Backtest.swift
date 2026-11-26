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

    /// The sample's seed, kept so a restarted onboarding asks the same days.
    var backtestSeed: UInt64 {
        if let saved = UserDefaults.standard.string(forKey: Self.seedKey), let seed = UInt64(saved) { return seed }
        let seed = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(String(seed), forKey: Self.seedKey)
        return seed
    }

    /// Every checked day of the last year, or nil with too little history
    /// (or Health not allowed, which looks the same: design decision 6).
    /// A Health that doesn't answer within 10 seconds counts as no history, so
    /// onboarding can't hang on "Checking your last year…".
    func loadBacktest() async -> [Backtest.Day]? {
        let reader = healthReader, calendar = calendar
        let runs = await value(within: .seconds(10), or: []) {
            await reader.runs(days: Backtest.lookbackDays, calendar: calendar)
        }
        guard runs.count >= Backtest.minimumRuns else { return nil }
        return Backtest.days(runs, injuryMonth: profile.injuryMonth, now: Date(), calendar: calendar)
    }

    func answerBacktest(_ answer: BacktestAnswer, day: Backtest.Day) {
        upload(.backtestAnswer(answer.rawValue, day: day, seed: backtestSeed, at: Date(), calendar: calendar), ownAnswer: true)
        if answer == .yes, let jump = day.jumpPercent {
            let line = "\(day.date.timeIntervalSince1970):\(jump)"
            profile.hurtAfterJumpText = (profile.hurtAfterJumpText.split(separator: "\n").map(String.init) + [line])
                .joined(separator: "\n")
            try? context.save()
        }
    }

    /// "You were hurt after a jump like this in August": the latest backtest
    /// "Yes" day whose jump was this size or smaller (design decision 12).
    func hurtAfterJumpMonth(for flag: GuardrailFlag) -> String? {
        guard flag.kind == .spike, let jump = flag.jumpPercent else { return nil }
        return profile.hurtAfterJumps.filter { $0.jumpPercent > 0 && $0.jumpPercent <= jump }
            .max { $0.date < $1.date }
            .map { $0.date.formatted(.dateTime.month(.wide)) }
    }

    func finishBacktest(answered: Int) {
        track(.backtestCompleted(answered: answered))
    }
}
