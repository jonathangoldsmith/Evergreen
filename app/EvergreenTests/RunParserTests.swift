import Foundation
import Testing
@testable import Evergreen

/// Which training-calendar events are runs, and their size (plan items 1 and 3).
struct RunParserTests {
    static let start = Fixture.at(7)

    static func parse(_ title: String, minutes: Double = 60, allDay: Bool = false) -> PlannedRun? {
        let start = allDay ? Fixture.storyDay : Self.start
        let end = allDay ? Fixture.calendar.date(byAdding: .day, value: 1, to: start)! : start.addingTimeInterval(minutes * 60)
        return RunParser.parse(title: title, start: start, end: end, isAllDay: allDay,
                               calendarId: "runna", calendarTitle: "Runna", calendar: Fixture.calendar)
    }

    @Test(arguments: [
        ("Long run 18 km", RunSize.km(18)),
        ("Easy 8km", .km(8)),
        ("Parkrun 5k", .km(5)),
        ("Recovery 6.2 mi", .km(10)),
        ("Easy 45 min", .minutes(45)),
        ("Long run 1h 30", .minutes(90)),
        ("Tempo 1.5 hours", .minutes(90)),
    ])
    func titlesGiveTheSize(title: String, size: RunSize) throws {
        #expect(try #require(Self.parse(title)).size == size)
    }

    @Test func aRunWordWithoutASizeTakesTheEventsLength() throws {
        #expect(try #require(Self.parse("Easy run", minutes: 40)).size == .minutes(40))
    }

    @Test(arguments: ["Physio", "Team sync", "Strength 30 min", "Yoga"])
    func otherEventsAreNotRuns(title: String) {
        #expect(Self.parse(title) == nil)
    }

    @Test func aDistanceAloneMakesItARun() throws {
        #expect(try #require(Self.parse("12 km with Sam")).size == .km(12))
    }

    @Test func anAllDayRunWithASizeIsAnEightAMRun() throws {
        let run = try #require(Self.parse("Long run 18 km", allDay: true))
        #expect(run.isAllDay && run.size == .km(18))
        #expect(Fixture.calendar.component(.hour, from: run.start) == 8)
    }

    @Test func anAllDayRunWithoutASizeIsShownButHasNoSize() throws {
        let run = try #require(Self.parse("Easy run", allDay: true))
        #expect(run.size == nil)
    }

    @Test(arguments: ["Tempo 8 km", "Intervals 6x800", "Threshold 40 min", "Hills 45 min", "Track session 5 km", "Run 10 km at race pace"])
    func hardSessionsAreMarkedHard(title: String) throws {
        #expect(try #require(Self.parse(title)).isHard)
    }

    @Test func theKeyIsCalendarDayAndTitleAndTheSwapIdIsStable() throws {
        let run = try #require(Self.parse("Long run 18 km"))
        #expect(run.key == "runna|2026-11-19|Long run 18 km")
        #expect(run.swapItemId == (try #require(Self.parse("Long run 18 km"))).swapItemId)
        #expect(run.swapItemId.hasPrefix("swap-") && run.swapItemId.count == 17)
    }
}
