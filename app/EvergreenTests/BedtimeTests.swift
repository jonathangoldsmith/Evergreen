import Foundation
import Testing
@testable import Evergreen

/// Sleep the agent defends (TODOS item 4): the bedtime before a long or hard
/// morning run, its words, the caps that keep it from nagging, and the
/// notification budget it joins.
@MainActor
struct BedtimeTests {
    static let calendar = Fixture.calendar

    /// A run tomorrow (Friday 20 November) at `hour`.
    static func run(_ title: String = "Long run 1h 40", hour: Int = 7, minute: Int = 0, dayOffset: Int = 1,
                    minutes: Double = 100, size: RunSize? = .minutes(100), hard: Bool = false) -> PlannedRun {
        let start = Fixture.at(hour, minute, dayOffset: dayOffset)
        return PlannedRun(key: "runna|\(dayOffset)|\(hour)|\(title)", title: title, calendarTitle: "Runna", start: start,
                          end: start.addingTimeInterval(minutes * 60), size: size, isHard: hard, isAllDay: false)
    }

    static func plan(_ runs: [PlannedRun], usual: Double? = 450) -> [Bedtime] {
        Bedtime.plan(runs: runs, usualSleep: usual, calendar: calendar)
    }

    static func clock(_ date: Date) -> String { Bedtime.time(date, calendar, amPM: false) }

    // MARK: The time

    @Test func aSevenAMLongRunMeansLightsOutAtTenThirty() throws {
        let bedtime = try #require(Self.plan([Self.run()]).first)
        #expect(bedtime.why == .long)
        #expect(Self.clock(bedtime.wake) == "6:00")
        #expect(Self.clock(bedtime.lightsOut) == "10:30")
        #expect(bedtime.lightsOut == Fixture.at(22, 30))
        #expect(bedtime.fireAt == Fixture.at(21, 30))
        #expect(bedtime.line(calendar: Self.calendar) == "Lights out by 10:30 for tomorrow’s long run.")
        #expect(bedtime.reason(calendar: Self.calendar) == "That leaves your usual 7h 30 of sleep before a 6:00 wake-up.")
        let note = bedtime.note(calendar: Self.calendar)
        #expect(note.title == "Lights out by 10:30")
        #expect(note.body == "Tomorrow’s long run is at 7:00 AM. That leaves a full night before a 6:00 wake-up.")
    }

    @Test func itRoundsToAQuarterHourEarlier() throws {
        // 7:00 run, 7h 20 usual: 22:40 rounds down to 22:30.
        let bedtime = try #require(Self.plan([Self.run()], usual: 440).first)
        #expect(bedtime.lightsOut == Fixture.at(22, 30))
    }

    @Test func withoutEnoughNightsItPlansSevenAndAHalfHours() throws {
        let bedtime = try #require(Self.plan([Self.run()], usual: nil).first)
        #expect(bedtime.lightsOut == Fixture.at(22, 30))
        #expect(bedtime.reason(calendar: Self.calendar) == "That leaves 7h 30 of sleep before a 6:00 wake-up.")
    }

    @Test func someoneWhoUsuallySleepsSixGetsSevenNotTheirUsual() throws {
        let bedtime = try #require(Self.plan([Self.run()], usual: 360).first)
        #expect(bedtime.lightsOut == Fixture.at(23))
        #expect(bedtime.reason(calendar: Self.calendar) == "That leaves 7h of sleep before a 6:00 wake-up.")
    }

    @Test func anEarlyRunIsNeverBeforeNinePM() throws {
        // 5:00 run: up at 4:00, 7h 30 would be 8:30 PM.
        let bedtime = try #require(Self.plan([Self.run(hour: 5)]).first)
        #expect(bedtime.lightsOut == Fixture.at(21))
        #expect(bedtime.fireAt == Fixture.at(20))
        #expect(bedtime.isShort)
        #expect(bedtime.reason(calendar: Self.calendar) == "That leaves 7h of sleep before a 4:00 wake-up.")
    }

