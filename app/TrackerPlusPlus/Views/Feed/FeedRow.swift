import SwiftUI

struct FeedRow: View {
    let action: AgentAction

    @Environment(AppModel.self) private var model

    private var undone: Bool { model.isUndone(action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ActionCopy.headline(action))
                    .agentFont(17, relativeTo: .headline)
                    .foregroundStyle(undone ? Theme.textMuted : Theme.accent)
                Spacer()
                Text(action.createdAt.clock)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
            if let change = ActionCopy.beforeAfter(action) {
                change.font(.subheadline).foregroundStyle(Theme.text)
            }
            Text(action.reason)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            if undone {
                Text("Undone")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textMuted)
            } else if action.kind != .note {
                Button("Undo") { model.undo(action) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ActionCopy.spoken(action) + (undone ? " Undone." : ""))
        .accessibilityActions {
            if !undone && action.kind != .note {
                Button("Undo") { model.undo(action) }
            }
        }
    }
}
