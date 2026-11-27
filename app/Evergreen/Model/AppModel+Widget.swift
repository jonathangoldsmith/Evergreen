import Foundation
import WidgetKit

/// The phone widget (TODOS "Readiness, range, sleep and widgets", item 1): it
/// shows the watch's state, and its answers come back as links that are
/// recorded exactly like a watch tap.
extension AppModel {
    /// Saves today's state for the widget and reloads it, only when the state
    /// changed, so WidgetKit's reload budget isn't spent on the clock ticking.
    func pushWidgetState(_ state: WatchState) {
        WidgetLink.ensureToken()
        if let saved = WatchStateStore.load(), Self.sameForWidget(saved, state) { return }
        WatchStateStore.save(state)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetMoment.kind)
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
        switch WidgetLink(url: url, token: WidgetLink.token()) {
        case .answer(let runKey, let kind):
            return handleWatchAnswer(WatchAnswer(runKey: runKey, kind: kind), from: .widget)
        case .today, nil:
            return false
        }
    }
}