    @Test func aLateMorningOrEveningRunNeedsNoNudge() {
        #expect(Self.plan([Self.run(hour: 10)]).isEmpty)
        #expect(Self.plan([Self.run(hour: 18)]).isEmpty)
    }

    @Test func onlyLongOrHardRuns() throws {
        let easy = Self.run("Easy 40 min", minutes: 40, size: .minutes(40))
        #expect(Self.plan([easy]).isEmpty)
        let tempo = Self.run("Tempo 45 min", minutes: 45, size: .minutes(45), hard: true)
        let bedtime = try #require(Self.plan([tempo]).first)
        #expect(bedtime.why == .hard)
        #expect(bedtime.line(calendar: Self.calendar) == "Lights out by 10:30 for tomorrow’s hard workout.")
        var allDay = Self.run()
        allDay.isAllDay = true
        #expect(Self.plan([allDay]).isEmpty)
    }

    @Test func aKilometreLongRunCounts() throws {
        let bedtime = try #require(Self.plan([Self.run("Long run 18 km", size: .km(18))]).first)
        #expect(bedtime.why == .long)
    }

    // MARK: Not nagging

    @Test func oneANightForTheEarliestRun() throws {
        let early = Self.run("Long run 1h 40", hour: 6)
        let later = Self.run("Tempo 45 min", hour: 6, minute: 30, minutes: 45, size: .minutes(45), hard: true)
        let bedtimes = Self.plan([later, early])
        #expect(bedtimes.count == 1)
        #expect(bedtimes.first?.run == early)
    }

    @Test func atMostTwoAWeekTheLongRunsFirst() {
        // Monday 23 to Sunday 29 November: three hard mornings and a long Sunday.
        let tuesday = Self.run("Tempo 50 min", dayOffset: 5, minutes: 50, size: .minutes(50), hard: true)
        let wednesday = Self.run("Intervals 45 min", dayOffset: 6, minutes: 45, size: .minutes(45), hard: true)
        let thursday = Self.run("Tempo 40 min", dayOffset: 7, minutes: 40, size: .minutes(40), hard: true)
        let sunday = Self.run("Long run 2h", dayOffset: 10, minutes: 120, size: .minutes(120))
        let bedtimes = Self.plan([tuesday, wednesday, thursday, sunday])
        #expect(bedtimes.count == 2)
        #expect(Set(bedtimes.map(\.run)) == [sunday, tuesday])
    }

    @Test func theUsualIsTheTwentyEightNightsBefore() {
        let today = Self.calendar.startOfDay(for: Fixture.storyDay)
        func night(_ back: Int, _ minutes: Double) -> HealthHistory.Day {
            HealthHistory.Day(date: Self.calendar.date(byAdding: .day, value: -back, to: today)!, sleepMin: minutes,
                              restingHeartRate: nil)
        }
        let six = (1...6).map { night($0, 420) }
        #expect(Bedtime.usualSleep(six, before: Fixture.storyDay, calendar: Self.calendar) == nil)
        let days = (1...7).map { night($0, 420) } + [night(10, 500), night(40, 100), night(0, 200)]
        #expect(Bedtime.usualSleep(days, before: Fixture.storyDay, calendar: Self.calendar) == 430)
    }

    @Test func todayShowsItFromSixPMTheEveningBefore() throws {
        let bedtime = try #require(Self.plan([Self.run()]).first)
        #expect(!bedtime.shows(at: Fixture.at(17, 59), calendar: Self.calendar))
        #expect(bedtime.shows(at: Fixture.at(20, 30), calendar: Self.calendar))
        #expect(!bedtime.shows(at: Fixture.at(0, 30, dayOffset: 1), calendar: Self.calendar))
    }

