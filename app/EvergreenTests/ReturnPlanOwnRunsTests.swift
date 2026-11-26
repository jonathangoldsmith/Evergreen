import Foundation
import Testing
@testable import Evergreen

/// Evergreen's own runs step aside during a return plan (item 21).
@MainActor
struct ReturnPlanOwnRunsTests {
    @Test func ownRunsPauseButStrengthStays() throws {
        let model = try NotifierActionTests.model()
        let before = model.plan.filter { $0.source == .plan && $0.slot.start > Date() }
        model.startReturnPlan(weekdays: [2, 4, 7], startMinute: 420)
        let after = model.plan.filter { $0.source == .plan && $0.slot.start > Date() }
        #expect(after.allSatisfy { $0.slot.activityType != "Running" })
        // Strength stays, except on a session's day: one workout a day, and the session wins.
        let sessionDays = Set(model.returnSessions.map { model.calendar.startOfDay(for: $0.start) })
        let kept = before.filter {
            $0.slot.activityType != "Running" && !sessionDays.contains(model.calendar.startOfDay(for: $0.slot.start))
        }
        #expect(after.count == kept.count)
        model.endReturnPlan()
        #expect(model.plan.filter { $0.source == .plan && $0.slot.start > Date() }.count == before.count)
    }
}
