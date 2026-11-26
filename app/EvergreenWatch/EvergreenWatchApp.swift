import SwiftUI

/// Evergreen on Apple Watch (range plan item 19): today's run, the morning
/// check and the swap, answered from the wrist. The phone runs the rule.
@main
struct EvergreenWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(link)
                .task { link.start() }
        }
        // A complication transfer from the phone wakes the watch in the background;
        // the link applies it and reloads the complication (task E22).
        .backgroundTask(.watchConnectivity) {
            await MainActor.run { link.start() }
        }
    }
}
