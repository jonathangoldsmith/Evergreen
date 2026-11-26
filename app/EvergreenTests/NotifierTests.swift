import Foundation
import Testing
import UserNotifications
@testable import Evergreen

/// Notifier as it behaves today (eng review D3, task E3): access follows the
/// system, today's notifications still schedule, and a tap still opens the
/// app. Written before any change to it, on a fake notification center.
@MainActor
struct NotifierTests {
    /// Records what Notifier asks of the notification center.
    final class FakeCenter: NotificationScheduling {
        var status: UNAuthorizationStatus = .authorized
        var requests: [UNNotificationRequest] = []
        var removed: [String] = []
        var categories: Set<UNNotificationCategory> = []
        var delegateSet = false
        var authorizationAsked = false

        func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) { delegateSet = true }
        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            authorizationAsked = true
            status = .authorized
            return true
        }
        func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removed += identifiers
            requests.removeAll { identifiers.contains($0.identifier) }
        }
        func add(_ request: UNNotificationRequest) async throws {
            requests.removeAll { $0.identifier == request.identifier }
            requests.append(request)
        }
        func notificationCategories() async -> Set<UNNotificationCategory> { categories }
        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }

        func request(_ id: String) -> UNNotificationRequest? { requests.first { $0.identifier == id } }
    }

    static func notifier(_ status: UNAuthorizationStatus = .authorized) async -> (Notifier, FakeCenter) {
        let center = FakeCenter()
        center.status = status
        let notifier = Notifier(center: center)
        await notifier.refreshAccess()
        return (notifier, center)
    }

    static func item(_ id: String, startsIn: TimeInterval, minutes: Double = 30) -> PlanItem {
        let start = Date.now.addingTimeInterval(startsIn)
        return PlanItem(id: id, slot: Slot(start: start, end: start.addingTimeInterval(minutes * 60), activityType: "Running"),
                        points: 20, source: .plan)
    }

    @Test func itBecomesTheDelegateWithTheFixedCategories() async {
        let (_, center) = await Self.notifier()
        #expect(center.delegateSet)
        #expect(center.categories == NotificationAction.fixedCategories)
    }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, NotificationAccess.on), (.provisional, .on), (.ephemeral, .on),
        (.notDetermined, .notAsked), (.denied, .off),
    ])
    func accessFollowsTheSystemSetting(status: UNAuthorizationStatus, access: NotificationAccess) async {
        let (notifier, _) = await Self.notifier(status)
        #expect(notifier.access == access)
    }

    @Test func askingForAccessAsksTheSystemThenRereadsIt() async {
        let (notifier, center) = await Self.notifier(.notDetermined)
        await notifier.requestAccess()
        #expect(center.authorizationAsked && notifier.access == .on)
    }

    @Test func withAccessOffNothingIsScheduled() async {
        let (notifier, center) = await Self.notifier(.denied)
        await notifier.scheduleReminders(for: [Self.item("a", startsIn: 7200)])
        await notifier.send(("Evergreen", "I moved your run"), id: "move")
        #expect(center.requests.isEmpty)
    }

    @Test func remindersAreThirtyMinutesBeforeEachWorkoutThisWeek() async throws {
        let (notifier, center) = await Self.notifier()
        // Old reminders are replaced; other notes are left alone.
        let keep = UNNotificationRequest(identifier: "guardrail-pain-1", content: UNNotificationContent(), trigger: nil)
        let stale = UNNotificationRequest(identifier: "reminder-old-1", content: UNNotificationContent(), trigger: nil)
        center.requests = [keep, stale]

        let soon = Self.item("soon", startsIn: 2 * 3600)
        let started = Self.item("started", startsIn: 10 * 60)           // its reminder time has passed
        let nextWeek = Self.item("later", startsIn: 8 * 24 * 3600)      // past the 7-day horizon
        await notifier.scheduleReminders(for: [soon, started, nextWeek])

        #expect(center.removed == ["reminder-old-1"])
        let ids = center.requests.map(\.identifier)
        let id = "reminder-soon-\(Int(soon.slot.start.timeIntervalSince1970))"
        #expect(ids.sorted() == ["guardrail-pain-1", id].sorted())

        let reminder = try #require(center.request(id))
        #expect(reminder.content.title == NotificationCopy.reminder(soon).title)
        #expect(reminder.content.body == NotificationCopy.reminder(soon).body)
        #expect(reminder.content.userInfo["open"] as? String == "today")      // a tap opens Today
        let trigger = try #require(reminder.trigger as? UNCalendarNotificationTrigger)
        let fires = try #require(Calendar.current.date(from: trigger.dateComponents))
        let expected = soon.slot.start.addingTimeInterval(-Notifier.reminderLead)
        #expect(abs(fires.timeIntervalSince(expected)) < 60)                  // to the minute
        #expect(!trigger.repeats)
    }

    @Test func aNoteNowShowsInASecond() async throws {
        let (notifier, center) = await Self.notifier()
        await notifier.send(("Evergreen", "I moved your run to 7 PM."), id: "move-1")
        let note = try #require(center.request("now-move-1"))
        #expect(note.content.body == "I moved your run to 7 PM.")
        let trigger = try #require(note.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 1 && !trigger.repeats)
    }

    @Test func aSwapNoteCarriesItsButtonsAndThePayloadItsActionNeeds() async throws {
        let (notifier, center) = await Self.notifier()
        let run = GuardrailCopyTests.run, flag = GuardrailCopyTests.flags[0]
        let note = GuardrailNote(kind: .swap, fireAt: Date.now.addingTimeInterval(3600), title: "Evergreen",
                                 body: "Make it 13?", run: run, flag: flag)
        await notifier.scheduleGuardrail([note])

        let request = try #require(center.request(note.id))
        #expect(request.content.categoryIdentifier == NotificationAction.swapCategoryPrefix + note.id)
        let payload = try #require(NotePayload(userInfo: request.content.userInfo))
        #expect(payload.run?.key == run.key && payload.flag == flag)
        #expect(center.categories.isSuperset(of: NotificationAction.fixedCategories))
        #expect(center.categories.contains { $0.identifier == request.content.categoryIdentifier })
    }

    @Test func aTapOpensTheAppAndAButtonRunsItsAction() async {
        let (notifier, _) = await Self.notifier()
        var opened = 0
        var actions: [NotificationAction] = []
        notifier.onOpen = { opened += 1 }
        notifier.onAction = { action, _ in actions.append(action) }

        await notifier.handle(UNNotificationDefaultActionIdentifier, nil)
        await notifier.handle(NotificationAction.painNo.rawValue, nil)
        #expect(opened == 1)
        #expect(actions == [.painNo])
    }
}
