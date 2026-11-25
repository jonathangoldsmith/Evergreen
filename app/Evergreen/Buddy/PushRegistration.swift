import UIKit

/// Asks iOS for this device's push token (buddy notes, range plan item 22).
enum PushRegistration {
    @MainActor
    static func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
