import SwiftUI

/// Today's planned workouts, divided by hairlines.
struct TodayPlanSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .padding(.bottom, Theme.sm)
            if model.todayPlan.isEmpty {
                Text("Nothing planned today.")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, Theme.md)
            }
            ForEach(model.todayPlan) { item in
                Rectangle().fill(Theme.rule).frame(height: 1)
                PlanRow(item: item)
            }
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }
}
