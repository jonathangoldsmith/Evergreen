import SwiftUI

/// The last onboarding step (design D15): the person's normal and this month's goal.
struct YourNormalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            Text("Your normal")
                .font(.headline)
                .foregroundStyle(Theme.textMuted)
            if let normal = model.normal {
                if normal.gettingToKnowYou {
                    Text("I'm still getting to know you.")
                        .agentFont(28, relativeTo: .title)
                        .foregroundStyle(Theme.text)
                    Text("I'll start from 2 workouts a week and adjust as I learn.")
                        .font(.body)
                        .foregroundStyle(Theme.textMuted)
                } else {
                    Text("You usually work out \(frequency(normal.perWeek)).")
                        .agentFont(28, relativeTo: .title)
                        .foregroundStyle(Theme.text)
                    Text(goalLine(normal))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                }
            } else {
                Text("Looking at your last 4 weeks…")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func frequency(_ perWeek: Double) -> String {
        let rounded = Int(perWeek.rounded())
        return rounded <= 1 ? "about once a week" : "about \(rounded) times a week"
    }

    private func goalLine(_ normal: Normal) -> String {
        let extra = normal.goal4Weeks - normal.usual4Weeks
        return extra > 0
            ? "Goal: \(normal.goal4Weeks) this month, \(extra) more than usual."
            : "Goal: keep your \(normal.goal4Weeks) this month."
    }
}
