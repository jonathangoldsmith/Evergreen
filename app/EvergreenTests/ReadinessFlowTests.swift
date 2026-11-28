import Foundation
import Testing
@testable import Evergreen

/// Readiness on Today (TODOS item 2): this morning's readings shorten today's
/// long run before the morning answer, the answer wins once given, and other
/// days' runs never use this morning's readings.
@MainActor
struct ReadinessFlowTests {
    static func model(clock: Int = 7 * 60) throws -> AppModel {
        let model = try NotifierActionTests.model()
        model.setClockMinutes(clock)
        model.demoHealthDays = AppModel.roughNightDays(storyDay: model.storyDay, calendar: model.calendar)
        return model
    }

    static func longRun(_ model: AppModel, dayOffset: Int = 0) -> PlannedRun {
        let day = model.calendar.date(byAdding: .day, value: dayOffset, to: model.storyDay)!
        let start = model.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
        return PlannedRun(key: "runna|readiness|\(dayOffset)", title: "Long run 1h 40", calendarTitle: "Runna",
                          start: start, end: start.addingTimeInterval(100 * 60), size: .minutes(100),
                          isHard: false, isAllDay: false)
    }

    @Test func theRoughNightDaysAreOffOnRestingHeartRateAndSleep() throws {
        let model = try Self.model()
        let signal = try #require(model.bodySignal(for: Self.longRun(model)))
        #expect(signal.isOff)
        #expect(signal.off.map(\.reading) == [.restingHeartRate, .sleep])
    }

    @Test func todaysLongRunIsShortenedBeforeAnyAnswer() throws {
        let model = try Self.model()
        let run = Self.longRun(model)
        model.trainingRuns = [run]
        let flag = try #require(model.flag(for: run))
        #expect(flag.kind == .body)
        #expect(flag.suggested == .minutes(80))
        #expect(flag.body?.isOff == true)
        #expect(GuardrailCopy.reason(flag).hasPrefix("Your resting heart rate is 6 bpm above your usual and you slept 5h 40"))
    }

    @Test func freshWins() throws {
        let model = try Self.model()
        let run = Self.longRun(model)
        model.trainingRuns = [run]
        model.answerMorningCheck(run, .fresh)
        #expect(model.flag(for: run) == nil)
    }

    @Test func tiredGivesTheTiredFlag() throws {
        let model = try Self.model()
        let run = Self.longRun(model)
        model.trainingRuns = [run]
        model.answerMorningCheck(run, .tired)
        #expect(model.flag(for: run)?.kind == .tired)
    }

    @Test func tomorrowsRunDoesntUseThisMorning() throws {
        let model = try Self.model()
        let run = Self.longRun(model, dayOffset: 1)
        model.trainingRuns = [run]
        #expect(model.bodySignal(for: run) == nil)
        #expect(model.flag(for: run) == nil)
    }

    @Test func withoutReadingsNothingChanges() throws {
        let model = try Self.model()
        model.demoHealthDays = []
        let run = Self.longRun(model)
        model.trainingRuns = [run]
        #expect(model.flag(for: run) == nil)
    }

    @Test func acceptingRecordsTheBodyKind() throws {
        let model = try Self.model()
        let run = Self.longRun(model)
        model.trainingRuns = [run]
        let flag = try #require(model.flag(for: run))
        model.acceptSwap(run, flag: flag)
        #expect(model.decisions.map(\.flagKind) == [.body])
        #expect(model.decisions.first?.suggested == .minutes(80))
    }

    @Test func thePlannerStillGetsOnlySleepAndRestingHeartRateDays() throws {
        var history = HealthHistory()
        history.days = [
            .init(date: Fixture.at(0), sleepMin: 450, restingHeartRate: 49, hrv: 62),
            .init(date: Fixture.at(0, dayOffset: -40), sleepMin: nil, restingHeartRate: nil, hrv: 60),
        ]
        let payload = HistoryPayload(history, cal: Fixture.calendar)
        #expect(payload.daily.count == 1)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        #expect(!json.contains("hrv"))
    }
}
