import Foundation

/// The watch's last state in the App Group, so the complication (a separate
/// widget extension) reads what the watch app received (task E22).
enum WatchStateStore {
    static let appGroup = "group.com.evergreentraining.app"
    private static let key = "watch_state"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func save(_ state: WatchState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }

    static func load() -> WatchState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchState.self, from: data)
    }
}
