import SwiftUI

/// Home (design D4): the agent's latest action as the one card, the week's
/// workouts, and how many are done.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(dateLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, Theme.xs)
                if model.offline {
                    Label("Offline, showing last update", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                if let action = model.latestAction, let purchaseId = action.purchaseId {
                    PurchaseCard(purchaseId: purchaseId)
                } else if let action = model.latestAction {
                    AgentCard(action: action)
                } else {
                    QuietState()
                }
                TodayPlanSection()
                if model.calendarAccess != .on {
                    CalendarOffNotice()
                }
                HStack(spacing: Theme.md) {
                    Group {
                        if doneCount >= model.plan.count && doneCount > 0 {
                            PineBuddy(pose: .cheering, filled: weekTiers)
                        } else {
                            WalkingBuddy(filled: weekTiers)
                        }
                    }
                    .frame(height: 72)
                    Text(weekLine)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                .frame(minHeight: 44)
                .padding(.top, Theme.sm)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.lg)
            // Room for the floating demo button, so it never covers a row.
            .padding(.bottom, 88)
        }
        .background(Theme.surface)
    }

    /// "Friday, Nov 20", plus the time when the demo clock is set ("· 4:00 PM"),
    /// since the status bar keeps showing the real time.
    private var dateLine: String {
        let day = model.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return model.clockMinutes == nil ? day : "\(day) · \(model.now.clock)"
    }

    /// "This week: 1 of 3 done. Keep it up!", counting the planned workouts
    /// above so it agrees with the card's "three workouts".
    private var doneCount: Int {
        model.plan.filter { model.completion(for: $0) != nil }.count
    }

    /// The buddy's tiers filled so far, scaled to its three tiers.
    private var weekTiers: Int {
        let total = max(model.plan.count, 1)
        return min(3, (doneCount * 3 + total - 1) / total)
    }

    /// The pine grows a tier for each workout done this week.
    private var weekLine: String {
        let done = doneCount
        let total = model.plan.count
        let cheer = done == 0 ? "Let’s grow." : done < total ? "Growing nicely!" : "Fully grown. You did it!"
        return "This week: \(done) of \(total) done. \(cheer)"
    }
}
