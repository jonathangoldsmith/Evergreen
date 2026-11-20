import SwiftUI

/// The Lock Screen banner: what's next, when, and what it keeps.
struct WorkoutLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.phase == .done ? "checkmark.circle.fill" : state.symbol)
                .font(.title2)
                .foregroundStyle(Color(.accent))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(Color(.text))
                Text(state.note)
                    .font(.subheadline)
                    .foregroundStyle(Color(.textMuted))
                if state.isComeback && state.phase == .upcoming {
                    Text("2× comeback")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.accent))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.accent), lineWidth: 1)
                        }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.startText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color(.text))
                WorkoutTimeText(state: state)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color(.textMuted))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
    }
}
