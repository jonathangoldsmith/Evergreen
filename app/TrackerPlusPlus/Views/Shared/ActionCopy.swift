import SwiftUI

/// Words for an agent action: the five parts of design D9, in the calm tone of
/// design D7 (no minus numbers, "No problem" at a miss).
enum ActionCopy {
    static func headline(_ action: AgentAction) -> String {
        switch action.kind {
        case .bookComeback: "Booked comeback"
        case .move: "Moved"
        case .shrink: "Shrunk"
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

    /// "Your 12:00 PM walk didn't happen. No problem." for a comeback, and
    /// "Something landed on tomorrow's 7:30 AM elliptical session." when the
    /// agent defends a slot (the person's own moves need no lead).
    static func lead(_ action: AgentAction, now: Date) -> String? {
        guard let before = action.before else { return nil }
        switch action.kind {
        case .bookComeback:
            return "Your \(before.start.clock) \(Activity.noun(before.activityType)) didn't happen. No problem."
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

    /// Loss-framed points line: "Keep your 40 points: 15 minutes tonight."
    static func keep(_ action: AgentAction, now: Date) -> String? {
        guard action.kind == .bookComeback, let after = action.after, let points = action.points else { return nil }
        return "Keep your \(points) points: \(after.minutes) minutes \(when(after.start, now: now))."
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
        if action.kind == .bookComeback { parts.append("double points") }
        if let purchase = action.purchase, action.kind == .purchase {
            parts.append("\(purchase.item), \(money(purchase.amountCents)), \(purchase.merchant)")
        }
        return parts.joined(separator: ", ") + ". " + action.reason
    }
}

// MARK: Purchases

extension ActionCopy {
    /// Day passes are bought under the person's rule; everything else asks first.
    static func boughtWithoutAsking(_ purchase: Purchase) -> Bool {
        purchase.rule.id == "day-pass"
    }

    /// "$138 · asks first" or "$15 · under your $20 rule".
    static func ruleBadge(_ purchase: Purchase) -> String {
        boughtWithoutAsking(purchase)
            ? "\(money(purchase.amountCents)) · under your $20 rule"
            : "\(money(purchase.amountCents)) · asks first"
    }

    /// Whether the person can still undo a pass the agent bought without asking.
    static func canCancelFree(_ purchase: Purchase, now: Date) -> Bool {
        guard boughtWithoutAsking(purchase), purchase.status == .bought, purchase.outcome == nil,
              let cancelBy = purchase.cancelBy else { return false }
        return now < cancelBy
    }

    static func whyLabel(_ purchase: Purchase) -> String {
        boughtWithoutAsking(purchase) ? "Why" : "Why this pair"
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
        if boughtWithoutAsking(purchase), purchase.status == .bought {
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

