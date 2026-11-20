import SwiftUI

/// Words for an agent action: the parts of design D9, in the calm tone of
/// design D7.
enum ActionCopy {
    static func headline(_ action: AgentAction) -> String {
        switch action.kind {
        case .bookComeback: "Booked comeback"
        case .move: "Saved your workout"
        case .shrink: "Made it fit"
        case .addRoutine: "Added routine"
        case .note: action.title ?? "Noted"
        case .purchase: action.title ?? "Bought \(action.purchase?.item ?? "something")"
        case .cancelPurchase: action.title ?? "Cancelled"
        case .purchaseOutcome: action.title ?? "Done"
        case .addWorkout: action.title ?? "Added a workout"
        }
    }

    static func symbol(_ action: AgentAction) -> String {
        switch action.kind {
        case .bookComeback: "arrow.uturn.forward.circle"
        case .move: "calendar.badge.clock"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .addRoutine: "repeat"
        case .note: "text.bubble"
        case .purchase: "bag"
        case .cancelPurchase: "arrow.uturn.backward.circle"
        case .purchaseOutcome: "checkmark.seal"
        case .addWorkout: "figure.run"
        }
    }

    /// "Something landed on tomorrow's 7:30 AM elliptical session." when the
    /// agent defends a slot (the person's own moves need no lead).
    static func lead(_ action: AgentAction, now: Date) -> String? {
        guard let before = action.before else { return nil }
        switch action.kind {
        case .move where action.id.hasPrefix("defend-"), .shrink where action.id.hasPrefix("defend-"):
            return "Something landed on \(when(before.start, now: now))'s \(before.start.clock) \(Activity.noun(before.activityType))."
        default:
            return nil
        }
    }

    /// "12:00 PM, 30 min → 6:30 PM, 15 min", old value struck through.
    static func beforeAfter(_ action: AgentAction) -> Text? {
        switch (action.before, action.after) {
        case let (before?, after?):
            Text("\(Text(before.summary).strikethrough().foregroundStyle(Theme.textMuted)) → \(Text(after.summary).fontWeight(.semibold))")
        case let (nil, after?) where action.kind == .addWorkout:
            // Break-in runs land on later days, so say which one.
            Text("\(after.start.formatted(.dateTime.weekday(.wide))) \(after.summary)").fontWeight(.semibold)
        case let (nil, after?):
            Text(after.summary).fontWeight(.semibold)
        default:
            nil
        }
    }

    static func when(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 17 ? "tonight" : "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "$138", or "$15" without cents.
    static func money(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }

    /// VoiceOver reads each action as one sentence (design D12).
    static func spoken(_ action: AgentAction) -> String {
        var parts = [headline(action)]
        if let after = action.after {
            parts.append("\(after.start.clock), \(after.minutes) minutes")
        }
        if let purchase = action.purchase, action.kind == .purchase {
            parts.append("\(purchase.item), \(money(purchase.amountCents)), \(purchase.merchant)")
        }
        return parts.joined(separator: ", ") + ". " + action.reason
    }
}

// MARK: Moves

extension ActionCopy {
    /// "Thu 12:15 PM → Fri 12:15 PM", old time struck through; a shrink adds
    /// the new length.
    static func moveChange(_ action: AgentAction) -> Text? {
        guard let before = action.before, let after = action.after else { return nil }
        let old = dayClock(before.start)
        var new = dayClock(after.start)
        if after.minutes != before.minutes { new += ", \(after.minutes) min" }
        return Text("\(Text(old).strikethrough().foregroundStyle(Theme.textMuted)) → \(Text(new).fontWeight(.semibold))")
    }

    /// "A new meeting overlaps your Thursday workout." when the agent defended
    /// the slot; the agent's own reason otherwise.
    static func moveReason(_ action: AgentAction) -> String {
        guard action.id.hasPrefix("defend-"), let before = action.before else { return action.reason }
        let day = before.start.formatted(.dateTime.weekday(.wide))
        let next = action.after.map { " \($0.start.clock) is your next open time." } ?? ""
        return "A meeting landed on your \(day) workout.\(next)"
    }

    /// "Still three this week. You're on track. · Demo Gym"
    static func moveKeep(_ action: AgentAction, countWord: String) -> String {
        ["Still \(countWord) this week. You’re on track.", action.after?.place].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Thu 12:15 PM"
    static func dayClock(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.abbreviated))) \(date.clock)"
    }
}

