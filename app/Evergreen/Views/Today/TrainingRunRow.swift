import SwiftUI

/// A run from a training calendar (Runna, a coach): read-only here, since the
/// calendar belongs to that plan. A swap shows as Evergreen's own row instead.
struct TrainingRunRow: View {
    let run: PlannedRun

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: Theme.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.sm) {
                    Text(run.start.formatted(.dateTime.weekday(.wide)))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.text)
                    if model.decision(for: run)?.choice == .keep {
                        Badge(text: "Kept")
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: Theme.sm)
            Text(run.isAllDay && run.size == nil ? "All day" : run.start.clock)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// "Long run 18 km · Runna", or, during a return plan,
    /// "Paused for your return plan (Runna says Long run 18 km)" (item 21).
    private var detail: String {
        if model.isPausedForReturn(run) { return "Paused for your return plan (\(run.calendarTitle) says \(run.title))" }
        return [run.title, run.calendarTitle].joined(separator: " · ")
    }
}
