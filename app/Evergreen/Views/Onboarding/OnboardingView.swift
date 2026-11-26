import SwiftUI

/// Onboarding (design decision 3): Welcome, the three permissions on one
/// page, the range setup (what leaves your phone, training calendars, injury),
/// then Today.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.welcome

    /// Pages slide in, or fade under Reduce Motion (design decision 16).
    private var pageTransition: AnyTransition { reduceMotion ? .opacity : .move(edge: .trailing) }

    enum Page { case welcome, permissions, range, friend }

    var body: some View {
        Group {
            switch page {
            case .welcome:
                WelcomeView(onStart: { page = .permissions }, onFriendCode: { page = .friend })
            case .permissions:
                PermissionsView(onContinue: { page = .range })
                    .transition(pageTransition)
            case .range:
                RangeSetupView(onFinish: finish)
                    .transition(pageTransition)
            case .friend:
                FriendSetupView(onBack: { page = .welcome })
                    .transition(pageTransition)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: page)
    }

    private func finish() {
        Task {
            await model.tick()
            model.completeOnboarding()
        }
    }
}
