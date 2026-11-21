import SwiftUI

/// The row under the week's plan that opens the harness planner's next 7 days.
/// Shown only when the harness is set up (its secret is in Settings or
/// app/Secrets.xcconfig).
struct PlannerLink: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(alignment: .top, spacing: Theme.md) {
                Image(systemName: "calendar.badge.clock")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 7 days from the planner")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.text)
                    Text("Built from your load, sleep, shoes and race")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: Theme.sm)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the planner's recommendations")
        .sheet(isPresented: $showing) { WeekPlanView() }
    }
}
