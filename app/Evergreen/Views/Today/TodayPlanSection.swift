import SwiftUI

/// Every planned workout this week, divided by hairlines.
struct TodayPlanSection: View {
    @Environment(AppModel.self) private var model

    /// A row is Evergreen's own workout or a run on a training calendar.
    enum Row: Identifiable {
        case plan(PlanItem)
        case training(PlannedRun)

        var id: String {
            switch self {
            case .plan(let item): item.id
            case .training(let run): run.key
            }
        }

        var start: Date {
            switch self {
            case .plan(let item): item.slot.start
            case .training(let run): run.start
            }
        }
    }

    /// The plan and the training runs, by time. A swapped run shows once, as
    /// its swap; the training calendar's own event stays as it was.
    private var rows: [Row] {
        let swapped = Set(model.swapItems.map(\.id))
        let runs = model.trainingRuns.filter { !swapped.contains($0.swapItemId) }
        return (model.plan.map(Row.plan) + runs.map(Row.training)).sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.calendarAccess == .on ? "On your calendar · tap one to move it" : "This week · tap one to move it")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Theme.sm)
            if model.plan.isEmpty && model.trainingRuns.isEmpty {
                Text("Nothing planned this week.")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, Theme.md)
            }
            ForEach(rows) { row in
                switch row {
                case .plan(let item): PlanRow(item: item)
                case .training(let run): TrainingRunRow(run: run)
                }
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            if model.plannerAvailable {
                PlannerLink()
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
        }
    }
}
