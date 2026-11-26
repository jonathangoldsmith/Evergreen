import SwiftData
import SwiftUI

@main
struct EvergreenApp: App {
    @UIApplicationDelegateAdaptor(EvergreenAppDelegate.self) private var appDelegate
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
        // The client is made only once uploads are allowed (BN2): even an
        // opted-out client fetches Amplitude's remote config at launch.
        var amplitudeKey = Bundle.main.object(forInfoDictionaryKey: "AMPLITUDE_API_KEY") as? String
        if amplitudeKey?.isEmpty != false || amplitudeKey?.hasPrefix("$(") == true {
            print("[amplitude] API key is not set — no events will be sent")
            amplitudeKey = nil
        }
        let container = Storage.container()
        self.container = container
        let model = AppModel(context: container.mainContext, amplitudeKey: amplitudeKey)
        _model = State(initialValue: model)
        EvergreenAppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
