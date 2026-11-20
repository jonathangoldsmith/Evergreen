import SwiftUI

/// The content of one onboarding step.
struct OnboardingStep: View {
    let step: Int

    var body: some View {
        switch step {
        case 0:
            OnboardingPage(symbol: "heart.text.square",
                           title: "I read your workouts to learn your normal.",
                           message: "Nothing leaves your phone except summaries.")
        case 1:
            OnboardingPage(symbol: "calendar",
                           title: "I add workouts to my own TrackerPlusPlus calendar.",
                           message: "And I move them when something else lands on top.")
        default:
            YourNormalView()
        }
    }
}
