import SwiftData
import SwiftUI

@main
struct TrackerPlusPlusApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        Theme.registerFonts()
        #if DEBUG
        // Builds run from Xcode (simulator or phone) start with the demo
        // controls on. Written, not registered, so the toggle in iOS Settings
        // shows it and can still turn it off. Release builds stay off (D13).
        if UserDefaults.standard.object(forKey: "demo_controls") == nil {
            UserDefaults.standard.set(true, forKey: "demo_controls")
        }
        #endif
        let container = Storage.container()
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
