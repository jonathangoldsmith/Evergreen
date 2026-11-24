import Foundation
import SwiftData
import Testing
@testable import Evergreen

/// The store for real people (eng review D4 and D5): last release's file opens
/// and keeps its data, an unreadable file is set aside rather than deleted, and
/// a real person's actions survive a new story day.
@MainActor
struct StorageTests {
    static func tempStore() -> URL {
        // A space in the path, like "Application Support".
        let folder = URL.temporaryDirectory.appending(path: "storage \(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Evergreen.store")
    }

    static func swapAction(_ id: String = "user-move-1") -> AgentAction {
        let start = Fixture.at(18)
        return AgentAction(id: id, kind: .move, planItemId: "plan-me-2026-11-19-running",
                           before: Slot(start: start, end: start.addingTimeInterval(1800), activityType: "Running"),
                           after: Slot(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5400), activityType: "Running"),
                           reason: "You picked this time.", createdAt: start)
    }

    @Test func lastReleasesStoreOpensWithItsRunAndActions() throws {
        let url = Self.tempStore()
        do {
            let schema = Schema(versionedSchema: EvergreenSchemaV1.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let run = Run(persona: .me, storyDay: Fixture.storyDay)
            run.onboarded = true
            old.mainContext.insert(run)
            let record = ActionRecord(Self.swapAction(), sequence: 0)
            old.mainContext.insert(record)
            run.actions.append(record)
            try old.mainContext.save()
        }

        let container = try Storage.open(at: url)
        let runs = try container.mainContext.fetch(FetchDescriptor<Run>())
        let run = try #require(runs.first)
        #expect(run.personaKey == .me && run.onboarded)
        #expect(run.actions.map(\.actionId) == ["user-move-1"])

        // The new models are there to write to.
        let profile = Profile()
        profile.injuryMonth = Fixture.storyDay
        container.mainContext.insert(profile)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<Profile>()).count == 1)
    }

    @Test func anUnreadableStoreIsSetAsideNotDeleted() throws {
        let url = Self.tempStore()
        try Data("not a database".utf8).write(to: url)

        let container = Storage.container(at: url)
        #expect(try container.mainContext.fetch(FetchDescriptor<Run>()).isEmpty)

        let folder = url.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        let aside = try #require(names.first { $0.hasPrefix("Evergreen-unreadable-") && $0.hasSuffix(".store") })
        #expect(try Data(contentsOf: folder.appending(path: aside)) == Data("not a database".utf8))
    }

    @Test func aRealPersonsActionsSurviveANewDay() throws {
        let container = try Storage.open(at: Self.tempStore())
        let context = container.mainContext
        let run = Run(persona: .me, storyDay: Fixture.storyDay)
        context.insert(run)
        let record = ActionRecord(Self.swapAction(), sequence: 0)
        context.insert(record)
        run.actions.append(record)
        try context.save()

        let monday = Fixture.calendar.date(byAdding: .day, value: 4, to: Fixture.storyDay)!
        run.startDay(monday, keepingHistory: true, in: context)
        try context.save()

        #expect(run.storyDay == monday)
        #expect(run.actions.map(\.actionId) == ["user-move-1"])
        #expect(run.clockMinutes == nil && run.lastResponse == nil)
    }

    @Test func aDemoPersonsRunStartsCleanEachDay() throws {
        let container = try Storage.open(at: Self.tempStore())
        let context = container.mainContext
        let run = Run(persona: .jordan, storyDay: Fixture.storyDay)
        context.insert(run)
        let record = ActionRecord(Self.swapAction(), sequence: 0)
        context.insert(record)
        run.actions.append(record)
        run.approvedPurchaseIds = ["daypass-1"]
        try context.save()

        run.startDay(Fixture.storyDay.addingTimeInterval(86_400), keepingHistory: false, in: context)
        try context.save()

        #expect(run.actions.isEmpty && run.approvedPurchaseIds.isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActionRecord>()).isEmpty)
    }

    @Test func guardrailDecisionsAreNotPartOfTheRun() throws {
        let container = try Storage.open(at: Self.tempStore())
        let context = container.mainContext
        let run = Run(persona: .jordan, storyDay: Fixture.storyDay)
        context.insert(run)
        let planned = PlannedRun(key: "runna|2026-11-22|Long run 18 km", title: "Long run 18 km", calendarTitle: "Runna",
                                 start: Fixture.at(8, dayOffset: 3), end: Fixture.at(10, dayOffset: 3),
                                 size: .km(18), isHard: false, isAllDay: false)
        let flag = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                 keepEasy: false, injuryAdjusted: false)
        context.insert(GuardrailDecision(run: planned, flag: flag, choice: .accept, at: Fixture.at(19)))
        try context.save()

        run.startDay(Fixture.storyDay.addingTimeInterval(86_400), keepingHistory: false, in: context)
        try context.save()

        let decisions = try context.fetch(FetchDescriptor<GuardrailDecision>())
        #expect(decisions.map(\.suggested) == [.km(13)])
    }
}
