import Foundation
import Testing
@testable import Evergreen

/// Today's card stack (tasks G2, E17, G4): one urgency order, cards only while
/// something needs an answer or can be undone, and each card's after-answer state.
@MainActor
struct TodayCardTests {
    // MARK: The order

    @Test func theOrderIsUrgencyThenTime() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let ranked: [TodayCard.Ranked] = [
            .init(card: .returnPlan, urgency: .returnPlan, at: early),
            .init(card: .pain(early), urgency: .pain, at: early),
            .init(card: .run(Self.run(at: late)), urgency: .swap, at: late),
            .init(card: .run(Self.run(at: early)), urgency: .morningCheck, at: early),
            .init(card: .pain(late), urgency: .note, at: late),
        ]
        #expect(TodayCard.ordered(ranked).map(\.id) == [
            "run-\(Self.run(at: late).key)", "run-\(Self.run(at: early).key)",
            "pain-\(early.timeIntervalSince1970)", "return", "pain-\(late.timeIntervalSince1970)",
        ])
    }

    @Test func notificationsDropByTheSameOrder() {
        #expect(GuardrailNote.Kind.swap.urgency < GuardrailNote.Kind.morningCheck.urgency)
        #expect(GuardrailNote.Kind.morningCheck.urgency < GuardrailNote.Kind.pain.urgency)
    }

    // MARK: A Sunday long-run day (G2's fixture)

    @Test func aSundayLongRunDayStacksRunThenPainThenReturn() throws {
        let (model, run) = try Self.sundayBeforeALongRun()
        #expect(model.todayCards.map(\.id) == ["run-\(run.key)", "pain-\(model.pendingPainWeek!.timeIntervalSince1970)", "return"])
        #expect(model.mostUrgentRun?.key == run.key)
    }

    @Test func aDecidedRunIsOneCardBelowTheQuestions() throws {
        let (model, run) = try Self.sundayBeforeALongRun()
        let flag = try #require(model.flag(for: run))
        model.acceptSwap(run, flag: flag)
        let ids = model.todayCards.map(\.id)
        #expect(ids.filter { $0 == "run-\(run.key)" }.count == 1)
        #expect(ids.last == "run-\(run.key)")
        #expect(model.runUrgency(run) == .undoable)
    }

    @Test func painNoLeavesAThanksCardAtTheBottom() throws {
        let (model, run) = try Self.sundayBeforeALongRun()
        let week = try #require(model.pendingPainWeek)
        model.answerPain(.no, week: week)
        #expect(model.pendingPainWeek == nil)
        #expect(model.painCardWeek == week)
        #expect(model.todayCards.map(\.id) == ["run-\(run.key)", "return", "pain-\(week.timeIntervalSince1970)"])
    }

    // MARK: The morning check (G4)

    @Test func twoRunsInADayAreAskedAboutOnce() throws {
        let model = try NotifierActionTests.model()
        model.completeOnboarding()
        let day = model.storyDay
        let first = Self.run(at: day.addingTimeInterval(18 * 3600), minutes: 30, key: "a")
        let second = Self.run(at: day.addingTimeInterval(20 * 3600), minutes: 30, key: "b")
        model.trainingRuns = [second, first]
        model.setClockMinutes(9 * 60)
        #expect(model.needsMorningCheck(first))
        #expect(!model.needsMorningCheck(second))
    }

    @Test func anAnsweredCheckShrinksToOneLineUntilTheRun() throws {
        let model = try NotifierActionTests.model()
        model.completeOnboarding()
        let run = Self.run(at: model.storyDay.addingTimeInterval(18 * 3600), minutes: 30, key: "easy")
        model.trainingRuns = [run]
        model.setClockMinutes(9 * 60)
        #expect(model.runUrgency(run) == .morningCheck)
        model.answerMorningCheck(run, .fresh)
        #expect(model.guardrailRuns.map(\.key) == [run.key])
        #expect(model.runUrgency(run) == .note)
        #expect(GuardrailCopy.checkedIn(.fresh) == "Got it. Enjoy the run.")
        #expect(GuardrailCopy.checkedIn(.tired) == "Keep it easy today.")
        model.setClockMinutes(18 * 60 + 1)
        #expect(model.guardrailRuns.isEmpty)
    }

    // MARK: The agent's action (decision 13, eng re-run Section 1 #2)

    @Test func aComebackIsACardUntilItStartsThenARow() async throws {
        let model = try NotifierActionTests.model()
        model.completeOnboarding()
        model.showComebackDemo()
        // Switching person starts its own tick, and only the newest tick's
        // answer applies, so wait for the agent rather than one tick.
        for _ in 0..<50 where model.latestAction == nil {
            await model.tick()
            try await Task.sleep(for: .milliseconds(100))
        }
        let action = try #require(model.latestAction)
        #expect(action.kind == .bookComeback)
        let item = try #require(model.plan.first { $0.id == action.planItemId })
        #expect(model.todayCards.contains(.action(action)))
        let startMinute = Int(item.slot.start.timeIntervalSince(model.storyDay) / 60)
        model.setClockMinutes(startMinute + 1)
        #expect(model.actionUrgency(action) == nil)
        #expect(!model.todayCards.contains(.action(action)))
    }

    // MARK: Fixtures

    static func run(at start: Date, minutes: Double = 150, key: String? = nil) -> PlannedRun {
        PlannedRun(key: key ?? "runna|\(start.timeIntervalSince1970)", title: "Long run", calendarTitle: "Runna",
                   start: start, end: start.addingTimeInterval(minutes * 60),
                   size: .minutes(minutes), isHard: false, isAllDay: false)
    }

    /// Sunday 6:30 PM: the pain question is open, an injury last month offers
    /// the return plan, and tomorrow's 2½-hour long run is a big jump.
    static func sundayBeforeALongRun() throws -> (AppModel, PlannedRun) {
        UserDefaults.standard.removeObject(forKey: AppModel.offerDismissedKey)
        let model = try NotifierActionTests.model()
        model.completeOnboarding()
        model.profile.consentAt = Date().addingTimeInterval(-60 * 86_400)
        ReturnPlanFlowTests.injured(model, monthsAgo: 1)
        let calendar = Calendar.current
        let sunday = PainWeek.asksAt(PainWeek.monday(of: Date(), calendar: calendar), calendar: calendar)
            .addingTimeInterval(30 * 60)
        model.setClockMinutes(Int(sunday.timeIntervalSince(model.storyDay) / 60))
        let run = Self.run(at: sunday.addingTimeInterval(13.5 * 3600))
        model.trainingRuns = [run]
        return (model, run)
    }
}
