import SwiftUI

/// Sunday's "How was your week? Any pain?" (plan item 17), from Sunday 6 PM
/// until Tuesday night. A question, so SF Pro and ghost buttons (design
/// decision 14). "No" is done in one tap; "A little" and "Yes" open the
/// OSTRC questions (BN1).
struct PainCheckInCard: View {
    let week: Date

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("How was your week? Any pain?")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("One tap helps me learn whether my suggestions fit you.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { answers }
                VStack(spacing: Theme.sm) { answers }
            }
            .padding(.top, Theme.sm)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
    }

    private var answers: some View {
        ForEach([PainAnswer.no, .aLittle, .yes], id: \.self) { answer in
            Button(answer.label) { model.answerPain(answer, week: week) }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
