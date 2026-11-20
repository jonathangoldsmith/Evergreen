import Foundation
import Testing
@testable import TrackerPlusPlus

/// The shopping beat's happy paths (eng review D5) and the guard that the
/// purchase rules stay silent without demo conditions (D6).
struct PurchaseTests {
    /// No evidence URL or harness: tests never touch the network, get cached
    /// passages and the stand-in's own shoe pick.
    let agent = StandInAgent(evidence: nil, recommend: nil)

    /// Jordan's shape: 20 runs of 56¼ minutes in 30 days = 1,125 minutes = 125
    /// miles, on a pair that already had 267, so the pair reads 392.
    static let runs: [Workout] = (1...20).map { index in
        Workout(id: "run-\(index)", activityType: "Running",
                start: Fixture.at(7, dayOffset: -index), end: Fixture.at(7, dayOffset: -index).addingTimeInterval(56.25 * 60),
                effort: nil, avgHeartRate: nil, source: .mock)
    }

    static let shoesId = "shoes-\(Fixture.calendar.date(byAdding: .day, value: -30, to: Fixture.storyDay)!.formatted(.iso8601.year().month().day()))"

    static func jordan(actions: [AgentAction] = [], undone: [String] = [], approved: [String] = []) -> TickSnapshot {
        var snapshot = Fixture.snapshot(now: Fixture.at(9), workouts: runs, actions: actions, undoneActionIds: undone)
        snapshot.mandate = AppModel.mandate
        snapshot.approvedPurchaseIds = approved
        snapshot.demo = DemoConditions(
            shoesBoughtOn: Fixture.calendar.date(byAdding: .day, value: -30, to: Fixture.storyDay),
            shoesStartMiles: 267,
            raceDate: Fixture.calendar.date(byAdding: .day, value: 9, to: Fixture.storyDay)
        )
        return snapshot
    }

    private func purchaseActions(_ response: TickResponse) -> [AgentAction] {
        response.actions.filter { $0.purchaseId != nil }
    }

    @Test func asksFirstForTheCheapestPairThatFitsAndArrivesInTime() async throws {
        let actions = purchaseActions(try await agent.tick(Self.jordan()))

        #expect(actions.map(\.id) == ["purchase-\(Self.shoesId)"])
        let purchase = try #require(actions.first?.purchase)
        #expect(purchase.status == .awaitingApproval)
        #expect(purchase.item == "Pacer 9")
        #expect(purchase.amountCents == 13800)
        #expect(purchase.noticed == "Your shoes hit 392 miles. Race day is in 9 days.")
        #expect(purchase.rule.id == "ask-first")
        #expect(purchase.options.map(\.name) == ["Pacer 9", "Glide Trainer", "Tempo Lite"])
        #expect(purchase.options.dropFirst().allSatisfy { $0.lostBecause != nil })
        #expect(purchase.evidence.count == 3)
        #expect(!purchase.evidenceLive)
    }

