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

    /// No clock checks: on a busy Mac they fail for reasons that aren't the code's.
    @Test func workThatNeverAnswersGivesTheFallback() async {
        // Like a HealthKit query that's never answered: nothing arrives until
        // the test finishes the stream. The continuation is kept until then,
        // because dropping it would end the stream and answer at once.
        let (never, continuation) = AsyncStream<Int>.makeStream()
        let result = await value(within: .milliseconds(100), or: -1) {
            for await answer in never { return answer }
            return 7
        }
        #expect(result == -1)
        // The late answer arrives after the fallback; it must not resume twice.
        continuation.finish()
    }
}
