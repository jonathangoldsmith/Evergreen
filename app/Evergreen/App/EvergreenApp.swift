import AmplitudeSwift
import SwiftData
import SwiftUI

@main
struct EvergreenApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    /// The one Amplitude client. Nil when no key is set (app/Secrets.xcconfig), so nothing is sent.
    private let amplitude: Amplitude?

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
        let amplitudeKey = Bundle.main.object(forInfoDictionaryKey: "AMPLITUDE_API_KEY") as? String
        if let amplitudeKey, !amplitudeKey.isEmpty, !amplitudeKey.hasPrefix("$(") {
            // The "default" project is in the US data region.
            amplitude = Amplitude(configuration: Configuration(apiKey: amplitudeKey, serverZone: .US))
        } else {
            print("[amplitude] API key is not set — no events will be sent")
            amplitude = nil
        }
        let container = Storage.container()
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext, amplitude: amplitude))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
