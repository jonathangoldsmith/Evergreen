import SwiftUI

/// Shown when a workout finishes a plan item (range plan item 14): the points,
/// counted up, the 2× badge for a comeback, the week, and the pine buddy
/// celebrating with a tier filled. No confetti (DESIGN.md).
struct DoneSheet: View {
    let completion: Completion

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        // Centered when it fits; scrolls when large text makes it taller than the sheet.
        ViewThatFits(in: .vertical) {
            DoneSummary(completion: completion, shown: shown)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                DoneSummary(completion: completion, shown: shown)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.lg)
            }
        }
        .padding(.horizontal, Theme.lg)
        .safeAreaInset(edge: .bottom) {
            Button("Nice") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(Theme.lg)
        }
        .background(Theme.surface)
        .task { await countUp() }
    }

    /// 600 ms ease-out count-up; none under Reduce Motion (DESIGN.md Motion).
    private func countUp() async {
        let target = completion.points
        guard !reduceMotion else {
            shown = target
            return
        }
        let steps = 30
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(20))
            let t = Double(step) / Double(steps)
            shown = Int((Double(target) * (1 - pow(1 - t, 3))).rounded())
        }
    }
}
