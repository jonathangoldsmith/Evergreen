import SwiftUI

/// The return-to-running plan on Today (range plan item 21, design decisions
/// 7 and 19): the ask-first offer with weekday toggles, the plan in progress,
/// the pause after a "Yes" pain answer, and the end.
struct ReturnPlanCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var weekdays: Set<Int> = []
    @State private var startMinute = ReturnPlan.defaultStartMinute

    static let disclaimer = "Evergreen suggests training changes. It isn't medical advice; see a physio if it hurts to walk."

    var body: some View {
        Group {
            if model.offersReturnPlan {
                offer
            } else if let plan = model.returnPlan {
                switch plan.status {
                case .active: active
                case .paused: paused
                case .ended: ended
                case .finished: finished
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
    }

    // MARK: The offer (design decision 19)

    private var offer: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Want a walk-run plan back to running?")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            Text("4 weeks, on the days you usually run. It starts at 20 minutes of 1 minute running, 2 walking, and grows a little each week.")
                .font(.body)
                .foregroundStyle(Theme.text)
            WeekdayToggles(selected: $weekdays)
                .padding(.vertical, Theme.xs)
            if !ReturnPlan.suggestedDays.contains(weekdays.count) {
                Text("2 to 4 days works best coming back.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            Text(Self.disclaimer)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { offerButtons }
                VStack(spacing: Theme.sm) { offerButtons }
            }
            .padding(.top, Theme.sm)
        }
        .onAppear {
            let suggested = ReturnPlan.suggestedDays(history: model.workouts, today: model.now, calendar: .current)
            weekdays = suggested.weekdays
            startMinute = suggested.startMinute
        }
    }

    @ViewBuilder
    private var offerButtons: some View {
        Button("Start 4 weeks, \(weekdays.count) day\(weekdays.count == 1 ? "" : "s") a week") {
            model.startReturnPlan(weekdays: weekdays, startMinute: startMinute)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(weekdays.isEmpty)
        Button("Not now") { model.dismissReturnOffer() }
            .buttonStyle(GhostButtonStyle())
    }

    // MARK: States (design decision 7)

    /// Without a training calendar there's no "training plan" to name.
    private var hasTrainingPlan: Bool { !model.profile.trainingCalendarIds.isEmpty }

    private var active: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Return plan · Week \((model.returnWeek ?? 0) + 1) of \(ReturnPlan.weeks)")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            if let next = model.returnSessions.first(where: { $0.end > model.now }) {
                Text("Next: \(next.start.formatted(.dateTime.weekday(.wide))) at \(next.start.clock), \(next.title.lowercased().replacingOccurrences(of: "walk-run ", with: "")).")
                    .font(.body)
                    .foregroundStyle(Theme.text)
            }
            Text("\(hasTrainingPlan ? "Your training plan's runs are" : "Your other runs are") paused until it's done. A missed session isn't chased.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            Button("End return plan") { model.endReturnPlan() }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, Theme.sm)
        }
    }

    private var paused: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Your return plan is paused")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("You said it hurts this week. A physio can tell you when to pick it up again. \(hasTrainingPlan ? "Your training plan's runs stay" : "Your other runs stay") paused meanwhile.")
                .font(.body)
                .foregroundStyle(Theme.text)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { pausedButtons }
                VStack(spacing: Theme.sm) { pausedButtons }
            }
            .padding(.top, Theme.sm)
        }
    }

    @ViewBuilder
    private var pausedButtons: some View {
        Button("Resume your return plan") { model.resumeReturnPlan() }
            .buttonStyle(PrimaryButtonStyle())
        Button("End it and go back to your plan") { model.endReturnPlan() }
            .buttonStyle(GhostButtonStyle())
    }

    private var ended: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Return plan ended")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            Text(hasTrainingPlan ? "Your training plan is back, and its first run gets the usual check." : "Your usual runs are back, and the first one gets the usual check.")
                .font(.body)
                .foregroundStyle(Theme.text)
            Button("Undo") { model.undoEndReturnPlan() }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, Theme.sm)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Back to your plan.")
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            Text("Four weeks done. Your next run gets the usual check against your recent running.")
                .font(.body)
                .foregroundStyle(Theme.text)
        }
    }
}
