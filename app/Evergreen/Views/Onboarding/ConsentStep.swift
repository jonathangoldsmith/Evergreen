import SwiftUI

/// "What leaves your phone" (business notes BN2): asked before anything about
/// the brake is uploaded. Research use is a separate tick, off by default.
struct ConsentStep: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var research = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    Text("What leaves your phone")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("To check my suggestions are right, I send a little to Evergreen's server under an anonymous ID. No name or email. You can delete it any time in Your data.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    list("Sent", symbol: "arrow.up.circle", items: [
                        "Each suggestion and what you chose",
                        "Your weekly pain answer and its follow-up questions",
                        "An injury as yes or no, and how many months ago",
                        "Your answers about last year's runs",
                        "Your week's counts",
                    ])
                    list("Never sent", symbol: "lock", items: [
                        "Your Apple Health data itself",
                        "Where an injury or pain is",
                        "Calendar event titles",
                    ])
                    Toggle(isOn: $research) {
                        Text("Let researchers use my answers, without my name, to study running injuries.")
                            .font(.body)
                            .foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                    // Room for the switch's rounded end inside the scroll view's clip.
                    .padding(.trailing, Theme.xs)
                    .padding(.vertical, Theme.sm)
                    Text("Either way, the brake works on your phone. Sharing with a coach or a friend asks again.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.top, Theme.lg)
            }
            VStack(spacing: Theme.sm) {
                Button("Allow and continue") {
                    model.setConsent(uploads: true, research: research)
                    onDone()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Keep it on my phone") {
                    model.setConsent(uploads: false, research: false)
                    onDone()
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, Theme.md)
        }
        .onAppear { research = model.profile.researchAllowed }
    }

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    private func list(_ title: String, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                // One icon width for both lists, so the text lines up.
                Label {
                    Text(item)
                } icon: {
                    Image(systemName: symbol).frame(width: iconWidth)
                }
                .font(.body)
                .foregroundStyle(Theme.text)
            }
        }
    }
}
