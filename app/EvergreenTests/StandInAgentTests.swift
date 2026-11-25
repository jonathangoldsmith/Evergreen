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

    @Test func aRegularsMissGetsNoComeback() async throws {
        // Three a week: the brake's side, not the push's (range plan item 10).
        let regular = (1...12).map { Fixture.workout("r\($0)", at: Fixture.at(19, dayOffset: -$0 * 2), minutes: 30) }
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk],
                                                             workouts: regular))

        #expect(response.actions.isEmpty)
        #expect(response.completions.isEmpty)
    }

    // MARK: The push: misses and comebacks (range plan items 10–13)

    @Test func missedWalkBooksAShorterDoublePointsComeback() async throws {
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk]))

        let comeback = try #require(response.actions.first)
        #expect(response.actions.count == 1)
        #expect(comeback.id == "comeback-plan-walk")
        #expect(comeback.kind == .bookComeback)
        #expect(comeback.before == Fixture.lunchWalk.slot)
        // 60% of the 25-minute median, at the usual 7 PM.
        #expect(comeback.after == Slot(start: Fixture.at(19), end: Fixture.at(19, 15), activityType: "Walking"))
        #expect(comeback.points == 40)
        #expect(ActionCopy.comebackKeep(comeback, now: Fixture.at(13, 30)) == "Keep your 40 points: a 15-minute walk tonight.")
    }

    @Test func noMissInsideTheGracePeriod() async throws {
        // The walk ended at 12:30; it counts as missed from 1:00.
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(12, 50), plan: [Fixture.lunchWalk]))

        #expect(response.actions.isEmpty)
    }

    @Test func aComebackIsBookedOnce() async throws {
        let first = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk]))
        let again = try await agent.tick(
            Fixture.snapshot(now: Fixture.at(14), plan: [Fixture.lunchWalk], actions: first.actions)
        )

        #expect(again.actions.isEmpty)
    }

    @Test func anUndoneComebackIsntBookedAgain() async throws {
        let response = try await agent.tick(Fixture.snapshot(
            now: Fixture.at(14), plan: [Fixture.lunchWalk], undoneActionIds: ["comeback-plan-walk"]
        ))

        #expect(response.actions.isEmpty)
    }

    @Test func aMissedComebackOnlyGetsANote() async throws {
        let booked = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk]))
        let comeback = try #require(booked.actions.first)
        let comebackItem = PlanItem(id: comeback.id, slot: try #require(comeback.after), points: 40, source: .comeback)

        let response = try await agent.tick(Fixture.snapshot(
            now: Fixture.at(20), plan: [Fixture.lunchWalk, comebackItem], actions: booked.actions
        ))

        #expect(response.actions.map(\.id) == ["note-missed-comeback-plan-walk"])
        #expect(response.actions.first?.kind == .note)
    }

    @Test func aMissedSwapIsNeverChased() async throws {
        let swap = PlanItem(id: "swap-0123456789ab", slot: Fixture.lunchWalk.slot, points: 20, source: .swap)
        let response = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [swap]))

        #expect(response.actions.isEmpty)
    }

    @Test func finishingTheComebackEarnsDoublePoints() async throws {
        let booked = try await agent.tick(Fixture.snapshot(now: Fixture.at(13, 30), plan: [Fixture.lunchWalk]))
        let comeback = try #require(booked.actions.first)
        let comebackItem = PlanItem(id: comeback.id, slot: try #require(comeback.after), points: 40, source: .comeback)
        let walk = Fixture.workout("demo-walk", at: Fixture.at(19), minutes: 15, source: .demo)

        let response = try await agent.tick(Fixture.snapshot(
            now: Fixture.at(19, 20),
            plan: [Fixture.lunchWalk, comebackItem],
            workouts: Fixture.samHistory + [walk],
            actions: booked.actions
        ))

        #expect(response.completions == [
            Completion(planItemId: "comeback-plan-walk", workoutId: "demo-walk", points: 40, comeback: true),
        ])
        #expect(response.pointsTotal == 40)
        #expect(response.weekDone == 2)
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
