import Foundation
import Testing
@testable import Evergreen

/// The swap card's history line (design decision 12, task G8).
@MainActor
struct HurtAfterJumpTests {
    @Test func aPastYesDayWithASmallerJumpNamesItsMonth() throws {
        let model = try NotifierActionTests.model()
        let august = Fixture.calendar.date(from: DateComponents(year: 2026, month: 8, day: 17))!
        let day = Backtest.Day(date: august, size: .km(16), longest30: .km(12), flagged: true)      // +33%
        model.answerBacktest(.yes, day: day)

        let bigger = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                   keepEasy: false, injuryAdjusted: false)                          // +38%
        let smaller = GuardrailFlag(kind: .spike, planned: .km(14.5), suggested: .km(13), longest30: .km(13),
                                    keepEasy: false, injuryAdjusted: false)                         // +12%
        #expect(model.hurtAfterJumpMonth(for: bigger) == "August")
        #expect(model.hurtAfterJumpMonth(for: smaller) == nil)
    }

    @Test func noAnswersMeansNoLine() throws {
        let model = try NotifierActionTests.model()
        let day = Backtest.Day(date: Fixture.at(8), size: .km(16), longest30: .km(12), flagged: true)
        model.answerBacktest(.no, day: day)
        let flag = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                 keepEasy: false, injuryAdjusted: false)
        #expect(model.hurtAfterJumpMonth(for: flag) == nil)
    }
}
