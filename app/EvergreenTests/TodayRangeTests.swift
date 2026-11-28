import Foundation
import Testing
@testable import Evergreen

/// Today's range (TODOS item 3) on Apple Fitness's training load: effort ×
/// minutes, 7 days against 28. The ceiling, the floor, the effort word,
/// readiness, how hard the person rated their week, and the new in-range day.
@MainActor
struct TodayRangeTests {
    static let calendar = Fixture.calendar
    static let today = Fixture.storyDay

    /// A 50-minute workout every day for `days` days before today. The last 6
    /// days can carry their own effort.
    static func history(days: Int = 28, effort: Double = 5, lastSixEffort: Double? = nil) -> [Workout] {
        (1...days).map { back in
            let start = Fixture.at(7, dayOffset: -back)
            return Workout(id: "w\(back)", activityType: "Running", start: start, end: start.addingTimeInterval(50 * 60),
                           effort: back <= 6 ? (lastSixEffort ?? effort) : effort, avgHeartRate: nil, source: .health)
        }
    }

    static func range(_ workouts: [Workout], planned: Bool = true, bodyOff: Bool = false) -> TodayRange? {
        TodayRange.make(workouts: workouts, on: Fixture.at(7), planned: planned, bodyOff: bodyOff, calendar: calendar)
    }

    // MARK: Load

    @Test func loadIsEffortTimesMinutesSevenDaysAgainstTwentyEight() {
        // 28 days at effort 5; the last 7 at effort 7: (7×50×7/7) / (21×250 + 7×350)/28 = 350 / 275.
        var workouts = Self.history(effort: 5)
        for i in workouts.indices where workouts[i].start >= Fixture.at(0, dayOffset: -7) { workouts[i].effort = 7 }
        let insights = TrainingInsights(workouts: workouts, storyDay: Self.today, calendar: Self.calendar)
        #expect(abs(insights.loadChange - (350.0 / 275.0 - 1)) < 0.0001)
        #expect(insights.weekMinutes == 350)
    }

    @Test func theEffortIsTheRatingThenHeartRateThenModerate() {
        let start = Fixture.at(7, dayOffset: -1)
        func workout(_ effort: Double?, _ rate: Int?) -> Workout {
            Workout(id: "x", activityType: "Running", start: start, end: start.addingTimeInterval(60 * 10),
                    effort: effort, avgHeartRate: rate, source: .health)
        }
        #expect(TrainingInsights.load(workout(8, 120)) == 80)
        #expect(TrainingInsights.load(workout(nil, 165)) == 70)
        #expect(TrainingInsights.load(workout(nil, 120)) == 30)
        #expect(TrainingInsights.load(workout(nil, nil)) == 50)
    }

    // MARK: The range

    @Test func aSteadyWeek() throws {
        // Usual week 1750; last 6 days 1500; room 1.3×1750 − 1500 = 775 load = 155 min at effort 5.
        let range = try #require(Self.range(Self.history()))
        #expect(range.floor == 10)
        #expect(range.ceiling == 155)
        #expect(range.effort == .usual)
        #expect(range.line == "Today: 10–155 min, your usual effort.")
        #expect(range.reason == "Your 7-day training load is right at your 28-day load.")
    }

    @Test func aHardRatedWeekLeavesFewerMinutesThanAnEasyOne() throws {
        let hard = try #require(Self.range(Self.history(lastSixEffort: 8)))
        let easy = try #require(Self.range(Self.history(lastSixEffort: 3)))
        #expect(hard.ceiling < easy.ceiling)
        #expect(hard.effort == .easy)
        #expect(hard.reason.hasPrefix("Your 7-day training load is "))
        #expect(hard.reason.hasSuffix("% above your 28-day load."))
        #expect(easy.effort == .any)
    }

    @Test func readinessOffLowersTheCeilingAndAsksForEasy() throws {
        let range = try #require(Self.range(Self.history(), bodyOff: true))
        // 775 × 0.8 = 620 load = 124 min, down to 120.
        #expect(range.ceiling == 120)
        #expect(range.effort == .easy)
    }

    @Test func aRestDayHasNoFloor() throws {
        let range = try #require(Self.range(Self.history(), planned: false))
        #expect(range.line == "Today: up to 155 min, your usual effort.")
    }

    @Test func aWeekAlreadyOverLeavesTheFloor() throws {
        // The last 6 days at effort 10: no room left, but a planned day keeps its 10 minutes.
        let range = try #require(Self.range(Self.history(lastSixEffort: 10)))
        #expect(range.ceiling == 10)
        #expect(range.line == "Today: 10 min, easy effort.")
    }

    @Test func underTwoWeeksOfHistoryThereIsNoRange() {
        #expect(Self.range(Self.history(days: 10)) == nil)
        #expect(Self.range([]) == nil)
    }

    @Test func noSafetyWords() throws {
        let range = try #require(Self.range(Self.history(lastSixEffort: 8)))
        let flag = GuardrailFlag(kind: .load, planned: .minutes(100), suggested: .minutes(45), longest30: nil,
                                 keepEasy: false, injuryAdjusted: false)
        for text in [range.line, range.reason, GuardrailCopy.reason(flag)] {
            for banned in ["safe", "injur", "recover", "risk", "prevent"] {
                #expect(!text.lowercased().contains(banned), "\(banned) in \(text)")
            }
        }
        #expect(GuardrailCopy.reason(flag)
                == "100 min would put your 7-day training load more than 30% over your usual. 45 min keeps it in range.")
        #expect(AnalyticsEvent.flagShown(.load).properties == ["kind": "load"])
    }

    // MARK: On Today

    static func model() throws -> AppModel {
        let model = try NotifierActionTests.model()
        model.setClockMinutes(7 * 60)
        return model
    }

    @Test func jordanHasARangeToday() throws {
        let model = try Self.model()
        let range = try #require(model.todayRange)
        #expect(range.ceiling >= range.floor)
        #expect(range.line.hasPrefix("Today: "))
    }

    @Test func aRunTodayLongerThanTheRoomIsFlagged() throws {
        let model = try Self.model()
        let range = try #require(model.todayRange)
        let start = model.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: model.storyDay)!
        let minutes = Double(range.ceiling) * 2 + 60
        let run = PlannedRun(key: "runna|load", title: "Big day", calendarTitle: "Runna", start: start,
                             end: start.addingTimeInterval(minutes * 60), size: .minutes(minutes),
                             isHard: false, isAllDay: false)
        model.trainingRuns = [run]
        let flag = try #require(model.flag(for: run))
        #expect(flag.kind == .load || flag.kind == .spike)
        #expect(flag.suggested.value <= Double(max(range.ceiling, 20)))
    }

    @Test func goingOverTheCeilingIsOutOfRange() throws {
        let model = try Self.model()
        let today = model.now
        #expect(!model.wentOverRange(on: today))
        let start = model.calendar.date(bySettingHour: 6, minute: 0, second: 0, of: model.storyDay)!
        model.logWorkout(Workout(id: "huge", activityType: "Running", start: start, end: start.addingTimeInterval(400 * 60),
                                 effort: 9, avgHeartRate: nil, source: .demo))
        #expect(model.wentOverRange(on: today))
        let week = PainWeek.monday(of: today, calendar: model.calendar)
        let report = model.rangeReport(for: week)
        #expect(report.daysInRange < report.daysCounted)
    }
}
