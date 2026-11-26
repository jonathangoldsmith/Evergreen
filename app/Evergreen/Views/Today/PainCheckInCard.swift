import SwiftUI

/// Sunday's "How was your week? Any pain?" (plan item 17), from Sunday 6 PM
/// until Tuesday night. A question, so SF Pro and ghost buttons (design
/// decision 14). "No" is done in one tap; "A little" and "Yes" open the
/// OSTRC questions (BN1). VoiceOver reads it as one sentence with the
/// answers as actions (design decision 16).
struct PainCheckInCard: View {
    let week: Date

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    static let ask = "How was your week? Any pain?"
    static let why = "One tap helps me learn whether my suggestions fit you."
    static let thanks = "Thanks. See you next week."

    var body: some View {
        Group {
            if model.painRecord(for: week) != nil {
                // After the answer (design decision 7): one line until the day ends.
                Text(Self.thanks)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
            } else {
                question
            }
        }
        .padding(model.painRecord(for: week) != nil ? Theme.md : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(Self.ask)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(Self.why)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ChoiceRow { answers }
                .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.ask) \(Self.why)")
        .accessibilityActions {
            ForEach(Self.choices, id: \.self) { answer in
                Button(answer.label) { model.answerPain(answer, week: week) }
            }
        }
    }

    private static let choices: [PainAnswer] = [.no, .aLittle, .yes]

    private var answers: some View {
        ForEach(Self.choices, id: \.self) { answer in
            Button(answer.label) { model.answerPain(answer, week: week) }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
