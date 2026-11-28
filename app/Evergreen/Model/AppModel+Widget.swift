import Foundation
import WidgetKit

/// The phone widget (TODOS "Readiness, range, sleep and widgets", item 1): it
/// shows the watch's state, and its answers come back as links that are
/// recorded exactly like a watch tap.
extension AppModel {
    /// Where the widget's state and link token live: the App Group, except in
    /// a test run, which gets a store of its own so it never overwrites what
    /// the installed widget shows.
    nonisolated(unsafe) static let widgetDefaults: UserDefaults = {
        if isTestRun, let tests = UserDefaults(suiteName: "evergreen-widget-tests") { return tests }
        return WidgetLink.sharedDefaults
    }()

    nonisolated static var isTestRun: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Saves today's state for the widget and reloads it, only when the state
    /// changed, so WidgetKit's reload budget isn't spent on the clock ticking.
    func pushWidgetState(_ state: WatchState) {
        let store = Self.widgetDefaults
        WidgetLink.ensureToken(in: store)
        if let saved = WatchStateStore.load(in: store), Self.sameForWidget(saved, state) { return }
        WatchStateStore.save(state, in: store)
        if !Self.isTestRun { WidgetCenter.shared.reloadTimelines(ofKind: WidgetMoment.kind) }
    }

    nonisolated static func sameForWidget(_ a: WatchState, _ b: WatchState) -> Bool {
        var a = a
        a.sentAt = b.sentAt
        return a == b
    }

    /// An `evergreen://` link from the widget. Opening Today needs nothing
    /// more; an answer needs the App Group token and is then a watch tap.
    @discardableResult
    func handleWidgetURL(_ url: URL) -> Bool {
        switch WidgetLink(url: url, token: WidgetLink.token(in: Self.widgetDefaults)) {
        case .answer(let runKey, let kind):
            return handleWatchAnswer(WatchAnswer(runKey: runKey, kind: kind), from: .widget)
        case .today, nil:
            return false
        }
    }
}
