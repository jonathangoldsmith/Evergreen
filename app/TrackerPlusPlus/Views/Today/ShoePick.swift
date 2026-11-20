import SwiftUI

/// The pair Evergreen recommends: a picture, the name and price, and why it won.
struct ShoePick: View {
    let purchase: Purchase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            HStack(spacing: Theme.md) {
                Image(systemName: "shoe.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 72, height: 72)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusButton, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("My pick")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                    Text(purchase.item)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(priceLine)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
            }
            VStack(alignment: .leading, spacing: Theme.sm) {
                ForEach(reasons, id: \.self) { reason in
                    Label {
                        Text(reason).font(.subheadline).foregroundStyle(Theme.text)
                    } icon: {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "$138 · arrives Monday"
    private var priceLine: String {
        [ActionCopy.money(purchase.amountCents), ActionCopy.arrivalDay(purchase).map { "arrives \($0)" }]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// Why this pair beat the others, from what the agent weighed.
    private var reasons: [String] {
        var lines = ["Wide toe box, like your fit notes ask for"]
        if let day = ActionCopy.arrivalDay(purchase) {
            lines.append("Arrives \(day), in time for 2 break-in runs before race day")
        }
        if purchase.options.dropFirst().contains(where: { $0.lostBecause?.hasPrefix("Costs more") == true }) {
            lines.append("The best price of the pairs that fit")
        }
        return lines
    }
}
