import SwiftUI

/// The Done sheet's points, badge and week line, read by VoiceOver as one
/// sentence. The Nice button stays outside it so VoiceOver can reach it.
struct DoneSummary: View {
    let completion: Completion
    /// The counted-up value currently on screen.
    let shown: Int

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.lg) {
            Text("Done")
                .font(.headline)
                .foregroundStyle(Theme.textMuted)
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
            if let response = model.response {
                Text("\(response.weekDone) of \(response.normal.weeklyTarget) this week")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var sentence = "Done. \(completion.points) points"
        if completion.comeback { sentence += ", double for the comeback" }
        if let response = model.response {
            sentence += ". \(response.weekDone) of \(response.normal.weeklyTarget) this week"
        }
        return sentence + "."
    }
}
