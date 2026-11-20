import SwiftUI

/// The "Order it" screen for new running shoes: what you're getting, when it
/// arrives, how you pay, and the break-in runs Evergreen will add. Nothing is
/// ordered until Place order; then it confirms with the buddy cheering.
struct ShoeCheckout: View {
    let purchaseId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ordered = false

    private var purchase: Purchase? {
        model.purchaseState(purchaseId)
            ?? model.purchaseTrail(purchaseId).first { $0.purchase != nil }?.purchase
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let purchase {
                    if ordered {
                        confirmation(purchase)
                    } else {
                        review(purchase)
                    }
                }
            }
            .background(Theme.surface)
            .navigationTitle(ordered ? "" : "Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: ordered ? .confirmationAction : .cancellationAction) {
                    Button(ordered ? "Done" : "Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let purchase, !ordered {
                    VStack(spacing: Theme.xs) {
                        Button("Place order · \(ActionCopy.money(purchase.amountCents))", action: placeOrder)
                            .buttonStyle(PrimaryButtonStyle())
                        Text("Demo store. Nothing is charged.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(Theme.md)
                    .background(Theme.surface)
                }
            }
        }
    }

    // MARK: Review

    private func review(_ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            ShoePick(purchase: purchase)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))

            section("Your order") {
                detailRow("Size", "US 10 · Wide", symbol: "ruler")
                detailRow("Arrives", arrival(purchase), symbol: "shippingbox")
                detailRow("Ship to", "Home", symbol: "house")
                detailRow("Pay with", "Apple Pay", symbol: "creditcard")
                detailRow("Returns", "Free for 30 days", symbol: "arrow.uturn.backward")
            }

            section("After it arrives") {
                ForEach(Array(breakInRuns.enumerated()), id: \.offset) { index, slot in
                    detailRow("Break-in run \(index + 1)",
                              "\(ActionCopy.dayClock(slot.start)) · \(slot.minutes) min easy",
                              symbol: "figure.run")
                }
                Text("I’ll add these to your calendar so the new pair is race-ready.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, Theme.xs)
            }

            section("Total") {
                HStack {
                    Text(purchase.item)
                    Spacer()
                    Text(ActionCopy.money(purchase.amountCents)).monospacedDigit()
                }
                HStack {
                    Text("Shipping")
                    Spacer()
                    Text("Free")
                }
                .foregroundStyle(Theme.textMuted)
            }
            .font(.body)
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.lg)
    }

    // MARK: Confirmation

    private func confirmation(_ purchase: Purchase) -> some View {
        VStack(spacing: Theme.md) {
            PineBuddy(pose: .cheering)
                .frame(height: 180)
                .padding(.top, Theme.xl)
            Text("Ordered! Fresh legs, here we come.")
                .agentFont(28, relativeTo: .title)
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
            Text("Your \(purchase.item) arrives \(arrival(purchase)).")
                .font(.body)
                .foregroundStyle(Theme.text)
            Text("I added \(breakInRuns.count) easy break-in runs to your calendar before race day.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func detailRow(_ label: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(label).foregroundStyle(Theme.text)
            Spacer()
            Text(value).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
        }
        .font(.body)
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    /// "Monday, Nov 23"
    private func arrival(_ purchase: Purchase) -> String {
        purchase.options.first?.arrives?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? "soon"
    }

    private var breakInRuns: [Slot] {
        guard let arrives = purchase?.options.first?.arrives, let race = model.raceDate else { return [] }
        return StandInAgent.breakInRuns(arrives: arrives, race: race, cal: Calendar.current)
    }

    private func placeOrder() {
        model.approvePurchase(purchaseId)
        withAnimation(.easeOut(duration: 0.3)) { ordered = true }
    }
}
