import WatchConnectivity
import os

/// The phone's end of WatchConnectivity (range plan item 19). It sends today's
/// state as the application context (and to the complication), and hands each
/// watch tap to the app, whether it came as a message or a queued transfer.
final class PhoneWatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.evergreentraining.app", category: "watch")

    /// Called on the main actor with each watch tap.
    @MainActor var onAnswer: ((WatchAnswer) -> Void)?
    private var lastSent: WatchState?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the state if it changed. The complication gets it too, within
    /// iOS's daily budget for complication transfers.
    @MainActor
    func send(_ state: WatchState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var comparable = state
        comparable.sentAt = lastSent?.sentAt ?? state.sentAt
        guard comparable != lastSent else { return }
        lastSent = state
        do {
            try WCSession.default.updateApplicationContext(state.encoded())
            if WCSession.default.isComplicationEnabled, WCSession.default.remainingComplicationUserInfoTransfers > 0 {
                WCSession.default.transferCurrentComplicationUserInfo(state.encoded())
            }
        } catch {
            Self.log.error("Couldn't send the watch state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deliver(_ dictionary: [String: Any]) {
        guard let answer = WatchAnswer(dictionary) else { return }
        Task { @MainActor in self.onAnswer?(answer) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }
}
