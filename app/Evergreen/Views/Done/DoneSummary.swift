import SwiftUI

/// The Done sheet's buddy, points, badge and week line, read by VoiceOver as
/// one sentence. The Nice button stays outside it so VoiceOver can reach it.
struct DoneSummary: View {
    let completion: Completion
    /// The counted-up value currently on screen.
    let shown: Int

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.lg) {
            CelebratingBuddy(filled: tiers)
                .frame(height: 120)
                .accessibilityHidden(true)
            VStack(spacing: Theme.xs) {
                Text("\(shown)")
                    .monospacedDigit()
                    .agentFont(72, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.accent)
                Text("points")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
            }
            if completion.comeback {
                Badge(text: "2× comeback")
            }
            Text("\(model.weekDone) of \(model.weekTotal) this week")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// The buddy's tiers for the week so far, out of three.
    private var tiers: Int {
        let total = max(model.weekTotal, 1)
        return min(3, (model.weekDone * 3 + total - 1) / total)
    }

    private var spoken: String {
        var sentence = "Done. \(completion.points) points"
        if completion.comeback { sentence += ", double for the comeback" }
        return sentence + ". \(model.weekDone) of \(model.weekTotal) this week."
    }
}
