import Foundation
import Testing
@testable import Evergreen

/// Trends as sentences (TODOS item 5): each line, its steady band, what's
/// left out without enough data, and the wording rules.
@MainActor
struct TrendsTests {
    static let calendar = Fixture.calendar
    static let today = Fixture.storyDay

    static func workout(_ back: Int, minutes: Double = 50, type: String = "Running", effort: Double = 5) -> Workout {
        let start = Fixture.at(7, dayOffset: -back)
        return Workout(id: "w\(back)-\(type)", activityType: type, start: start, end: start.addingTimeInterval(minutes * 60),
                       effort: effort, avgHeartRate: nil, source: .health)
    }

    static func day(_ back: Int, sleep: Double? = nil, resting: Double? = nil, hrv: Double? = nil) -> HealthHistory.Day {
        HealthHistory.Day(date: calendar.date(byAdding: .day, value: -back, to: today)!, sleepMin: sleep,
                          restingHeartRate: resting, hrv: hrv)
    }

    static func make(_ workouts: [Workout] = [], days: [HealthHistory.Day] = [], range: Trends.Range? = nil) -> Trends {
        Trends.make(workouts: workouts, days: days, range: range, on: Fixture.at(12), calendar: calendar)
    }

    // MARK: Workouts and load

    @Test func theLastSevenDaysCountWorkoutsAndTime() {
        let trends = Self.make([Self.workout(1), Self.workout(3, minutes: 100), Self.workout(9)])
        #expect(trends.week.first == "2 workouts, 2h 30 in all.")
    }

    @Test func aQuietWeekAfterEarlierWorkoutsSaysSo() {
        #expect(Self.make([Self.workout(10)]).week.first == "No workouts.")
    }

    @Test func theLastFourWeeksCompareWithTheFourBefore() {
        let recent = (1...6).map { Self.workout($0 * 4) }            // 6 in the last 28 days
        let earlier = [35, 42, 50, 54].map { Self.workout($0) }        // 4 in the 28 before
        let trends = Self.make(recent + earlier)
        #expect(trends.month.first == "6 workouts, 5h in all, up from 4 the 4 weeks before.")
        #expect(trends.month.contains("Training load: 50% above the 4 weeks before."))
    }

    @Test func aSteadyLoadSaysSteady() {
        let recent = (1...4).map { Self.workout($0 * 5) }
        let earlier = [30, 37, 44, 51].map { Self.workout($0) }
        let trends = Self.make(recent + earlier)
        #expect(trends.month.first == "4 workouts, 3h 20 in all, the same as the 4 weeks before.")
        #expect(trends.month.contains("Training load: steady on the 4 weeks before."))
    }

    @Test func withoutEarlierHistoryThereIsNoComparison() {
        let trends = Self.make([Self.workout(2), Self.workout(5)])
        #expect(trends.month.first == "2 workouts, 1h 40 in all.")
        #expect(!trends.month.contains { $0.hasPrefix("Training load") })
    }

    @Test func aMonthOfHistoryIsntComparedWithAPartialMonthBefore() {
        // History starts 30 days ago: the 4 weeks before hold one workout, so no "up from 1".
        let trends = Self.make([Self.workout(2), Self.workout(30)])
        #expect(trends.month.first == "1 workout, 50 min in all.")
        #expect(!trends.month.contains { $0.hasPrefix("Training load") })
    }

    @Test func theLongestRunHasItsDate() {
        let trends = Self.make([Self.workout(2), Self.workout(4, minutes: 100), Self.workout(6, minutes: 120, type: "Cycling")])
        #expect(trends.month.contains("Longest run: 1h 40, on Nov 15."))
    }

    @Test func daysInRangeOverFourWeeks() {
        #expect(Self.make(range: .init(daysInRange: 24, daysCounted: 25, swaps: 2)).month == ["In range 24 of 25 days, with 2 swaps."])
        #expect(Self.make(range: .init(daysInRange: 20, daysCounted: 20, swaps: 1)).month == ["In range 20 of 20 days, with 1 swap."])
        #expect(Self.make(range: .init(daysInRange: 9, daysCounted: 9, swaps: 0)).month == ["In range 9 of 9 days."])
        #expect(Self.make(range: .init(daysInRange: 0, daysCounted: 0, swaps: 0)).isEmpty)
    }

