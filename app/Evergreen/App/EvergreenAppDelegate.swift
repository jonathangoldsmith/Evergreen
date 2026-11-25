import HealthKit
import UIKit

/// The app delegate the plan's buddy needs (range plan item 22, outside voice
/// #5): it receives the push token and registers HealthKit's workout observer
/// at launch, so a finished workout wakes the app even when it's closed.
final class EvergreenAppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the app once its model exists.
    @MainActor static var model: AppModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WorkoutObserver.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await Self.model?.pushTokenArrived(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token means no buddy notes on this device; the app works the same otherwise.
    }
}
