import Foundation
import Testing
@testable import Evergreen

/// A real person's week from their Apple Health history, what the phone sends
/// the planner, and the anonymous id. No HealthKit: workouts are built here.
struct HistoryPlanTests {
    static var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    /// Friday, Nov 20, 2026.
    static let storyDay = cal.date(from: DateComponents(year: 2026, month: 11, day: 20))!

    static func at(_ back: Int, _ hour: Int, _ minute: Int = 0, for minutes: Double, _ type: String = "Running") -> Workout {
        let day = cal.date(byAdding: .day, value: -back, to: storyDay)!
        let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return Workout(id: "w\(back)-\(hour)", activityType: type, start: start, end: start.addingTimeInterval(minutes * 60),
                       effort: nil, avgHeartRate: 150, source: .health, distanceKm: minutes / 6)
    }

    /// Four weeks of Tuesday 7 PM runs (40 min), Thursday 7:10 PM strength (35 min)
    /// and Sunday 9 AM long runs (80 min), plus one stray Wednesday walk.
    static let month: [Workout] = (0..<4).flatMap { week -> [Workout] in
        let base = week * 7
        return [at(base + 3, 19, for: 40), at(base + 1, 19, 10, for: 35, "FunctionalStrengthTraining"), at(base + 5, 9, for: 80)]
    } + [at(9, 12, for: 20, "Walking")]

    @Test func theWeekFollowsTheUsualDaysTimesAndKinds() throws {
        let week = HistoryPlan.week(Self.month, storyDay: Self.storyDay, calendar: Self.cal)
        let byDay = Dictionary(uniqueKeysWithValues: week.map { (Self.cal.component(.weekday, from: $0.day), $0.entry) })

        #expect(Set(byDay.keys) == [1, 3, 5])                       // Sunday, Tuesday, Thursday; not the one-off walk
        let tuesday = try #require(byDay[3])
        #expect(tuesday.activityType == "Running" && tuesday.startMinute == 19 * 60 && tuesday.minutes == 40)
        let thursday = try #require(byDay[5])
        #expect(thursday.focus == .strength && thursday.startMinute == 19 * 60 + 15)
        let sunday = try #require(byDay[1])
        #expect(sunday.focus == .long && sunday.minutes == 80 && sunday.startMinute == 9 * 60)
    }

    @Test func itemsAreDatedInTheNextSevenDaysWithStableIds() throws {
        let items = HistoryPlan.items(Self.month, storyDay: Self.storyDay, calendar: Self.cal)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.slot.start >= Self.storyDay && $0.slot.start < Self.storyDay.addingTimeInterval(7 * 86_400) })
        #expect(items.map(\.id).contains("plan-me-2026-11-22-running"))
        #expect(items == HistoryPlan.items(Self.month, storyDay: Self.storyDay, calendar: Self.cal))
    }

    @Test func aPlanMadeMidDaySkipsTodaysWorkoutThatAlreadyStarted() {
        // A Friday 6 PM run habit; the plan is made at 7 PM on Friday the story day.
        let fridays = (1...4).map { Self.at($0 * 7, 18, for: 45) }
        let evening = Self.cal.date(bySettingHour: 19, minute: 0, second: 0, of: Self.storyDay)!
        let morning = Self.cal.date(bySettingHour: 8, minute: 0, second: 0, of: Self.storyDay)!

        #expect(HistoryPlan.items(fridays, storyDay: Self.storyDay, calendar: Self.cal, madeAt: evening).isEmpty)
        #expect(HistoryPlan.items(fridays, storyDay: Self.storyDay, calendar: Self.cal, madeAt: morning).count == 1)
    }

    @Test func noPatternMeansAGentleStarterWeek() {
        let items = HistoryPlan.items([Self.at(2, 7, for: 30)], storyDay: Self.storyDay, calendar: Self.cal)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.slot.activityType == "Walking" && $0.slot.minutes == 30 })
        let insights = TrainingInsights(workouts: [], storyDay: Self.storyDay, calendar: Self.cal)
        #expect(HistoryPlan.reason(for: items[0], workouts: [], storyDay: Self.storyDay, calendar: Self.cal,
                                   insights: insights) == "A short walk to start while I learn your routine.")
    }

    @Test func reasonsCiteThePersonsOwnPattern() throws {
        let items = HistoryPlan.items(Self.month, storyDay: Self.storyDay, calendar: Self.cal)
        let insights = TrainingInsights(workouts: Self.month, storyDay: Self.storyDay, calendar: Self.cal)
        let long = try #require(items.first { $0.id == "plan-me-2026-11-22-running" })
        #expect(HistoryPlan.reason(for: long, workouts: Self.month, storyDay: Self.storyDay, calendar: Self.cal,
                                   insights: insights) == "Your long run: you usually go 80 min on Sundays.")
    }

    @Test func thePayloadCarriesLocalTimesAndDays() throws {
        let night = HealthHistory.Day(date: Self.storyDay.addingTimeInterval(-86_400), sleepMin: 452, restingHeartRate: 51.5)
        let payload = HistoryPayload(HealthHistory(workouts: [Self.at(3, 19, for: 40)], days: [night]), cal: Self.cal)

        let run = try #require(payload.workouts.first)
        #expect(run.start == "2026-11-17T19:00:00-08:00" && run.end == "2026-11-17T19:40:00-08:00")
        #expect(run.distanceKm == 6.667 && run.avgHeartRate == 150)
        #expect(payload.daily == [.init(date: "2026-11-19", sleepMin: 452, restingHeartRate: 51.5)])
        let json = String(decoding: try JSONEncoder.contract.encode(payload), as: UTF8.self)
        #expect(!json.contains("\"id\"") && !json.contains("source"))
    }

    @Test func theAnonymousIdHasTheHarnessShapeAndCarriesNoName() {
        let id = DeviceIdentity.id(secret: "test-secret")
        #expect(id.wholeMatch(of: /usr_[0-9a-f]{16}/) != nil)
        #expect(id == DeviceIdentity.id(secret: "test-secret"))
        #expect(id != DeviceIdentity.id(secret: "other-secret"))
    }
}