    // MARK: Body readings

    @Test func restingHeartRateAgainstTheUsual() {
        let usual = (8...28).map { Self.day($0, resting: 49) }
        let lower = (1...7).map { Self.day($0, resting: 46) }
        #expect(Self.make(days: usual + lower).week == ["Resting heart rate: 46 bpm, 3 below your usual."])
        let steady = (1...7).map { Self.day($0, resting: 50) }
        #expect(Self.make(days: usual + steady).week == ["Resting heart rate: 50 bpm, about your usual."])
    }

    @Test func sleepAgainstTheUsual() {
        let usual = (8...28).map { Self.day($0, sleep: 450) }
        let shorter = (1...7).map { Self.day($0, sleep: 425) }
        #expect(Self.make(days: usual + shorter).week == ["Sleep: 7h 05 a night, 25 min below your usual."])
        let steady = (1...7).map { Self.day($0, sleep: 440) }
        #expect(Self.make(days: usual + steady).week == ["Sleep: 7h 20 a night, about your usual."])
    }

    @Test func hrvAgainstSixtyDays() {
        let usual = (8...60).map { Self.day($0, hrv: 60) }
        let higher = (1...7).map { Self.day($0, hrv: 66) }
        #expect(Self.make(days: usual + higher).week == ["Heart rate variability: 66 ms, 10% above your usual."])
    }

    @Test func tooFewReadingsAreLeftOut() {
        let usual = (8...13).map { Self.day($0, sleep: 450, resting: 49, hrv: 60) }   // 6 usual days
        let recent = (1...7).map { Self.day($0, sleep: 400, resting: 55, hrv: 50) }
        #expect(Self.make(days: usual + recent).week.isEmpty)
        let fullUsual = (8...28).map { Self.day($0, resting: 49) }
        let twoRecent = (1...2).map { Self.day($0, resting: 55) }
        #expect(Self.make(days: fullUsual + twoRecent).week.isEmpty)
    }

    @Test func nothingAtAllIsEmpty() {
        #expect(Self.make().isEmpty)
    }

    // MARK: Words

    @Test func noSafetyWordsOrScores() {
        let usual = (8...60).map { Self.day($0, sleep: $0 <= 28 ? 450 : nil, resting: $0 <= 28 ? 49 : nil, hrv: 60) }
        let recent = (1...7).map { Self.day($0, sleep: 400, resting: 55, hrv: 50) }
        let workouts = (1...26).map { Self.workout($0 * 2) }
        let trends = Self.make(workouts, days: usual + recent, range: .init(daysInRange: 20, daysCounted: 22, swaps: 1))
        #expect(trends.week.count == 4 && trends.month.count == 4)
        for line in trends.week + trends.month {
            for banned in ["safe", "injur", "recover", "risk", "prevent", "score", "good", "bad"] {
                #expect(!line.lowercased().contains(banned), "\(banned) in \(line)")
            }
        }
    }

    // MARK: The demo

    @Test func jordansDemoTrendsReadAsSentences() throws {
        let model = try NotifierActionTests.model()
        model.setClockMinutes(12 * 60)
        model.showTrendsDemo()
        #expect(model.showsTrends)
        let trends = model.trends
        #expect(trends.week.contains("Resting heart rate: 46 bpm, 3 below your usual."))
        #expect(trends.week.contains { $0.hasPrefix("Sleep: ") && $0.hasSuffix("below your usual.") })
        #expect(trends.week.contains { $0.hasPrefix("Heart rate variability: ") })
        #expect(trends.month.contains { $0.hasPrefix("Longest run: ") })
        // Jordan's mock history is about a month, so nothing is compared with the month before.
        #expect(!trends.month.contains { $0.contains("the 4 weeks before") })
    }
}
