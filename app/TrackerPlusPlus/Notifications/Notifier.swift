import CoreLocation
import UserNotifications
import os

/// Local notifications; there's no push backend yet. Three kinds of trigger:
/// a calendar time (the reminder before each workout), a timer (the demo's
/// "send a test notification"), and a place (arriving at or leaving the gym).
/// Mock pushes in app/MockPushes go through the same delegate.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let reminderLead: TimeInterval = 30 * 60
    private static let gymAlertsKey = "gym_alerts"
    private static let log = Logger(subsystem: "com.trackerplusplus.app", category: "notifications")

    private let center = UNUserNotificationCenter.current()
    private let location = LocationPermission()
    private(set) var access: NotificationAccess = .notAsked

    /// Called when someone taps a notification, so the app can look again.
    var onOpen: (@MainActor () -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    var gymAlertsOn: Bool {
        UserDefaults.standard.bool(forKey: Self.gymAlertsKey) && location.isAuthorized
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

    // MARK: Timer trigger: test notification

    /// Demo control: what the agent last did, as a notification in a few
    /// seconds, so the presenter can lock the phone first.
    func sendTestNotification(for action: AgentAction?, fallback: PlanItem?, now: Date, after seconds: TimeInterval) async {
        let copy = action.map { NotificationCopy.action($0, now: now) }
            ?? fallback.map(NotificationCopy.reminder)
            ?? ("TrackerPlusPlus", "This is a test notification.")
        await add("test-\(UUID().uuidString)", copy,
                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
    }

    // MARK: Location trigger: gym arrival and departure

    /// Turns on gym alerts: asks for location the first time, then watches the
    /// demo gym. Returns whether they're on.
    @discardableResult
    func enableGymAlerts(next: PlanItem?) async -> Bool {
        guard await location.request() else { return false }
        UserDefaults.standard.set(true, forKey: Self.gymAlertsKey)
        await scheduleGymAlerts(next: next)
        return true
    }

    /// Demo control: the arrival or departure notification in 3 seconds. The
    /// iOS 27 simulator doesn't fire location triggers ("Couldn't get fences"
    /// in locationd), so this is how the demo shows them; a phone uses the
    /// real geofence above.
    func sendGymNotification(arriving: Bool, next: PlanItem?) async {
        let copy = arriving ? NotificationCopy.gymArrival(next: next) : NotificationCopy.gymExit
        await add("gym-demo-\(UUID().uuidString)", copy,
                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
    }

    func disableGymAlerts() {
        UserDefaults.standard.set(false, forKey: Self.gymAlertsKey)
        center.removePendingNotificationRequests(withIdentifiers: ["gym-arrive", "gym-leave"])
    }

    /// Re-adds both geofences so the arrival line names the current next workout.
    func scheduleGymAlerts(next: PlanItem?) async {
        guard gymAlertsOn, access == .on else { return }
        await add("gym-arrive", NotificationCopy.gymArrival(next: next), trigger: gymTrigger(entry: true))
        await add("gym-leave", NotificationCopy.gymExit, trigger: gymTrigger(entry: false))
        let pending = await center.pendingNotificationRequests().count
        Self.log.info("Scheduled gym alerts; \(pending) notifications pending")
    }

    private func gymTrigger(entry: Bool) -> UNLocationNotificationTrigger {
        let region = CLCircularRegion(center: Gym.center, radius: Gym.radius,
                                      identifier: entry ? "gym-arrive" : "gym-leave")
        region.notifyOnEntry = entry
        region.notifyOnExit = !entry
        return UNLocationNotificationTrigger(region: region, repeats: true)
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
