import SwiftUI

/// The agent card for a purchase (shopping beat), folded across the purchase's
/// trail. Every purchase asks first: See options or Buy it, and Not now.
struct PurchaseCard: View {
    let purchaseId: String

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWhy = false
    @State private var showCheckout = false

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
                .sheet(isPresented: $showCheckout) { ShoeCheckout(purchaseId: purchaseId) }
        }
    }

    private func content(_ latest: AgentAction, _ purchase: Purchase) -> some View {
        Group {
            if isShoesAsk(purchase) {
                shoesAsk(purchase)
            } else if isPassAsk(purchase) {
                passAsk(latest, purchase)
            } else if isActivePass(purchase) {
                dayPass(latest, purchase)
            } else {
                standard(latest, purchase)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isShoesAsk(purchase)
            ? "Time for new running shoes? \(ActionCopy.shoesMilesLine(purchase)) Nothing is bought without your OK."
            : ActionCopy.headline(latest) + " " + purchase.noticed)
        .accessibilityActions {
            if isShoesAsk(purchase) {
                Button("Order it for \(ActionCopy.money(purchase.amountCents))") { showCheckout = true }
                Button("Compare pairs") { showWhy = true }
                Button("Not now") { undoPurchase() }
            } else if isPassAsk(purchase) {
                Button("Book it for \(ActionCopy.money(purchase.amountCents))") { model.approvePurchase(purchaseId) }
                Button("Not now") { undoPurchase() }
            } else if isActivePass(purchase) {
                Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                if ActionCopy.canCancelFree(purchase, now: model.now) {
                    Button("Undo") { cancelOrder() }
                }
            } else {
                if purchase.status == .awaitingApproval {
                    Button("Order it") { model.approvePurchase(purchaseId) }
                    Button("Not now") { undoPurchase() }
                }
                Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                if purchase.status == .bought {
                    Button("Cancel order") { cancelOrder() }
                }
            }
        }
    }

    /// The day pass offer: Evergreen always checks before buying.
    private func isPassAsk(_ purchase: Purchase) -> Bool {
        ActionCopy.isDayPass(purchase) && purchase.status == .awaitingApproval
    }

    private func passAsk(_ latest: AgentAction, _ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(ActionCopy.headline(latest))
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            Text(purchase.noticed).font(.body).foregroundStyle(Theme.text)
            Text(ActionCopy.passTerms(purchase, now: model.now) + " · Nothing is bought without your OK.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { passAskButtons(purchase) }
                VStack(spacing: Theme.sm) { passAskButtons(purchase) }
            }
            .padding(.top, Theme.sm)
        }
    }

    @ViewBuilder
    private func passAskButtons(_ purchase: Purchase) -> some View {
        Button("Book it · \(ActionCopy.money(purchase.amountCents))") { model.approvePurchase(purchaseId) }
            .buttonStyle(PrimaryButtonStyle())
        Button("Not now") { undoPurchase() }
            .buttonStyle(GhostButtonStyle())
    }

    /// A day pass once bought, while it's in effect or once it's cancelled:
    /// the same shape as the Moved card, so the change reads at a glance.
    private func isActivePass(_ purchase: Purchase) -> Bool {
        guard ActionCopy.isDayPass(purchase) else { return false }
        return purchase.status == .cancelled || (purchase.status == .bought && purchase.outcome == nil)
    }

    private func dayPass(_ latest: AgentAction, _ purchase: Purchase) -> some View {
        let cancelled = purchase.status == .cancelled
        return VStack(alignment: .leading, spacing: Theme.sm) {
            Text(ActionCopy.headline(latest))
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            if let slot = moved?.after {
                ActionCopy.passChange(slot, cancelled: cancelled).font(.body).foregroundStyle(Theme.text)
            }
            Text(cancelled ? latest.reason : purchase.noticed).font(.body).foregroundStyle(Theme.text)
            if !cancelled {
                Text(ActionCopy.passTerms(purchase, now: model.now))
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: Theme.sm) {
                Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                    .buttonStyle(GhostButtonStyle())
                if ActionCopy.canCancelFree(purchase, now: model.now) {
                    Button("Undo") { cancelOrder() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .padding(.top, Theme.sm)
        }
    }

    /// The shoes ask before anything is bought: why now, and See options.
    private func isShoesAsk(_ purchase: Purchase) -> Bool {
        purchase.status == .awaitingApproval && !ActionCopy.isDayPass(purchase)
    }

    private func shoesAsk(_ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Time for new running shoes?")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            ActionCopy.shoesMilesText(purchase).font(.body).foregroundStyle(Theme.text)
            Text("Most pairs wear out between 300 and 500 miles, and worn shoes raise your injury risk.")
                .font(.body)
                .foregroundStyle(Theme.text)
            ShoePick(purchase: purchase)
                .padding(.vertical, Theme.xs)
            Text("Nothing is bought without your OK.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            VStack(spacing: Theme.sm) {
                Button("Order it · \(ActionCopy.money(purchase.amountCents))") { showCheckout = true }
                    .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: Theme.sm) {
                    Button("Compare pairs") { showWhy = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Not now") { undoPurchase() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .padding(.top, Theme.sm)
        }
    }

    private func standard(_ latest: AgentAction, _ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ActionCopy.headline(latest))
                .agentFont(24, relativeTo: .title2)
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

            buttons(purchase)
                .padding(.top, Theme.xs)
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
                if !ActionCopy.isDayPass(purchase) {
                    Button("Cancel order") { cancelOrder() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        case .cancelled:
            Button(ActionCopy.whyLabel(purchase)) { showWhy = true }
                .buttonStyle(GhostButtonStyle())
        }
    }

    /// "Not now" undoes the ask, so the agent won't ask again.
    private func undoPurchase() {
        if let ask = trail.first(where: { $0.id == "purchase-\(purchaseId)" }) { model.undo(ask) }
    }

    /// "Cancel order" (and Undo on a day pass, before the free-cancel deadline)
    /// undoes the bought step; the agent answers with the cancel and refund.
    private func cancelOrder() {
        if let bought = trail.first(where: { $0.id == "purchase-\(purchaseId)-bought" }) { model.undo(bought) }
    }
}
