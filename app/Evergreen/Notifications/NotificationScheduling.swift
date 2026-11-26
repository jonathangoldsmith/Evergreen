import UserNotifications

/// The calls Notifier makes on the notification center (eng review D3, task
/// E3), so tests can see what's scheduled without the real center.
@MainActor
protocol NotificationScheduling: AnyObject {
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
    func notificationCategories() async -> Set<UNNotificationCategory>
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

/// The phone's real notification center, unchanged behind the protocol.
@MainActor
final class SystemNotificationCenter: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) { center.delegate = delegate }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func notificationCategories() async -> Set<UNNotificationCategory> { await center.notificationCategories() }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { center.setNotificationCategories(categories) }
}