    @Test func noSafetyWordsAndNoSleepNumbersOnTheLockScreen() throws {
        for bedtime in Self.plan([Self.run()]) + Self.plan([Self.run(hour: 5)], usual: nil) {
            let note = bedtime.note(calendar: Self.calendar)
            for text in [bedtime.line(calendar: Self.calendar), bedtime.reason(calendar: Self.calendar), note.title, note.body] {
                for banned in ["safe", "injur", "recover", "risk", "prevent"] {
                    #expect(!text.lowercased().contains(banned), "\(banned) in \(text)")
                }
            }
            #expect(!note.body.contains("7h"))
        }
    }

    // MARK: The notification budget

    @Test func theNoteJoinsTheScheduleWithItsOwnId() throws {
        let run = Self.run()
        let notes = GuardrailSchedule.notes(runs: [], painWeeks: [], bedtimes: Self.plan([run]), now: Fixture.at(12),
                                            calendar: Self.calendar)
        let note = try #require(notes.first)
        #expect(note.kind == .bedtime && note.fireAt == Fixture.at(21, 30) && note.run == run)
        #expect(note.id.hasPrefix("guardrail-bedtime-"))
        #expect(GuardrailSchedule.notes(runs: [], painWeeks: [], bedtimes: Self.plan([run]), now: Fixture.at(22),
                                        calendar: Self.calendar).isEmpty)
    }

    @Test func itsTheFirstDroppedWhenTheEveningIsFull() {
        // A 5:30 AM long run that's a big jump: the swap note at 7 PM and the morning check at 8 PM come first.
        let run = Self.run("Long run 18 km", hour: 5, minute: 30, size: .km(18))
        let spike = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                  keepEasy: false, injuryAdjusted: false)
        let state = GuardrailSchedule.RunState(run: run, flag: spike, decided: false, checkedIn: false)
        let bedtimes = Self.plan([run])
        #expect(bedtimes.count == 1)
        let notes = GuardrailSchedule.notes(runs: [state], painWeeks: [], bedtimes: bedtimes, now: Fixture.at(12),
                                            calendar: Self.calendar)
        #expect(notes.map(\.kind) == [.swap, .morningCheck])
    }

    @Test func theNotifierSchedulesItWithoutButtons() async throws {
        let (notifier, center) = await NotifierTests.notifier()
        let bedtime = try #require(Self.plan([Self.run()]).first)
        let copy = bedtime.note(calendar: Self.calendar)
        let note = GuardrailNote(kind: .bedtime, fireAt: bedtime.fireAt, title: copy.title, body: copy.body, run: bedtime.run)
        await notifier.scheduleGuardrail([note])
        let request = try #require(center.request(note.id))
        #expect(request.content.title == "Lights out by 10:30")
        #expect(request.content.categoryIdentifier.isEmpty)
    }

    // MARK: On Today

    @Test func todayShowsTonightsBedtimeInTheEvening() throws {
        let model = try NotifierActionTests.model()
        model.demoHealthDays = Array(AppModel.roughNightDays(storyDay: model.storyDay, calendar: model.calendar).dropLast())
        let tomorrow = model.calendar.date(byAdding: .day, value: 1, to: model.storyDay)!
        let start = model.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow)!
        model.trainingRuns = [PlannedRun(key: "runna|bed", title: "Long run 1h 40", calendarTitle: "Runna", start: start,
                                         end: start.addingTimeInterval(6000), size: .minutes(100), isHard: false,
                                         isAllDay: false)]
        model.setClockMinutes(12 * 60)
        #expect(model.tonightsBedtime == nil)
        model.setClockMinutes(20 * 60 + 30)
        let bedtime = try #require(model.tonightsBedtime)
        #expect(bedtime.line(calendar: model.calendar) == "Lights out by 10:30 for tomorrow’s long run.")
        #expect(bedtime.reason(calendar: model.calendar) == "That leaves your usual 7h 30 of sleep before a 6:00 wake-up.")
    }
}
