import SwiftUI

/// The agent card for a purchase (shopping beat): the same five parts as every
/// action, folded across the purchase's trail, with Order it / Why / Not now
/// while it waits for the person, and Cancel order once it's bought.
struct PurchaseCard: View {
    let purchaseId: String

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWhy = false

    private var trail: [AgentAction] { model.purchaseTrail(purchaseId) }

    /// The newest action in the trail still in effect, other than a break-in run.
    private var latest: AgentAction? {
        trail.last { !model.isUndone($0) && $0.kind != .addWorkout }
    }

    /// The newest action in effect that moved the workout (buy or cancel).
    private var moved: AgentAction? {
        trail.last { !model.isUndone($0) && $0.before != nil && $0.after != nil && $0.kind != .addWorkout }
    }

    private var breakInRuns: Int {
        trail.filter { $0.kind == .addWorkout && !model.isUndone($0) }.count
    }

    var body: some View {
        if let latest, let purchase = model.purchaseState(purchaseId) {
            content(latest, purchase)
                .sheet(isPresented: $showWhy) { WhyView(purchaseId: purchaseId) }
        }
    }

    private func content(_ latest: AgentAction, _ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(ActionCopy.headline(latest))
                    .agentFont(22, relativeTo: .title2)
            } icon: {
                Image(systemName: ActionCopy.symbol(latest))
            }
            .foregroundStyle(Theme.accent)

            Text(purchase.noticed).font(.body).foregroundStyle(Theme.text)
            ActionCopy.purchaseChange(purchase, moved: moved).font(.body).foregroundStyle(Theme.text)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { badges(purchase) }
                VStack(alignment: .leading, spacing: Theme.sm) { badges(purchase) }
            }

            if let keep = ActionCopy.purchaseKeep(purchase, breakInRuns: breakInRuns, now: model.now) {
                Text(keep).font(.body.weight(.medium)).foregroundStyle(Theme.text)
            }
            Text(latest.reason)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            Text(latest.createdAt.clock)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textMuted)

            buttons(purchase)
                .padding(.top, Theme.xs)
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
        .accessibilityLabel(ActionCopy.spoken(latest) + " " + purchase.noticed)
        .accessibilityActions {
            if purchase.status == .awaitingApproval {
                Button("Order it") { model.approvePurchase(purchaseId) }
                Button("Not now") { undoPurchase() }
            }
            Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
            if ActionCopy.canCancelFree(purchase, now: model.now) {
                Button("Undo") { undoPurchase() }
            }
            if purchase.status == .bought, !ActionCopy.boughtWithoutAsking(purchase) {
                Button("Cancel order") { cancelOrder() }
            }
        }
    }

    @ViewBuilder
    private func badges(_ purchase: Purchase) -> some View {
        Badge(text: ActionCopy.ruleBadge(purchase))
        Badge(text: purchase.merchant)
    }

    @ViewBuilder
    private func buttons(_ purchase: Purchase) -> some View {
        switch purchase.status {
        case .awaitingApproval:
            VStack(spacing: Theme.sm) {
                Button("Order it") { model.approvePurchase(purchaseId) }
                    .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: Theme.sm) {
                    Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Not now") { undoPurchase() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        case .bought:
            HStack(spacing: Theme.sm) {
                Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                    .buttonStyle(GhostButtonStyle())
                if !ActionCopy.boughtWithoutAsking(purchase) {
                    Button("Cancel order") { cancelOrder() }
                        .buttonStyle(GhostButtonStyle())
                } else if ActionCopy.canCancelFree(purchase, now: model.now) {
                    Button("Undo") { undoPurchase() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        case .cancelled:
            Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                .buttonStyle(GhostButtonStyle())
        }
    }

    /// "Not now" undoes the ask, so the agent won't ask again; on a day pass,
    /// Undo before the free-cancel deadline makes the agent cancel and refund.
    private func undoPurchase() {
        if let ask = trail.first(where: { $0.id == "purchase-\(purchaseId)" }) { model.undo(ask) }
    }

    /// "Cancel order" undoes the bought step; the agent answers with the cancel.
    private func cancelOrder() {
        if let bought = trail.first(where: { $0.id == "purchase-\(purchaseId)-bought" }) { model.undo(bought) }
    }
}
