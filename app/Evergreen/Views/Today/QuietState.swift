import SwiftUI

/// Today before the agent has changed anything: the week it planned, as the
/// one card, with what it read to tailor it (Apple Health, training load, the
/// calendar). Each workout row below says why it's there and picks its own time.
struct QuietState: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let data = model.insights
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("\(model.planCountWord.capitalized) workouts, tailored to you.")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                SourceLine(symbol: "heart.fill", detail: healthLine(data))
                SourceLine(symbol: "gauge.with.dots.needle.67percent", detail: loadLine(data))
                SourceLine(symbol: "calendar", detail: model.openTimesShort)
            }
            .padding(.top, Theme.xs)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
        .accessibilityElement(children: .combine)
    }

    /// "Health: 21 runs in 30 days · avg HR 132"
    private func healthLine(_ data: TrainingInsights) -> String {
        var line = "Health: \(data.runs30) runs in 30 days"
        if let rate = data.avgHeartRate { line += " · avg HR \(rate)" }
        return line
    }

    /// "Load: up 19% on your usual week"
    private func loadLine(_ data: TrainingInsights) -> String {
        let percent = Int((data.loadChange * 100).rounded())
        return percent >= 5 ? "Load: up \(percent)% on your usual week"
            : percent <= -5 ? "Load: down \(-percent)% on your usual week" : "Load: right at your usual week"
    }
}

/// One data source on the plan card: icon and what it said, on one line.
private struct SourceLine: View {
    let symbol: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

extension View {
    /// The agent card's surface: white, 20pt continuous radius, a soft shadow in
    /// light mode and a 1px rule in dark mode.
    func agentCardBackground(_ colorScheme: ColorScheme) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(Theme.rule, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, y: 2)
    }
}
