import SwiftUI

/// Trends as sentences (TODOS item 5): the last 7 days and the last 4 weeks,
/// one plain sentence per row. No chart, ring or score (DESIGN.md: progress
/// is a sentence).
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trends = model.trends
        NavigationStack {
            Form {
                if trends.isEmpty {
                    Section {
                        Text("Not enough history yet. Trends start once Apple Health has a week of workouts.")
                            .foregroundStyle(Theme.textMuted)
                    }
                    .listRowBackground(Theme.card)
                }
                section("Last 7 days", trends.week)
                section("Last 4 weeks", trends.month)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .tint(Theme.accent)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            Section(title) {
                ForEach(lines, id: \.self) { line in
                    Text(line).foregroundStyle(Theme.text)
                }
            }
            .listRowBackground(Theme.card)
        }
    }
}
