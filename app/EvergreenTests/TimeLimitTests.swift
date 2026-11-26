import Foundation
import Testing
@testable import Evergreen

/// `value(within:or:)`, which keeps onboarding's backtest from waiting
/// forever on a Health that never answers.
struct TimeLimitTests {
    @Test func anAnswerInTimeIsKept() async {
        let result = await value(within: .seconds(5), or: 0) { 7 }
        #expect(result == 7)
    }

    @Test func workThatNeverAnswersGivesTheFallback() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await value(within: .milliseconds(200), or: -1) {
            try? await Task.sleep(for: .seconds(30))
            return 7
        }
        #expect(result == -1)
        #expect(clock.now - start < .seconds(5))
    }
}
