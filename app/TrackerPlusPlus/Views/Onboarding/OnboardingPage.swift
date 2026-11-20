import SwiftUI

/// An explainer shown before a system permission prompt (design D16).
struct OnboardingPage: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(title)
                .agentFont(28, relativeTo: .title)
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
