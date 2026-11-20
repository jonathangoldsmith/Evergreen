import Foundation
import Testing
@testable import TrackerPlusPlus

/// How the plan becomes TrackerPlusPlus calendar events, and what a sync
/// creates, moves and deletes. EventKit itself is checked on the phone.
struct CalendarSyncTests {
    private let comeback = PlanItem(
        id: "comeback-plan-walk",
        slot: Slot(start: Fixture.at(18, 30), end: Fixture.at(18, 45), activityType: "Walking"),
        points: 40,
        source: .comeback
    )

    private func entries(_ plan: [PlanItem], reasons: [String: String] = [:]) -> [CalendarEntry] {
        CalendarEntry.entries(for: plan, reasons: reasons, storyDay: Fixture.storyDay, calendar: Fixture.calendar)
    }

    // MARK: Entries

    @Test func eachPlanItemIsKeyedByStoryDayAndId() {
        let keys = entries([Fixture.lunchWalk, comeback]).map(\.key.absoluteString)

        #expect(keys == [
            "trackerplusplus://plan/2026-11-19/plan-walk",
            "trackerplusplus://plan/2026-11-19/comeback-plan-walk",
        ])
    }

    @Test func titlesSayWhatKindOfWorkoutItIs() {
        let routine = PlanItem(id: "routine-run", slot: Fixture.lunchWalk.slot, points: 20, source: .routine)

        #expect(entries([Fixture.lunchWalk, comeback, routine]).map(\.title) == [
            "Walk",
            "Comeback walk · 2× points",
            "Walk (routine)",
        ])
    }

    @Test func notesCarryTheAgentsReason() {
        let entry = entries([comeback], reasons: ["comeback-plan-walk": "Shorter sessions are easier."])[0]

        #expect(entry.notes == "Shorter sessions are easier.\n\nPlanned by Evergreen.")
        #expect(entry.start == Fixture.at(18, 30))
        #expect(entry.end == Fixture.at(18, 45))
    }

    // MARK: Changes

    @Test func missingEventsAreCreated() {
        let changes = CalendarChanges<Int>(desired: entries([Fixture.lunchWalk, comeback]), existing: [])

        #expect(changes.create.map(\.title) == ["Walk", "Comeback walk · 2× points"])
        #expect(changes.update.isEmpty)
        #expect(changes.delete.isEmpty)
    }

    @Test func matchingEventsAreLeftAlone() {
        let current = entries([Fixture.lunchWalk, comeback])
        let changes = CalendarChanges(desired: current, existing: [(id: 0, entry: current[0]), (id: 1, entry: current[1])])

        #expect(changes.isEmpty)
    }

    @Test func aMovedItemUpdatesItsEvent() {
        let before = entries([comeback])[0]
        var moved = comeback
        moved.slot = Slot(start: Fixture.at(20, 30), end: Fixture.at(20, 45), activityType: "Walking")
        let after = entries([moved])

        let changes = CalendarChanges(desired: after, existing: [(id: 7, entry: before)])

        #expect(changes.update == [.init(event: 7, entry: after[0])])
        #expect(changes.create.isEmpty)
        #expect(changes.delete.isEmpty)
    }

    @Test func anUndoneComebackDeletesItsEvent() {
        let current = entries([Fixture.lunchWalk, comeback])
        let changes = CalendarChanges(
            desired: entries([Fixture.lunchWalk]),
            existing: [(id: 0, entry: current[0]), (id: 1, entry: current[1])]
        )

        #expect(changes.delete == [1])
        #expect(changes.create.isEmpty)
        #expect(changes.update.isEmpty)
    }

    @Test func aDuplicateEventIsDeleted() {
        let walk = entries([Fixture.lunchWalk])
        let changes = CalendarChanges(desired: walk, existing: [(id: 0, entry: walk[0]), (id: 1, entry: walk[0])])

        #expect(changes.delete == [1])
        #expect(changes.create.isEmpty)
    }

    @Test func anotherStoryDaysEventIsReplaced() {
        let yesterday = CalendarEntry.entries(
            for: [Fixture.lunchWalk], reasons: [:],
            storyDay: Fixture.calendar.date(byAdding: .day, value: -1, to: Fixture.storyDay)!,
            calendar: Fixture.calendar
        )
        let changes = CalendarChanges(desired: entries([Fixture.lunchWalk]), existing: [(id: 3, entry: yesterday[0])])

        #expect(changes.delete == [3])
        #expect(changes.create.map(\.key.absoluteString) == ["trackerplusplus://plan/2026-11-19/plan-walk"])
    }
}
