import SwiftUI

struct FeedRow: View {
    let action: AgentAction

    @Environment(AppModel.self) private var model

    @State private var showWhy = false

    private var undone: Bool { model.isUndone(action) }

    /// Purchase rows use their own controls (Not now, Cancel order) on the
    /// card; only a break-in run keeps the generic Undo (eng review, R3-1).
    private var canUndo: Bool {
        if let purchaseId = action.purchaseId, action.id == "purchase-\(purchaseId)",
           let purchase = model.purchaseState(purchaseId) {
            // A day pass bought without asking: Undo until free cancel ends.
            return ActionCopy.canCancelFree(purchase, now: model.now)
        }
        return action.kind != .note && (action.purchaseId == nil || action.kind == .addWorkout)
    }

    /// "Not now" for a declined ask, "Cancelled" for an undone order.
    private var undoneLabel: String {
        guard action.purchaseId != nil else { return "Undone" }
        return action.purchase?.status == .awaitingApproval ? "Not now" : "Cancelled"
    }

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
            if let purchase = action.purchase, action.kind != .addWorkout {
                Text("\(ActionCopy.ruleBadge(purchase)) · \(purchase.merchant)")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: Theme.lg) {
                if undone {
                    Text(undoneLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textMuted)
                } else if canUndo {
                    Button("Undo") { model.undo(action) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                }
                if let purchase = action.purchase {
                    Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $showWhy) {
            if let purchaseId = action.purchaseId { WhyView(purchaseId: purchaseId) }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ActionCopy.spoken(action) + (undone ? " \(undoneLabel)." : ""))
        .accessibilityActions {
            if !undone && canUndo {
                Button("Undo") { model.undo(action) }
            }
            if let purchase = action.purchase {
                Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
            }
        }
    }
}
