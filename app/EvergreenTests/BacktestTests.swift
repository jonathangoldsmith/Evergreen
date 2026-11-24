import Foundation
import Testing
@testable import Evergreen

/// The onboarding backtest (plan item 4, design decision 5, R7).
struct BacktestTests {
    static let cal = Fixture.calendar
    static let now = Fixture.at(12)

    static func run(_ daysBack: Int, km: Double) -> Workout {
        let start = cal.date(byAdding: .day, value: -daysBack, to: Fixture.at(8))!
        return Workout(id: "r\(daysBack)", activityType: "Running", start: start, end: start.addingTimeInterval(km * 360),
                       effort: nil, avgHeartRate: nil, source: .health, distanceKm: km)
    }

    /// A steady 8 km every 4 days for a year, with two big jumps.
    static let year: [Workout] = stride(from: 360, through: 4, by: -4).map { back in
        switch back {
        case 200: run(back, km: 16)
        case 100: run(back, km: 14)
        default: run(back, km: 8)
        }
    }

    @Test func bigJumpsAreFlaggedAndSteadyRunsAreNot() {
        let days = Backtest.days(Self.year, injuryMonth: nil, now: Self.now, calendar: Self.cal)
        let flagged = days.filter(\.flagged)
        #expect(flagged.count == 2)
        #expect(flagged.map(\.jumpPercent) == [100, 75])
        #expect(days.count == Self.year.count)
    }

    @Test func anInjuryTightensTheRuleOnlyAfterIt() {
        // 8.7 km is 8.75% past the 8 km longest: under +10%, but over +5% after an injury.
        let history = Self.year + [Self.run(50, km: 8.7)]
        let injury = Self.cal.date(byAdding: .day, value: -60, to: Self.now)!
        let before = Backtest.days(history, injuryMonth: nil, now: Self.now, calendar: Self.cal)
        let after = Backtest.days(history, injuryMonth: injury, now: Self.now, calendar: Self.cal)
        #expect(before.first { $0.size == .km(8.7) }?.flagged == false)
        #expect(after.first { $0.size == .km(8.7) }?.flagged == true)
    }

    @Test func theSampleIsAtMostFourOfEachAndTheSameForTheSameSeed() {
        let days = Backtest.days(Self.year, injuryMonth: nil, now: Self.now, calendar: Self.cal)
        let sample = Backtest.sample(days, seed: 42)
        #expect(sample.count == 6)                                  // 2 flagged + 4 controls
        #expect(sample.filter(\.flagged).count == 2)
        #expect(sample == Backtest.sample(days, seed: 42))
        #expect(Set(sample).count == sample.count)
    }

    @Test func flaggedAndControlDaysAreInterleaved() {
        let days = Backtest.days(Self.year, injuryMonth: nil, now: Self.now, calendar: Self.cal)
        let firstTwo = Backtest.sample(days, seed: 7).prefix(2)
        #expect(firstTwo.filter(\.flagged).count == 1)
    }

    @Test func jumpsUploadRoundedToFive() {
        let day = Backtest.Day(date: Self.now, size: .km(18), longest30: .km(13), flagged: true)
        #expect(day.jumpPercent == 38 && day.jumpPercentRounded == 40)
        let small = Backtest.Day(date: Self.now, size: .km(8), longest30: .km(9), flagged: false)
        #expect(small.jumpPercent == -11 && small.jumpPercentRounded == -10)
    }

    @Test func runsOlderThanAYearAreNotChecked() {
        let days = Backtest.days([Self.run(380, km: 8), Self.run(370, km: 8)], injuryMonth: nil, now: Self.now, calendar: Self.cal)
        #expect(days.isEmpty)
    }
}
