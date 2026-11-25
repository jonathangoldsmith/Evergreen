import Foundation
import Testing
@testable import Evergreen

/// The return plan's life on the model (range plan item 21): offered after a
/// recent injury, started on a yes, paused by a "Yes" pain answer, resumed at
/// the paused week, ended with Undo, and external runs paused meanwhile.
@MainActor
struct ReturnPlanFlowTests {
    static func injured(_ model: AppModel, monthsAgo: Int) {
        let month = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date())!
        model.setInjury(month: month)
    }

    @Test func aRecentInjuryOffersThePlanAndAnOldOneDoesnt() throws {
        let model = try NotifierActionTests.model()
        #expect(!model.offersReturnPlan)
        Self.injured(model, monthsAgo: 5)
        #expect(!model.offersReturnPlan)
        Self.injured(model, monthsAgo: 1)
        #expect(model.offersReturnPlan)
        model.dismissReturnOffer()
        #expect(!model.offersReturnPlan)
    }

    @Test func startingPutsSessionsOnThePlan() throws {
        let model = try NotifierActionTests.model()
        Self.injured(model, monthsAgo: 0)
        model.startReturnPlan(weekdays: Set(1...7), startMinute: 23 * 60 + 59)
        #expect(!model.offersReturnPlan)
        #expect(model.returnPlan?.status == .active)
        #expect(model.returnSessions.count == 28 || model.returnSessions.count == 27)
        #expect(model.returnItems.allSatisfy { $0.source == .returnSession })
        #expect(!model.returnItems.isEmpty)
        #expect(model.returnTitles.values.contains("Walk-run 20 min: 1 min run, 2 min walk"))
    }

    @Test func aYesPainAnswerPausesItAndResumingPicksUpThatWeek() throws {
        let model = try NotifierActionTests.model()
        model.setConsent(uploads: false, research: false)
        model.startReturnPlan(weekdays: Set(1...7), startMinute: 23 * 60 + 59)
        let plan = try #require(model.returnPlan)
        model.answerPain(.yes, week: PainWeek.monday(of: Date(), calendar: .current))
        #expect(plan.status == .paused && plan.pausedWeek == 0)
        #expect(model.returnItems.isEmpty)
        #expect(!model.offersReturnPlan)
        model.resumeReturnPlan()
        #expect(plan.status == .active && plan.fromWeek == 0)
    }

    @Test func endingHasUndo() throws {
        let model = try NotifierActionTests.model()
        model.startReturnPlan(weekdays: [2, 4, 7], startMinute: 420)
        model.endReturnPlan()
        #expect(model.returnPlan?.status == .ended && model.returnItems.isEmpty)
        model.undoEndReturnPlan()
        #expect(model.returnPlan?.status == .active)
    }

    @Test func externalRunsArePausedOnlyWhileThePlanRuns() throws {
        let model = try NotifierActionTests.model()
        let start = Date().addingTimeInterval(2 * 86_400)
        let run = PlannedRun(key: "runna|x|Long run 18 km", title: "Long run 18 km", calendarTitle: "Runna", start: start,
                             end: start.addingTimeInterval(5400), size: .km(18), isHard: false, isAllDay: false)
        #expect(!model.isPausedForReturn(run))
        model.startReturnPlan(weekdays: [2, 4, 7], startMinute: 420)
        #expect(model.isPausedForReturn(run))
        model.pauseReturnPlan()
        #expect(model.isPausedForReturn(run))
        model.endReturnPlan()
        #expect(!model.isPausedForReturn(run))
    }
}
