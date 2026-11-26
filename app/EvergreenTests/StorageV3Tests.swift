import Foundation
import SwiftData
import Testing
@testable import Evergreen

/// The V2 → V3 store migration keeps everything and adds the return plan.
@MainActor
struct StorageV3Tests {
    @Test func aV2StoreOpensWithItsDecisionsAndTakesAReturnPlan() throws {
        let url = StorageTests.tempStore()
        do {
            let schema = Schema(versionedSchema: EvergreenSchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let profile = Profile()
            profile.injuryMonth = Fixture.storyDay
            old.mainContext.insert(profile)
            old.mainContext.insert(CheckInRecord(runKey: "runna|x", answer: .sore, at: Fixture.at(7)))
            try old.mainContext.save()
        }
        let container = try Storage.open(at: url)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<Profile>()).first?.injuryMonth == Fixture.storyDay)
        #expect(try context.fetch(FetchDescriptor<CheckInRecord>()).count == 1)
        context.insert(ReturnPlanState(start: Fixture.at(12), weekdays: [2, 4, 7], startMinute: 420, at: Fixture.at(12)))
        try context.save()
        let plan = try #require(try context.fetch(FetchDescriptor<ReturnPlanState>()).first)
        #expect(plan.weekdays == [2, 4, 7] && plan.status == .active)
    }
}
