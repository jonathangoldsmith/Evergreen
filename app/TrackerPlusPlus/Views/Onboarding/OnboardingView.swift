import SwiftUI

/// Onboarding (design D16, D15): a one-sentence explainer before each system
/// prompt, ending on "Your normal".
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var busy = false

    var body: some View {
        // Centered when it fits; scrolls at large text sizes or on a short screen
        // such as iPhone Duo's outer display.
        ViewThatFits(in: .vertical) {
            OnboardingStep(step: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            ScrollView {
                OnboardingStep(step: step)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.lg)
            }
        }
        .padding(.horizontal, Theme.lg)
        .safeAreaInset(edge: .bottom) {
            Button(step < 2 ? "Continue" : "Start", action: advance)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                .padding(Theme.lg)
        }
        .background(Theme.surface)
    }

    private func advance() {
        Task { await next() }
    }

    private func next() async {
        busy = true
        defer { busy = false }
        switch step {
        case 0:
            await Permissions.requestHealth()
            step = 1
        case 1:
            await Permissions.requestCalendar()
            await model.tick()
            step = 2
        default:
            model.completeOnboarding()
        }
    }
}
