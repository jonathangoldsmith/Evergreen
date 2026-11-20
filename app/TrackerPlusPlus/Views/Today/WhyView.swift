import SwiftUI

/// The audit trail behind one purchase, top to bottom in the order the agent
/// worked: rule → what it noticed → what it checked (cited, live or cached) →
/// options and why each lost → what it did → outcome. A sheet, like Feed.
struct WhyView: View {
    let purchaseId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showCheckout = false
    /// The harness can send 15–25 options; the first few tell the story.
    @State private var showAllOptions = false

    static let optionsShown = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                if let purchase = model.purchaseState(purchaseId) ?? firstPurchase {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(purchase.item) · \(ActionCopy.money(purchase.amountCents))")
                            .agentFont(22, relativeTo: .title2)
                            .foregroundStyle(Theme.accent)
                            .padding(.bottom, Theme.lg)
                        trail(purchase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.lg)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if purchase?.status == .awaitingApproval, let purchase, !ActionCopy.isDayPass(purchase) {
                    Button("Order it") { showCheckout = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Theme.md)
                    .background(Theme.surface)
                }
            }
            .sheet(isPresented: $showCheckout, onDismiss: closeIfOrdered) { ShoeCheckout(purchaseId: purchaseId) }
            .background(Theme.surface)
            .navigationTitle((purchase ?? firstPurchase).map(ActionCopy.whyLabel) ?? "Why")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var purchase: Purchase? { model.purchaseState(purchaseId) }

    /// Back on Today once the order is placed.
    private func closeIfOrdered() {
        if purchase?.status == .bought { dismiss() }
    }

    /// The ask itself, so a declined purchase ("Not now") keeps its trail.
    private var firstPurchase: Purchase? {
        model.purchaseTrail(purchaseId).first { $0.purchase != nil }?.purchase
    }

    @ViewBuilder
    private func trail(_ purchase: Purchase) -> some View {
        step("Your rule") {
            Text(purchase.rule.text)
            Text("Set in onboarding").font(.footnote).foregroundStyle(Theme.textMuted)
        }
        step("What I noticed") {
            Text(purchase.noticed)
        }
        step("What I checked", marker: purchase.evidenceLive ? "Senso · live" : "Senso · cached") {
            ForEach(purchase.evidence, id: \.self) { evidence in
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(evidence.passage)”")
                    Text(evidence.source).font(.footnote).foregroundStyle(Theme.textMuted)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.rule, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        step("Options") {
            let hidden = showAllOptions ? 0 : max(0, purchase.options.count - Self.optionsShown)
            ForEach(Array(purchase.options.dropLast(hidden).enumerated()), id: \.offset) { index, option in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(option.name) · \(ActionCopy.money(option.amountCents))")
                            .fontWeight(index == 0 ? .semibold : .regular)
                        Spacer()
                        if index == 0 {
                            Label("Chosen", systemImage: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if let lost = option.lostBecause {
                        Text(lost).font(.footnote).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if hidden > 0 {
                Button("Show \(hidden) more") { showAllOptions = true }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        step(purchase.status == .awaitingApproval ? "What I'll do" : "What I did") {
            Text(didText(purchase))
            ForEach(breakInRuns, id: \.id) { run in
                if let slot = run.after {
                    Text("Break-in run: \(slot.start.formatted(.dateTime.weekday(.abbreviated))) \(slot.start.clock), \(slot.minutes) min")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        step("Outcome", last: true) {
            Text(outcomeText(purchase))
                .foregroundStyle(purchase.status == .awaitingApproval ? Theme.textMuted : Theme.text)
        }
    }

    private var breakInRuns: [AgentAction] {
        model.purchaseTrail(purchaseId).filter { $0.kind == .addWorkout && !model.isUndone($0) }
    }

    private func didText(_ purchase: Purchase) -> String {
        switch purchase.status {
        case .awaitingApproval:
            ActionCopy.isDayPass(purchase)
                ? "Buy a \(purchase.item) (demo, no charge) once you say yes, and move your workout there."
                : "Order it from the demo store (no charge), then add 2 break-in runs before race day."
        case .bought:
            ActionCopy.isDayPass(purchase)
                ? "Bought a \(purchase.item) (demo, no charge) after you said yes, and moved your workout there."
                : "Ordered from the demo store, no charge."
        case .cancelled:
            ActionCopy.isDayPass(purchase)
                ? "Cancelled the pass and moved your workout back."
                : "Cancelled the order."
        }
    }

    private func outcomeText(_ purchase: Purchase) -> String {
        if let outcome = purchase.outcome { return outcome }
        let declined = model.purchaseTrail(purchaseId).first.map(model.isUndone) ?? false
        switch purchase.status {
        case .awaitingApproval: return declined ? "You said not now." : "Waiting for you."
        case .bought:
            if ActionCopy.isDayPass(purchase) {
                return ActionCopy.purchaseKeep(purchase, breakInRuns: 0, now: model.now) ?? "Bought."
            }
            return ActionCopy.arrivalDay(purchase).map { "Arrives \($0)." } ?? "Ordered."
        case .cancelled: return "Cancelled."
        }
    }

    /// One step of the trail: a dot on a rule line, a small label, then content.
    private func step<Content: View>(
        _ label: String, marker: String? = nil, last: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.md) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Theme.textMuted, lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                if !last {
                    Rectangle().fill(Theme.rule).frame(width: 2)
                }
            }
            .frame(width: 10)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack {
                    Text(label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let marker {
                        Text(marker)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, Theme.xs + 2)
                            .padding(.vertical, 1)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.rule, lineWidth: 1)
                            }
                    }
                }
                content()
                    .font(.body)
                    .foregroundStyle(Theme.text)
            }
            .padding(.bottom, Theme.lg)
        }
    }
}
