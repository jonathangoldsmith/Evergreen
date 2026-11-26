import Foundation
import Testing
@testable import Evergreen

/// Watch taps on the phone (range plan item 19, task T8): a queued accept
/// becomes exactly one decision when it arrives, a second answer is dropped,
/// and a tap for a run that has started is dropped.
@MainActor
struct WatchAnswerTests {
    static let run = NotifierActionTests.run
    static let flag = NotifierActionTests.flag

    @Test func theMessagesSurviveTheTrip() throws {
        let answer = WatchAnswer(runKey: "runna|x", kind: .accept)
        #expect(WatchAnswer(answer.encoded()) == answer)
        let state = WatchState(run: .init(key: "k", line: "Sun · Long run", start: Fixture.at(8), asksCheck: true),
                               inRange: "5/6", inRangeSpoken: "5 of 6 days in range", today: "Rest day", sentAt: Fixture.at(7))
        #expect(WatchState(state.encoded()) == state)
    }

    @Test func aWatchTapForAnUnknownOrStartedRunIsDropped() throws {
        let model = try NotifierActionTests.model()
        #expect(!model.handleWatchAnswer(WatchAnswer(runKey: Self.run.key, kind: .accept)))
        #expect(model.decisions.isEmpty)
    }

    @Test func aWatchAnswerAfterThePhonesIsDropped() async throws {
        let model = try NotifierActionTests.model()
        await model.handleNotificationAction(.swapKeep, NotePayload(run: Self.run, flag: Self.flag))
        // The run isn't on a training calendar in tests, so the watch path drops it either way;
        // the phone's one decision stands.
        #expect(!model.handleWatchAnswer(WatchAnswer(runKey: Self.run.key, kind: .accept)))
        #expect(model.decisions.map(\.choice) == [.keep])
    }

    /// Tomorrow's 2½-hour long run: past Jordan's longest this month, so it's flagged.
    static let longRun = PlannedRun(key: "runna|long", title: "Long run 2h 30", calendarTitle: "Runna",
                                    start: NotifierActionTests.start, end: NotifierActionTests.start.addingTimeInterval(9000),
                                    size: .minutes(150), isHard: false, isAllDay: false)

    /// Task T8, both orders, with the run on a training calendar: whichever
    /// answer lands first is the one decision; the second is dropped.
    @Test func theWatchFirstThenTheLockScreen() async throws {
        let model = try NotifierActionTests.model()
        model.trainingRuns = [Self.longRun]
        let flag = try #require(model.flag(for: Self.longRun))
        #expect(model.handleWatchAnswer(WatchAnswer(runKey: Self.longRun.key, kind: .accept)))
        await model.handleNotificationAction(.swapKeep, NotePayload(run: Self.longRun, flag: flag))
        #expect(model.decisions.map(\.choice) == [.accept])
    }

    @Test func theLockScreenFirstThenTheWatch() async throws {
        let model = try NotifierActionTests.model()
        model.trainingRuns = [Self.longRun]
        let flag = try #require(model.flag(for: Self.longRun))
        await model.handleNotificationAction(.swapKeep, NotePayload(run: Self.longRun, flag: flag))
        #expect(!model.handleWatchAnswer(WatchAnswer(runKey: Self.longRun.key, kind: .accept)))
        #expect(model.decisions.map(\.choice) == [.keep])
    }

    @Test func theWatchActionEventIsWordsOnly() {
        #expect(AnalyticsEvent.watchAction("swap").properties == ["kind": "swap"])
        #expect(AnalyticsEvent.watchAction("sore").properties == ["kind": "check_in"])
    }

    @Test func withoutTrainingRunsTheWatchHasNoRunToAnswer() throws {
        let model = try NotifierActionTests.model()
        let state = model.watchState
        #expect(state.run == nil)
        #expect(state.inRange == "—" || state.inRange.contains("/"))
    }
}
