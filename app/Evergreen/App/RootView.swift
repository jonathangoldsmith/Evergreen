import SwiftUI

/// Onboarding until it's done, then Today, with the demo controls on top.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The toggle on the app's page in iOS Settings (Settings.bundle).
    @AppStorage("demo_controls") private var demoEnabled = false
    @State private var showDemo = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.needsRangeSetup {
                // People who onboarded before the range steps see them once (R8).
                RangeSetupView(catchUp: true, onFinish: {})
            } else if model.onboarded {
                TodayView()
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if demoEnabled && model.onboarded {
                DemoButton(action: openDemo)
                    .padding(Theme.md)
            }
        }
        .sheet(isPresented: $showDemo) { DemoSheet() }
        .tint(Theme.text)
        .task { await model.keepTicking() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.noteAppOpened()
            Task { await model.refreshBuddy() }
            Task {
                if model.persona.key.isReal { await model.refreshHealth() }
                await model.tick()
            }
        }
    }

    private func openDemo() {
        showDemo = true
    }
}
