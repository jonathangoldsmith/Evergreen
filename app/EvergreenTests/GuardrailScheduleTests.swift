import Foundation
import Testing
@testable import Evergreen

/// The guardrail notification budget (design decision 10, eng re-run R9) and
/// the pain week's calendar (plan item 17).
struct GuardrailScheduleTests {
    static let cal = Fixture.calendar
    /// Thursday 19 November 2026, noon.
    static let now = Fixture.at(12)

    static func run(_ title: String, dayOffset: Int, hour: Int, size: RunSize = .km(18)) -> PlannedRun {
        let start = Fixture.at(hour, dayOffset: dayOffset)
        return PlannedRun(key: "runna|\(dayOffset)|\(title)", title: title, calendarTitle: "Runna", start: start,
                          end: start.addingTimeInterval(5400), size: size, isHard: false, isAllDay: false)
    }

    static let spike = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                     keepEasy: false, injuryAdjusted: false)

    static func state(_ run: PlannedRun, flag: GuardrailFlag? = nil, decided: Bool = false,
                      checkedIn: Bool = false) -> GuardrailSchedule.RunState {
        .init(run: run, flag: flag, decided: decided, checkedIn: checkedIn)
    }

    static func hour(_ note: GuardrailNote) -> Int { cal.component(.hour, from: note.fireAt) }

    @Test func aMorningRunGetsAnEveningSwapNoteAndAMorningCheck() throws {
        let saturday = Self.run("Long run 18 km", dayOffset: 2, hour: 8)
        let notes = GuardrailSchedule.notes(runs: [Self.state(saturday, flag: Self.spike)], painWeeks: [],
                                            now: Self.now, calendar: Self.cal)
        let swap = try #require(notes.first { $0.kind == .swap })
        #expect(Self.cal.isDate(swap.fireAt, inSameDayAs: Fixture.at(0, dayOffset: 1)) && Self.hour(swap) == 19)
        #expect(swap.body == "Tomorrow’s 18 km is a big jump from your longest run (13 km). Make it 13?")
        let check = try #require(notes.first { $0.kind == .morningCheck })
        #expect(Self.hour(check) == 7 && Self.cal.isDate(check.fireAt, inSameDayAs: saturday.start))
    }

    @Test func anAfternoonRunGetsItsSwapNoteAt7AM() throws {
        let saturday = Self.run("Long run 18 km", dayOffset: 2, hour: 17)
        let notes = GuardrailSchedule.notes(runs: [Self.state(saturday, flag: Self.spike)], painWeeks: [],
                                            now: Self.now, calendar: Self.cal)
        let swap = try #require(notes.first { $0.kind == .swap })
        #expect(Self.cal.isDate(swap.fireAt, inSameDayAs: saturday.start) && Self.hour(swap) == 7)
    }

    @Test func aDecidedRunGetsNoNotes() {
        let saturday = Self.run("Long run 18 km", dayOffset: 2, hour: 8)
        #expect(GuardrailSchedule.notes(runs: [Self.state(saturday, flag: Self.spike, decided: true)], painWeeks: [],
                                        now: Self.now, calendar: Self.cal).isEmpty)
    }

    @Test func aRunBefore6AMIsCheckedTheEveningBefore() throws {
        let early = Self.run("Easy 40 min", dayOffset: 2, hour: 5, size: .minutes(40))
        let notes = GuardrailSchedule.notes(runs: [Self.state(early)], painWeeks: [], now: Self.now, calendar: Self.cal)
        let check = try #require(notes.first)
        #expect(Self.hour(check) == 20 && Self.cal.isDate(check.fireAt, inSameDayAs: Fixture.at(0, dayOffset: 1)))
    }

    @Test func aSundayWithAMondaySpikeSendsExactlyTwoAndKeepsThePainNote() throws {
        // Sunday long run (morning check at 7 AM), Sunday 6 PM pain note, and a
        // spike note for Monday's 8 AM run at Sunday 7 PM: three on Sunday.
        let sunday = Self.run("Long run 16 km", dayOffset: 3, hour: 8, size: .km(16))
        let monday = Self.run("Long run 18 km", dayOffset: 4, hour: 8)
        let week = PainWeek.monday(of: Fixture.at(12, dayOffset: 3), calendar: Self.cal)
        let notes = GuardrailSchedule.notes(runs: [Self.state(sunday), Self.state(monday, flag: Self.spike, checkedIn: true)],
                                            painWeeks: [week], now: Self.now, calendar: Self.cal)
        let onSunday = notes.filter { Self.cal.isDate($0.fireAt, inSameDayAs: sunday.start) }
        #expect(onSunday.count == 2)
        let pain = try #require(onSunday.first { $0.kind == .pain })
        #expect(pain.body == "How was your week? Any pain? Also: tomorrow’s 18 km is a big jump from your longest run (13 km). Make it 13?")
        #expect(onSunday.contains { $0.kind == .morningCheck })
    }

    @Test func withoutAPainNoteTheMorningCheckIsDroppedFirst() {
        // Two runs on Saturday plus a spike note for Saturday morning's run: three on Saturday.
        let morning = Self.run("Easy 8 km", dayOffset: 2, hour: 7, size: .km(8))
        let evening = Self.run("Tempo 10 km", dayOffset: 2, hour: 17, size: .km(10))
        let notes = GuardrailSchedule.notes(runs: [Self.state(morning), Self.state(evening, flag: Self.spike)],
                                            painWeeks: [], now: Self.now, calendar: Self.cal)
        let saturday = notes.filter { Self.cal.isDate($0.fireAt, inSameDayAs: morning.start) }
        #expect(saturday.count == 2)
        #expect(saturday.contains { $0.kind == .swap })
    }

    @Test func notesInThePastAreNotScheduled() {
        let today = Self.run("Long run 18 km", dayOffset: 0, hour: 18)
        let notes = GuardrailSchedule.notes(runs: [Self.state(today, flag: Self.spike)], painWeeks: [],
                                            now: Self.now, calendar: Self.cal)
        #expect(notes.allSatisfy { $0.fireAt > Self.now })
    }

    // MARK: Pain week

    @Test func theWeekRunsMondayToSundayAndIsAskedSundayAt6() {
        let monday = PainWeek.monday(of: Fixture.at(12), calendar: Self.cal)        // Thursday the 19th
        #expect(Self.cal.component(.day, from: monday) == 16)
        let asks = PainWeek.asksAt(monday, calendar: Self.cal)
        #expect(Self.cal.component(.day, from: asks) == 22 && Self.cal.component(.hour, from: asks) == 18)
    }

    @Test func theOpenWeekRunsFromSunday6PMToTuesdayNight() {
        let monday16 = PainWeek.monday(of: Fixture.at(12), calendar: Self.cal)
        #expect(PainWeek.openWeek(at: Fixture.at(17, dayOffset: 3), calendar: Self.cal) == nil)        // Sunday 5 PM
        #expect(PainWeek.openWeek(at: Fixture.at(18, dayOffset: 3), calendar: Self.cal) == monday16)   // Sunday 6 PM
        #expect(PainWeek.openWeek(at: Fixture.at(23, dayOffset: 5), calendar: Self.cal) == monday16)   // Tuesday 11 PM
        #expect(PainWeek.openWeek(at: Fixture.at(0, dayOffset: 6), calendar: Self.cal) == nil)         // Wednesday
    }
}
