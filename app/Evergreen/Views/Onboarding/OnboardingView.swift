import SwiftUI

/// Onboarding: Welcome, then the three permissions on one page, then Today.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showPermissions = false

    var body: some View {
        Group {
            if showPermissions {
                PermissionsView(onContinue: finish)
                    .transition(.move(edge: .trailing))
            } else {
                WelcomeView(onStart: start)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showPermissions)
    }

    private func start() {
        showPermissions = true
    }

    private func finish() {
        Task {
            await model.tick()
            model.completeOnboarding()
        }
    }
}
