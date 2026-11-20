import Foundation
import Testing
@testable import Evergreen

/// The P0 rules the offline stand-in shares with the harness's `decide()`.
/// When the harness's golden fixtures land (task T3), the same cases should
/// pass against both.
struct StandInAgentTests {
    let agent = StandInAgent()

    // MARK: Normal and goal

    @Test func goalIsTenPercentMoreRoundedUp() async throws {
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(9)))

        #expect(response.normal.usual4Weeks == 8)
        #expect(response.normal.perWeek == 2)
        #expect(response.normal.goal4Weeks == 9)
        #expect(response.normal.weeklyTarget == 3)
        #expect(!response.normal.gettingToKnowYou)
        #expect(response.weekDone == 1)
    }

    @Test func veryActivePeopleKeepTheirNormal() async throws {
        let daily = (1...24).map {
            Fixture.workout("run-\($0)", at: Fixture.at(7, dayOffset: -$0), minutes: 30, type: "Running")
        }
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(9), workouts: daily))

        #expect(response.normal.perWeek == 6)
        #expect(response.normal.goal4Weeks == 24)
    }

    @Test func thinHistoryStartsFromDefaults() async throws {
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(9), historyDays: 10, workouts: []))

        #expect(response.normal.gettingToKnowYou)
        #expect(response.normal.usual4Weeks == 8)
        #expect(response.normal.goal4Weeks == 9)
        #expect(response.actions.map(\.id) == ["note-getting-to-know-you"])
    }

    @Test func workoutsUnderTenMinutesDontCount() async throws {
        let short = Fixture.workout("short", at: Fixture.at(8), minutes: 5)
        let response = try await agent.tick(
            Fixture.snapshot(now: Fixture.at(9), workouts: Fixture.samHistory + [short])
        )

        #expect(response.weekDone == 1)
    }

    // MARK: Misses and completions

    @Test func aMissedWorkoutGetsNoAction() async throws {
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk]))

        #expect(response.actions.isEmpty)
        #expect(response.completions.isEmpty)
    }

    @Test func finishingAPlannedWorkoutCompletesIt() async throws {
        let walk = Fixture.workout("demo-walk", at: Fixture.at(12), minutes: 30, source: .demo)

        let response = try await agent.tick(Fixture.snapshot(
            now: Fixture.at(12, 40), plan: [Fixture.lunchWalk], workouts: Fixture.samHistory + [walk]
        ))

        #expect(response.completions == [
            Completion(planItemId: Fixture.lunchWalk.id, workoutId: "demo-walk", points: Fixture.lunchWalk.points, comeback: false),
        ])
        #expect(response.weekDone == 2)
    }

    // MARK: Duplicates

    @Test func overlappingSameTypeWorkoutsCountOnceKeepingTheLonger() {
        let watch = Fixture.workout("watch", at: Fixture.at(19), minutes: 30)
        let phone = Fixture.workout("phone", at: Fixture.at(19, 5), minutes: 20)

        #expect(StandInAgent.mergeDuplicates([phone, watch]).map(\.id) == ["watch"])
    }

    @Test func overlappingDifferentTypesBothCount() {
        let walk = Fixture.workout("walk", at: Fixture.at(19), minutes: 30)
        let strength = Fixture.workout("strength", at: Fixture.at(19, 5), minutes: 20, type: "TraditionalStrengthTraining")

        #expect(Set(StandInAgent.mergeDuplicates([walk, strength]).map(\.id)) == ["walk", "strength"])
    }
}
