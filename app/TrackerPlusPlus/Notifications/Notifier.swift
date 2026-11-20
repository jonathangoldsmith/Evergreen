import UserNotifications
import os

/// Local notifications; there's no push backend yet: a reminder before each
/// workout. Mock pushes in app/MockPushes go through the same delegate.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let reminderLead: TimeInterval = 30 * 60
    private static let log = Logger(subsystem: "com.trackerplusplus.app", category: "notifications")

    private let center = UNUserNotificationCenter.current()
    private(set) var access: NotificationAccess = .notAsked

    /// Called when someone taps a notification, so the app can look again.
    var onOpen: (@MainActor () -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: Access

    func refreshAccess() async {
        let status = await center.notificationSettings().authorizationStatus
        access = switch status {
        case .authorized, .provisional, .ephemeral: .on
        case .notDetermined: .notAsked
        default: .off
        }
    }

    func requestAccess() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.log.error("Notification request failed: \(error.localizedDescription)")
        }
        await refreshAccess()
    }

    // MARK: Calendar trigger: reminders

    /// One reminder 30 minutes before each upcoming workout in the next week
    /// (plan item 16), replaced on every change so moves and undos carry over.
    /// They fire on the phone's real clock, not the demo clock.
    func scheduleReminders(for items: [PlanItem]) async {
        guard access == .on else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("reminder-") })
        let horizon = Date.now.addingTimeInterval(7 * 24 * 3600)
        for item in items {
            let at = item.slot.start.addingTimeInterval(-Self.reminderLead)
            guard at > .now, at < horizon else { continue }
            let copy = NotificationCopy.reminder(item)
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            await add("reminder-\(item.id)-\(Int(item.slot.start.timeIntervalSince1970))", copy,
                      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    // MARK: Now

    /// A notification right away, such as "I moved your run". It shows as a
    /// banner even with the app open.
    func send(_ copy: (title: String, body: String), id: String) async {
        guard access == .on else { return }
        await add("now-\(id)", copy, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    }

    // MARK: Shared

    private func add(_ id: String, _ copy: (title: String, body: String), trigger: UNNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = ["open": "today"]
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            Self.log.error("Couldn't schedule \(id): \(error.localizedDescription)")
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even with the app open, so the demo can see them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onOpen?() }
    }
}
