import SwiftUI

/// Onboarding screen 1: the mark, the buddy waving hi, Evergreen's promise, Let's go.
struct WelcomeView: View {
    let onStart: () -> Void
    /// A friend's buddy invite: the short path (range plan item 22).
    var onFriendCode: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()
            Spacer(minLength: Theme.lg)
            WavingBuddy(loops: true)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
            Spacer(minLength: Theme.lg)
            Text("Training that grows with you.")
                .agentFont(40, relativeTo: .largeTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("I’m Evergreen. I read your Apple Health data and your calendar, then pick the right workout for your body and the time you actually have.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, Theme.md)
            Button("Let’s go", action: onStart)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 40)
            if let onFriendCode {
                Button("Have a code from a friend?", action: onFriendCode)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, Theme.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.lg)
        .padding(.top, Theme.xl)
        .padding(.bottom, Theme.lg)
        .background(Theme.surface)
    }
}

/// The Evergreen mark: the pine buddy on a soft mint tile.
struct AppMark: View {
    var body: some View {
        PineBuddy()
            .frame(height: 46)
            .frame(width: 56, height: 56)
            .background(Color(red: 0.89, green: 0.95, blue: 0.92), in: .rect(cornerRadius: 16, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Evergreen")
    }
}
