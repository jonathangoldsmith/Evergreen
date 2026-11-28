import UserNotifications
import os

/// Local notifications; there's no push backend yet: a reminder before each
/// workout. Mock pushes in app/MockPushes go through the same delegate.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let reminderLead: TimeInterval = 30 * 60
    private static let log = Logger(subsystem: "com.evergreentraining.app", category: "notifications")

    private let center: any NotificationScheduling
    private(set) var access: NotificationAccess = .notAsked

    /// Called when someone taps a notification, so the app can look again.
    var onOpen: (@MainActor () -> Void)?
    /// Called for a Lock Screen button (plan items 7 and 17), often with the
    /// app in the background. The app records the answer before this returns.
    var onAction: (@MainActor (NotificationAction, NotePayload?) async -> Void)?

    /// The real center by default; tests pass their own (eng review D3).
    init(center: any NotificationScheduling = SystemNotificationCenter()) {
        self.center = center
        super.init()
        center.setDelegate(self)
        center.setNotificationCategories(NotificationAction.fixedCategories)
    }

    // MARK: Access

    func refreshAccess() async {
        let status = await center.authorizationStatus()
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

    // MARK: Guardrail notes (plan items 7 and 17)

    /// Replaces every pending guardrail note with `notes`, each with its
    /// buttons and the payload its action needs.
    func scheduleGuardrail(_ notes: [GuardrailNote]) async {
        guard access == .on else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("guardrail-") })
        var categories = NotificationAction.fixedCategories
        for note in notes {
            let category: String?
            switch note.kind {
            case .swap:
                guard let flag = note.flag else { continue }
                category = NotificationAction.swapCategoryPrefix + note.id
                categories.insert(NotificationAction.swapCategory(id: note.id, flag: flag))
            case .morningCheck:
                category = NotificationAction.morningCheckCategory
            case .pain:
                category = NotificationAction.painCategory
            case .bedtime:
                category = nil
            }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: note.fireAt)
            let payload = NotePayload(run: note.run, flag: note.flag, weekStart: note.weekStart)
            await add(note.id, (note.title, note.body),
                      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false),
                      category: category, userInfo: payload.userInfo())
        }
        center.setNotificationCategories(categories)
    }

    /// A note right away with buttons, such as "Changed to 12 km" with Undo,
    /// or a swap question after a "Sore" answered from the Lock Screen.
    func sendNow(_ copy: (title: String, body: String), id: String, category: UNNotificationCategory?,
                 payload: NotePayload) async {
        guard access == .on else { return }
        if let category {
            var categories = await center.notificationCategories()
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
        await add("now-\(id)", copy, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false),
                  category: category?.identifier, userInfo: payload.userInfo())
    }

    // MARK: Now

    /// A notification right away, such as "I moved your run". It shows as a
    /// banner even with the app open.
    func send(_ copy: (title: String, body: String), id: String) async {
        guard access == .on else { return }
        await add("now-\(id)", copy, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    }

    // MARK: Shared

    private func add(_ id: String, _ copy: (title: String, body: String), trigger: UNNotificationTrigger,
                     category: String? = nil, userInfo: [String: Any] = ["open": "today"]) async {
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }
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

    /// A tap opens the app; a button records its answer, with the app in the
    /// background when the button doesn't open it (eng review Section 1 #1).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let payload = NotePayload(userInfo: response.notification.request.content.userInfo)
        await handle(identifier, payload)
    }

    /// A tap (any identifier that isn't one of the buttons) opens the app;
    /// a button runs its action. Internal so tests can drive it, since a
    /// UNNotificationResponse can't be made outside the system.
    func handle(_ identifier: String, _ payload: NotePayload?) async {
        if let action = NotificationAction(rawValue: identifier), let onAction {
            await onAction(action, payload)
        } else {
            onOpen?()
        }
    }
}
