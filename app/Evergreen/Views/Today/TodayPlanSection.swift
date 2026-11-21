import SwiftUI

/// Every planned workout this week, divided by hairlines.
struct TodayPlanSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.calendarAccess == .on ? "On your calendar · tap one to move it" : "This week · tap one to move it")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Theme.sm)
            if model.plan.isEmpty {
                Text("Nothing planned this week.")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, Theme.md)
            }
            ForEach(model.plan) { item in
                PlanRow(item: item)
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            if model.plannerAvailable {
                PlannerLink()
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
        }
    }
}
