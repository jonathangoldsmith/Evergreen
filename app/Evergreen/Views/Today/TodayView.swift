import SwiftUI

/// Home (design D4): the agent's latest action as the one card, the week's
/// workouts, and how many are done.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showYourData = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(dateLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, Theme.xs)
                if let range = model.todayRange {
                    TodayRangeLine(range: range)
                }
                if let bedtime = model.tonightsBedtime {
                    TodaySentence(line: bedtime.line(calendar: model.calendar), reason: bedtime.reason(calendar: model.calendar))
                }
                if model.offline {
                    Label("Offline, showing last update", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                // Cards stack in the model's urgency order (design decisions 1
                // and 13); a past action is a badged row in the plan below.
                let cards = model.todayCards
                ForEach(cards) { card in
                    switch card {
                    case .run(let run): GuardrailCard(run: run)
                    case .pain(let week): PainCheckInCard(week: week)
                    case .returnPlan: ReturnPlanCard()
                    case .action(let action):
                        if let purchaseId = action.purchaseId {
                            PurchaseCard(purchaseId: purchaseId)
                        } else {
                            AgentCard(action: action)
                        }
                    }
                }
                if cards.isEmpty {
                    QuietState()
                }
                TodayPlanSection()
                if model.calendarAccess != .on {
                    CalendarOffNotice()
                }
                HStack(spacing: Theme.md) {
                    Group {
                        if model.weekDone >= model.weekTotal && model.weekDone > 0 {
                            PineBuddy(pose: .cheering, filled: weekTiers)
                        } else {
                            // Waves hi each time Today opens, then walks.
                            WavingBuddy(filled: weekTiers)
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
                // One quiet, dismissible line for the push side (design decision 4).
                if model.showsBuddyInvite {
                    HStack {
                        Button(BuddyCopy.invitePrompt) { showYourData = true }
                            .font(.footnote)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Button("Dismiss", systemImage: "xmark") { model.dismissBuddyInvite() }
                            .labelStyle(.iconOnly)
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                // For everyone: the brake's settings (calendars, injury, uploads) live here.
                Button("Your data") { showYourData = true }
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .frame(minHeight: 44)
                    .accessibilityHint("Training calendars, what leaves your phone, and what Evergreen keeps")
            }
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.lg)
            // Room for the floating demo button, so it never covers a row.
            .padding(.bottom, 88)
        }
        .background(Theme.surface)
        .sheet(isPresented: $showYourData) { YourDataView() }
        .sheet(item: ostrcBinding) { week in OSTRCSheet(week: week.date) }
        .sheet(item: celebrationBinding) { completion in DoneSheet(completion: completion) }
    }

    /// The Done sheet shows once per finished plan item (range plan item 14).
    private var celebrationBinding: Binding<Completion?> {
        Binding(get: { model.celebration }, set: { model.celebration = $0 })
    }

    /// The OSTRC sheet shows while a week's questions are waiting.
    private var ostrcBinding: Binding<OSTRCWeek?> {
        Binding(get: { model.ostrcWeek.map(OSTRCWeek.init) }, set: { if $0 == nil { model.skipOSTRC() } })
    }

    /// "Friday, Nov 20", plus the time when the demo clock is set ("· 4:00 PM"),
    /// since the status bar keeps showing the real time.
    private var dateLine: String {
        let day = model.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return model.clockMinutes == nil ? day : "\(day) · \(model.now.clock)"
    }

    /// The buddy's tiers filled so far, scaled to its three tiers.
    private var weekTiers: Int {
        let total = max(model.weekTotal, 1)
        return min(3, (model.weekDone * 3 + total - 1) / total)
    }

    /// The pine grows a tier for each workout done this week.
    private var weekLine: String {
        // Sunday 7 PM through Monday, the week's range report (design decision 2).
        if let report = model.rangeReport { return report.sentence }
        // Evergreen's plan and the training calendar's runs, each once (task E19).
        let done = model.weekDone
        let total = model.weekTotal
        let cheer = done == 0 ? "Let’s grow." : done < total ? "Growing nicely!" : "Fully grown. You did it!"
        return "This week: \(done) of \(total) done. \(cheer)"
    }
}
