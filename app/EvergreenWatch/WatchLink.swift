import Observation
import WatchConnectivity

/// The watch's end of WatchConnectivity: the last state the phone sent, and
/// taps sent back right away or queued until the phone is in reach.
@Observable
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    private(set) var state: WatchState = WatchLink.saved() ?? .empty
    /// Taps sent while the phone was away, by run key: "Will sync with your phone".
    private(set) var queued: [String: WatchAnswer.Kind] = [:]

    private static let savedKey = "watch_state"

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func answer(_ kind: WatchAnswer.Kind, for runKey: String) {
        let answer = WatchAnswer(runKey: runKey, kind: kind)
        if WCSession.default.activationState == .activated, WCSession.default.isReachable {
            WCSession.default.sendMessage(answer.encoded(), replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(answer.encoded())
            }
        } else {
            WCSession.default.transferUserInfo(answer.encoded())
            queued[runKey] = kind
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let state = WatchState(context) else { return }
        Task { @MainActor in
            self.state = state
            // The phone's state is the truth: anything it decided is no longer waiting.
            self.queued = self.queued.filter { key, _ in state.run?.key == key && state.run?.decided == nil }
            UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: Self.savedKey)
        }
    }

    private static func saved() -> WatchState? {
        guard let data = UserDefaults.standard.data(forKey: savedKey) else { return nil }
        return try? JSONDecoder().decode(WatchState.self, from: data)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }
}
