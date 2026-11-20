import SwiftUI

/// The one card in the app (design D8): the agent's latest action on Today.
struct AgentCard: View {
    let action: AgentAction

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var picking = false

    private var item: PlanItem? {
        guard let id = action.planItemId else { return nil }
        return model.plan.first { $0.id == id }
    }

    /// Once the workout this action set up is done, the card stops asking.
    private var finished: Completion? {
        item.flatMap { model.completion(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(ActionCopy.headline(action))
                    .agentFont(22, relativeTo: .title2)
            } icon: {
                Image(systemName: ActionCopy.symbol(action))
            }
            .foregroundStyle(Theme.accent)

            if let lead = ActionCopy.lead(action, now: model.now) {
                Text(lead).font(.body).foregroundStyle(Theme.text)
            }
            if let change = ActionCopy.beforeAfter(action) {
                change.font(.body).foregroundStyle(Theme.text)
            }
            if action.kind == .bookComeback {
                Badge(text: "2× comeback")
            }
            if let finished {
                Label("Done: \(finished.points) points earned.", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.success)
            } else if let keep = ActionCopy.keep(action, now: model.now) {
                Text(keep).font(.body.weight(.medium)).foregroundStyle(Theme.text)
            }
            Text(action.reason)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            Text(action.createdAt.clock)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textMuted)

            if action.kind != .note && finished == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.sm) { buttons }
                    VStack(spacing: Theme.sm) { buttons }
                }
                .padding(.top, Theme.xs)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ActionCopy.spoken(action))
        .accessibilityActions {
            // Named actions, not the default double-tap: opening the card
            // shouldn't cancel what the agent did.
            if action.kind != .note && finished == nil {
                Button("Undo") { model.undo(action) }
            }
            if item != nil && finished == nil {
                Button("Pick another time") { picking = true }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Undo") { model.undo(action) }
            .buttonStyle(GhostButtonStyle())
        if let item {
            PickAnotherTimeButton(item: item, isPresented: $picking)
        }
    }
}