    @Test func orderItBuysAndAddsTwoBreakInRuns() async throws {
        let ask = try #require(try await agent.tick(Self.jordan()).actions.first { $0.purchaseId != nil })
        let actions = purchaseActions(try await agent.tick(Self.jordan(actions: [ask], approved: [Self.shoesId])))

        #expect(actions.map(\.id) == [
            "purchase-\(Self.shoesId)-bought", "breakin-\(Self.shoesId)-1", "breakin-\(Self.shoesId)-2",
        ])
        #expect(actions.allSatisfy { $0.purchase?.status == .bought })
        // Pacer 9 arrives Sunday the 22nd; the race is Saturday the 28th.
        #expect(actions[1].after?.start == Fixture.at(18, dayOffset: 4))
        #expect(actions[1].after?.minutes == 30)
        #expect(actions[2].after?.start == Fixture.at(7, dayOffset: 6))
        #expect(actions[2].after?.minutes == 25)
    }

    @Test func notNowNeverAsksAgain() async throws {
        let ask = try #require(try await agent.tick(Self.jordan()).actions.first { $0.purchaseId != nil })
        let response = try await agent.tick(Self.jordan(undone: [ask.id], approved: [Self.shoesId]))

        #expect(purchaseActions(response).isEmpty)
    }

    @Test func cancelOrderCancelsOnce() async throws {
        let ask = try #require(try await agent.tick(Self.jordan()).actions.first { $0.purchaseId != nil })
        let bought = purchaseActions(try await agent.tick(Self.jordan(actions: [ask], approved: [Self.shoesId])))
        let undone = "purchase-\(Self.shoesId)-bought"
        let actions = purchaseActions(try await agent.tick(Self.jordan(
            actions: [ask] + bought.filter { $0.id != undone }, undone: [undone], approved: [Self.shoesId]
        )))

        #expect(actions.map(\.id) == ["purchase-\(Self.shoesId)-cancel"])
        #expect(actions.first?.kind == .cancelPurchase)
        #expect(actions.first?.purchase?.status == .cancelled)
    }

    // MARK: Day pass (Sam's rain)

    /// Sam's 6:30 PM comeback walk, booked after the missed lunch walk.
    static let comeback = PlanItem(
        id: "comeback-plan-walk",
        slot: Slot(start: Fixture.at(18, 30), end: Fixture.at(18, 45), activityType: "Walking"),
        points: StandInAgent.basePoints * 2,
        source: .comeback
    )

    static func sam(
        now: Date = Fixture.at(13, 30), inGym: Bool = false, actions: [AgentAction] = [], undone: [String] = [],
        forecastClear: Bool = false, visits: [Visit] = [], verified: Bool = true, approved: [String] = []
    ) -> TickSnapshot {
        var item = comeback
        if inGym { item.slot.place = StandInAgent.gym }
        var snapshot = Fixture.snapshot(now: now, plan: [item], actions: actions, undoneActionIds: undone)
        snapshot.mandate = AppModel.mandate
        snapshot.demo = DemoConditions(rainAt: Fixture.at(18, 30), forecastClear: forecastClear)
        snapshot.visits = visits
        snapshot.identityVerified = verified
        snapshot.approvedPurchaseIds = approved
        return snapshot
    }

    private func boughtPass() async throws -> AgentAction {
        try #require(try await agent.tick(Self.sam()).actions.first { $0.purchaseId != nil })
    }

    @Test func rainBuysADayPassWithoutAsking() async throws {
        let pass = try await boughtPass()

        #expect(pass.kind == .purchase)
        #expect(pass.purchase?.status == .bought)
        #expect(pass.purchase?.amountCents == 1500)
        #expect(pass.purchase?.rule.id == "day-pass")
        #expect(pass.purchase?.cancelBy == Fixture.at(17, 30))
        #expect(pass.planItemId == Self.comeback.id)
        #expect(pass.after?.place == StandInAgent.gym)
        #expect(pass.after?.start == Self.comeback.slot.start)
    }

    @Test func clearForecastMakesTheAgentCancelItsOwnPass() async throws {
        let pass = try await boughtPass()
        let actions = purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(13, 45), inGym: true, actions: [pass], forecastClear: true
        )))

        #expect(actions.map(\.id) == ["\(pass.id)-cancel"])
        #expect(actions.first?.purchase?.status == .cancelled)
        #expect(actions.first?.purchase?.outcome == "$15 refunded")
        #expect(actions.first?.after?.place == nil)
    }

    @Test func undoBeforeTheDeadlineRefunds() async throws {
        let pass = try await boughtPass()
        // Undone actions aren't in the snapshot, and replay puts the walk back outside.
        let actions = purchaseActions(try await agent.tick(Self.sam(now: Fixture.at(14), undone: [pass.id])))

        #expect(actions.map(\.id) == ["\(pass.id)-cancel"])
        #expect(actions.first?.purchase?.status == .cancelled)
    }

    @Test func arrivingAtTheGymClosesTheTrail() async throws {
        let pass = try await boughtPass()
        let actions = purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(18, 45), inGym: true, actions: [pass],
            visits: [Visit(place: StandInAgent.gym, at: Fixture.at(18, 45))]
        )))

        #expect(actions.map(\.id) == ["\(pass.id)-outcome"])
        #expect(actions.first?.kind == .purchaseOutcome)
        #expect(actions.first?.purchase?.outcome?.hasSuffix("pass used") == true)
    }

    // MARK: Day pass before identity verification (Persona)

    static let askId = "pass-ask-\(comeback.id)-\(Int(Fixture.at(18, 30).timeIntervalSince1970))"

    private func ask() async throws -> AgentAction {
        try #require(try await agent.tick(Self.sam(verified: false)).actions.first { $0.purchaseId != nil })
    }

    @Test func unverifiedRainAsksFirstAndMovesNothing() async throws {
        let ask = try await ask()

        #expect(ask.id == "purchase-\(Self.askId)")
        #expect(ask.purchase?.status == .awaitingApproval)
        #expect(ask.purchase?.rule.id == "ask-first")
        #expect(ask.purchase?.amountCents == 1500)
        #expect(ask.after == nil)
    }

    @Test func orderItOnTheAskBuysAndMovesTheWalk() async throws {
        let ask = try await ask()
        let actions = purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(13, 40), actions: [ask], verified: true, approved: [Self.askId]
        )))

        #expect(actions.map(\.id) == ["purchase-\(Self.askId)-bought"])
        #expect(actions.first?.purchase?.status == .bought)
        #expect(actions.first?.after?.place == StandInAgent.gym)
    }

    @Test func notNowOnTheAskNeverBuysOrRefunds() async throws {
        let ask = try await ask()
        let actions = purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(13, 40), undone: [ask.id], verified: true
        )))

        #expect(actions.isEmpty)
    }

    @Test func cancelOrderOnAnApprovedPassRefunds() async throws {
        let ask = try await ask()
        let bought = try #require(purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(13, 40), actions: [ask], verified: true, approved: [Self.askId]
        ))).first)
        let actions = purchaseActions(try await agent.tick(Self.sam(
            now: Fixture.at(14), inGym: false, actions: [ask], undone: [bought.id], verified: true, approved: [Self.askId]
        )))

        #expect(actions.map(\.id) == ["purchase-\(Self.askId)-cancel"])
        #expect(actions.first?.purchase?.outcome == "$15 refunded")
    }

    // MARK: Regression guard (D6)

    @Test(arguments: PersonaKey.allCases)
    func noPurchasesWithoutDemoConditions(_ key: PersonaKey) async throws {
        let person = Persona.load(key, storyDay: Fixture.storyDay, calendar: Fixture.calendar)
        var snapshot = Fixture.snapshot(now: Fixture.at(21), workouts: person.workouts)
        snapshot.mandate = AppModel.mandate
        let response = try await agent.tick(snapshot)

        #expect(response.actions.allSatisfy { $0.purchaseId == nil && $0.purchase == nil })
    }

    @MainActor @Test func storedActionsRoundTripUnchanged() throws {
        let move = AgentAction(
            id: "defend-plan-elliptical-1", kind: .move, planItemId: "plan-elliptical",
            before: Fixture.fridayElliptical.slot, after: Fixture.lunchWalk.slot,
            reason: "That's the nearest free time.", createdAt: Fixture.at(9)
        )
        #expect(ActionRecord(move, sequence: 0).action == move)

        let ask = AgentAction(
            id: "purchase-x", kind: .purchase, title: "Picked new running shoes", reason: "Fits.",
            createdAt: Fixture.at(9), purchaseId: "x",
            purchase: Purchase(id: "x", item: "Pacer 9", merchant: "Demo store, no charge", amountCents: 13800,
                               status: .awaitingApproval, rule: .init(id: "ask-first", text: "Ask me."),
                               noticed: "392 miles.", evidence: [], evidenceLive: false, options: [])
        )
        #expect(ActionRecord(ask, sequence: 1).action == ask)
    }
}