// MARK: Purchases

extension ActionCopy {
    /// A gym day pass (rain), as opposed to new shoes.
    static func isDayPass(_ purchase: Purchase) -> Bool {
        purchase.id.hasPrefix("pass-")
    }

    /// "$138 · you approved it" once bought, else "$138".
    static func ruleBadge(_ purchase: Purchase) -> String {
        purchase.status == .bought
            ? "\(money(purchase.amountCents)) · you approved it"
            : money(purchase.amountCents)
    }

    /// Whether the person can still undo a day pass for free.
    static func canCancelFree(_ purchase: Purchase, now: Date) -> Bool {
        guard isDayPass(purchase), purchase.status == .bought, purchase.outcome == nil,
              let cancelBy = purchase.cancelBy else { return false }
        return now < cancelBy
    }

    static func whyLabel(_ purchase: Purchase) -> String {
        isDayPass(purchase) ? "Why" : "Why this pair"
    }

    /// "~~Outside~~ → **Demo Gym**, Fri 6:00 PM", or back outside once cancelled.
    static func passChange(_ slot: Slot, cancelled: Bool) -> Text {
        let gym = StandInAgent.gym
        let (from, to) = cancelled ? (gym, "Outside") : ("Outside", slot.place ?? gym)
        return Text("\(Text(from).strikethrough().foregroundStyle(Theme.textMuted)) → \(Text(to).fontWeight(.semibold)), \(dayClock(slot.start))")
    }

    /// "$15 · under your $20 rule · cancel free until 5:00 PM"
    static func passTerms(_ purchase: Purchase, now: Date) -> String {
        var parts = [ruleBadge(purchase)]
        if let cancelBy = purchase.cancelBy {
            parts.append(now < cancelBy ? "cancel free until \(cancelBy.clock)" : "free cancel ended \(cancelBy.clock)")
        }
        return parts.joined(separator: " · ")
    }

    /// "**392 miles** on your current pair. That's a lot of running!"
    static func shoesMilesText(_ purchase: Purchase) -> Text {
        guard let miles = purchase.miles else { return Text("Your current pair has worked hard.") }
        return Text("\(Text("\(miles) miles").fontWeight(.semibold)) on your current pair. That’s a lot of running!")
    }

    /// The same line for VoiceOver.
    static func shoesMilesLine(_ purchase: Purchase) -> String {
        purchase.miles.map { "\($0) miles on your current pair. That’s a lot of running!" } ?? "Your current pair has worked hard."
    }

    /// "Monday", when the chosen option arrives.
    static func arrivalDay(_ purchase: Purchase) -> String? {
        purchase.options.first?.arrives?.formatted(.dateTime.weekday(.wide))
    }

    /// What the purchase changes: the moved workout for a day pass ("6:30 PM,
    /// 15 min → 6:30 PM, 15 min, Demo Gym"), else "Current pair → Pacer 9, arrives Monday".
    static func purchaseChange(_ purchase: Purchase, moved: AgentAction?) -> Text {
        if let moved, let change = beforeAfter(moved) { return change }
        let after = arrivalDay(purchase).map { "\(purchase.item), arrives \($0)" } ?? purchase.item
        return Text("\(Text("Current pair").strikethrough().foregroundStyle(Theme.textMuted)) → \(Text(after).fontWeight(.semibold))")
    }

    /// The line under the change: what the purchase keeps possible.
    static func purchaseKeep(_ purchase: Purchase, breakInRuns: Int, now: Date) -> String? {
        if isDayPass(purchase), purchase.status == .bought {
            if let outcome = purchase.outcome { return outcome }
            guard let cancelBy = purchase.cancelBy else { return nil }
            return now < cancelBy ? "Cancel free until \(cancelBy.clock)." : "Free cancel ended \(cancelBy.clock)."
        }
        return switch purchase.status {
        case .awaitingApproval:
            arrivalDay(purchase).map { "Arrives \($0), in time for 2 break-in runs before race day." }
        case .bought:
            breakInRuns > 0 ? "Ordered. \(breakInRuns) break-in runs are on your plan." : "Ordered."
        case .cancelled:
            purchase.outcome
        }
    }
}

