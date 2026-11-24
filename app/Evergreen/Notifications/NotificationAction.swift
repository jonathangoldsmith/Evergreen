import Foundation
import UserNotifications

/// The guardrail's Lock Screen buttons (plan items 7 and 17). Answers that
/// need no screen run in the background; "A little" and "Yes" open the app
/// for the OSTRC questions (business notes BN1).
enum NotificationAction: String, CaseIterable, Sendable {
    case swapAccept = "swap.accept"
    case swapKeep = "swap.keep"
    case swapUndo = "swap.undo"
    case checkFresh = "check.fresh"
    case checkTired = "check.tired"
    case checkSore = "check.sore"
    case painNo = "pain.no"
    case painALittle = "pain.aLittle"
    case painYes = "pain.yes"

    static let morningCheckCategory = "MORNING_CHECK"
    static let painCategory = "PAIN_CHECKIN"
    static let swapDoneCategory = "SWAP_DONE"
    /// One swap category per note, since its buttons name the sizes.
    static let swapCategoryPrefix = "SWAP-"

    var morningCheck: MorningCheck? {
        switch self {
        case .checkFresh: .fresh
        case .checkTired: .tired
        case .checkSore: .sore
        default: nil
        }
    }

    var painAnswer: PainAnswer? {
        switch self {
        case .painNo: .no
        case .painALittle: .aLittle
        case .painYes: .yes
        default: nil
        }
    }

    static func action(_ action: NotificationAction, _ title: String, opensApp: Bool = false) -> UNNotificationAction {
        UNNotificationAction(identifier: action.rawValue, title: title, options: opensApp ? [.foreground] : [])
    }

    /// The categories that never change.
    static var fixedCategories: Set<UNNotificationCategory> {
        [
        UNNotificationCategory(identifier: morningCheckCategory, actions: [
            action(.checkFresh, "Fresh"), action(.checkTired, "Tired"), action(.checkSore, "Sore"),
        ], intentIdentifiers: []),
        UNNotificationCategory(identifier: painCategory, actions: [
            action(.painNo, "No"), action(.painALittle, "A little", opensApp: true), action(.painYes, "Yes", opensApp: true),
        ], intentIdentifiers: []),
        UNNotificationCategory(identifier: swapDoneCategory, actions: [action(.swapUndo, "Undo")], intentIdentifiers: []),
        ]
    }

    /// "Make it 12 km" / "Keep 18 km" for one swap note.
    static func swapCategory(id: String, flag: GuardrailFlag) -> UNNotificationCategory {
        UNNotificationCategory(identifier: swapCategoryPrefix + id, actions: [
            action(.swapAccept, GuardrailCopy.accept(flag)), action(.swapKeep, GuardrailCopy.keep(flag)),
        ], intentIdentifiers: [])
    }
}
