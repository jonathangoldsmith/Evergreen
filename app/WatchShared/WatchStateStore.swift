import Foundation

/// The watch's last state in the App Group, so the complication (a separate
/// widget extension) reads what the watch app received (task E22).
enum WatchStateStore {
    static let appGroup = "group.com.evergreentraining.app"
    private static let key = "watch_state"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// The phone saves the same state for its widget; its tests pass their own store.
    static func save(_ state: WatchState, in store: UserDefaults? = nil) {
        (store ?? defaults).set(try? JSONEncoder().encode(state), forKey: key)
    }

    static func load(in store: UserDefaults? = nil) -> WatchState? {
        guard let data = (store ?? defaults).data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchState.self, from: data)
    }
}
