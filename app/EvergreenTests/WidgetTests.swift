import Foundation
import Testing
@testable import Evergreen

/// The phone widget (TODOS item 1): its links survive the trip, an answer
/// needs the App Group token, an answer becomes the same one decision as a
/// watch tap, and the timeline stops asking once the run has started.
@MainActor
struct WidgetTests {
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "widget-tests-\(UUID().uuidString)")!
    }

    // MARK: Links

    @Test func anAnswerLinkSurvivesTheTrip() throws {
        let link = WidgetLink.answer(runKey: "runna|2030-06-02|Long run 18 km", kind: .accept)
        #expect(WidgetLink(url: link.url(token: "t0k"), token: "t0k") == link)
        #expect(WidgetLink(url: WidgetLink.today.url(token: nil), token: nil) == .today)
    }

    @Test func anAnswerWithoutTheRightTokenIsIgnored() throws {
        let link = WidgetLink.answer(runKey: "runna|x", kind: .keep)
        #expect(WidgetLink(url: link.url(token: "forged"), token: "real") == nil)
        #expect(WidgetLink(url: link.url(token: nil), token: "real") == nil)
        // Before the app has made a token, no answer is accepted, even an empty one.
        #expect(WidgetLink(url: link.url(token: ""), token: nil) == nil)
        #expect(WidgetLink(url: link.url(token: ""), token: "") == nil)
    }

    @Test func otherLinksAreIgnored() throws {
        #expect(WidgetLink(url: URL(string: "https://example.com/answer?run=x&kind=accept&token=t")!, token: "t") == nil)
        #expect(WidgetLink(url: URL(string: "evergreen://answer?run=x&kind=buy&token=t")!, token: "t") == nil)
        #expect(WidgetLink(url: URL(string: "evergreen://answer?kind=accept&token=t")!, token: "t") == nil)
        #expect(WidgetLink(url: URL(string: "evergreen://purchase?token=t")!, token: "t") == nil)
    }

    @Test func theTokenIsMadeOnceAndKept() throws {
        let defaults = Self.defaults()
        #expect(WidgetLink.token(in: defaults) == nil)
        let token = WidgetLink.ensureToken(in: defaults)
        #expect(token.count >= 64)
        #expect(WidgetLink.ensureToken(in: defaults) == token)
        #expect(WidgetLink.token(in: defaults) == token)
    }

    // MARK: Answers

    @Test func aWidgetAnswerIsOneDecisionLikeAWatchTap() async throws {
        let model = try NotifierActionTests.model()
        model.trainingRuns = [WatchAnswerTests.longRun]
        let token = WidgetLink.ensureToken(in: AppModel.widgetDefaults)
        let url = WidgetLink.answer(runKey: WatchAnswerTests.longRun.key, kind: .accept).url(token: token)
        #expect(model.handleWidgetURL(url))
        #expect(model.decisions.map(\.choice) == [.accept])
        // A second tap on the same (stale) widget is dropped.
        #expect(!model.handleWidgetURL(WidgetLink.answer(runKey: WatchAnswerTests.longRun.key, kind: .keep).url(token: token)))
        #expect(model.decisions.map(\.choice) == [.accept])
    }

    @Test func aForgedWidgetAnswerChangesNothing() async throws {
        let model = try NotifierActionTests.model()
        model.trainingRuns = [WatchAnswerTests.longRun]
        WidgetLink.ensureToken(in: AppModel.widgetDefaults)
        let url = WidgetLink.answer(runKey: WatchAnswerTests.longRun.key, kind: .accept).url(token: "forged")
        #expect(!model.handleWidgetURL(url))
        #expect(model.decisions.isEmpty)
    }

    @Test func theWidgetActionEventIsWordsOnly() {
        #expect(AnalyticsEvent.widgetAction("swap").name == "widget_action")
        #expect(AnalyticsEvent.widgetAction("swap").properties == ["kind": "swap"])
        #expect(AnalyticsEvent.widgetAction("sore").properties == ["kind": "check_in"])
    }

    @Test func onlyAChangedStateReloadsTheWidget() {
        let a = WatchState(run: nil, inRange: "5/6", inRangeSpoken: "5 of 6 days in range", today: "Rest day", sentAt: Fixture.at(7))
        var b = a
        b.sentAt = Fixture.at(9)
        #expect(AppModel.sameForWidget(a, b))
        b.inRange = "6/6"
        #expect(!AppModel.sameForWidget(a, b))
    }

    /// A test run must not overwrite what the installed widget shows.
    @Test func aTestRunNeverWritesTheInstalledWidgetsState() throws {
        #expect(AppModel.isTestRun)
        let shared = WidgetLink.sharedDefaults
        let before = shared.data(forKey: "watch_state")
        let model = try NotifierActionTests.model()
        model.pushWidgetState(WatchState(run: nil, inRange: "9/9", inRangeSpoken: "9 of 9 days in range",
                                         today: "Test only", sentAt: Date()))
        #expect(shared.data(forKey: "watch_state") == before)
        #expect(WatchStateStore.load(in: AppModel.widgetDefaults)?.today == "Test only")
    }

    // MARK: Timeline

    static let run = WatchState.Run(key: "runna|long", line: "Sun · Long run 18 km at 6:00 PM", start: Fixture.at(18),
                                    asksCheck: false, question: "Make today's run 13 km?",
                                    acceptLabel: "Make it 13 km", keepLabel: "Keep 18 km")

    static func state(run: WatchState.Run? = run) -> WatchState {
        WatchState(run: run, inRange: "5/6", inRangeSpoken: "5 of 6 days in range", today: "Long run 18 km",
                   tomorrow: "Easy run · 30 min", sentAt: Fixture.at(7))
    }

    @Test func theTimelineStopsAskingWhenTheRunStartsAndRollsOverAtMidnight() throws {
        let moments = WidgetMoment.timeline(Self.state(), now: Fixture.at(8), calendar: Fixture.calendar)
        #expect(moments.map(\.date) == [Fixture.at(8), Fixture.at(18), Fixture.at(0, dayOffset: 1)])
        #expect(moments[0].run == Self.run)
        #expect(moments[1].run == nil)
        #expect(moments[1].line == "Long run 18 km")
        #expect(moments[2].line == "Easy run · 30 min")
        #expect(moments.allSatisfy { $0.inRangeLine == "In range 5/6" })
    }

    @Test func tomorrowsRunKeepsAskingPastMidnight() throws {
        var run = Self.run
        run.start = Fixture.at(8, dayOffset: 1)
        let moments = WidgetMoment.timeline(Self.state(run: run), now: Fixture.at(20), calendar: Fixture.calendar)
        #expect(moments.map(\.date) == [Fixture.at(20), Fixture.at(0, dayOffset: 1)])
        #expect(moments.allSatisfy { $0.run == run })
    }

    @Test func aRunThatHasStartedIsntAskedAbout() throws {
        let moments = WidgetMoment.timeline(Self.state(), now: Fixture.at(19), calendar: Fixture.calendar)
        #expect(moments.count == 2)
        #expect(moments.allSatisfy { $0.run == nil })
    }

    @Test func beforeAnyCountedDayTheRangeSaysSo() {
        let moment = WidgetMoment.timeline(.empty, now: Fixture.at(8), calendar: Fixture.calendar).first
        #expect(moment?.inRangeLine == "In range: —")
        #expect(moment?.line == "Rest day")
    }
}
