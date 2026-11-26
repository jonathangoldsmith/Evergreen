import SwiftUI

/// A run from a training calendar (Runna, a coach): read-only here, since the
/// calendar belongs to that plan. A swap shows as Evergreen's own row instead.
struct TrainingRunRow: View {
    let run: PlannedRun

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the time drops under the day (design G6).
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.md))
        let dayLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.xs))
            : AnyLayout(HStackLayout(spacing: Theme.sm))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                dayLayout {
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
            if !stacked { Spacer(minLength: Theme.sm) }
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
