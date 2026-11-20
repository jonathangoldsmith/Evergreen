import Foundation

/// Every notification's words, in one place so the copy owner (plan item 16:
/// Surya) can change them. Same tone as the app (design D7): calm, no guilt,
/// points only as what a workout keeps or earns.
enum NotificationCopy {
    /// 30 minutes before a planned workout (plan item 16).
    static func reminder(_ item: PlanItem) -> (title: String, body: String) {
        let what = item.source == .comeback
            ? "Comeback \(Activity.noun(item.slot.activityType))"
            : Activity.title(item.slot.activityType)
        let body = item.source == .comeback
            ? "\(item.slot.minutes) minutes keeps your \(item.points) points."
            : "\(item.slot.minutes) minutes. People who plan when they'll work out are more likely to do it, and you did."
        return ("\(what) at \(item.slot.start.clock)", body)
    }

    /// Arriving at the gym (location entry).
    static func gymArrival(next: PlanItem?) -> (title: String, body: String) {
        guard let next else { return ("You're at the gym", "Anything you do here counts toward this week.") }
        return ("You're at the gym",
                "Your \(next.slot.minutes)-minute \(Activity.noun(next.slot.activityType)) is next. It counts toward this week.")
    }

    /// Leaving the gym (location exit).
    static let gymExit = (title: "Heading out", body: "If you worked out, I'll count it once it's in Health.")

    /// What the agent did, sent as a notification: the same verb, before → after
    /// and reason as the card.
    static func action(_ action: AgentAction, now: Date) -> (title: String, body: String) {
        var parts: [String] = []
        if let lead = ActionCopy.lead(action, now: now) { parts.append(lead) }
        if let before = action.before, let after = action.after {
            parts.append("\(before.summary) → \(after.summary).")
        } else if let after = action.after {
            parts.append("\(after.summary).")
        }
        parts.append(action.reason)
        return (ActionCopy.headline(action), parts.joined(separator: " "))
    }

    /// The Live Activity's line under the title.
    static func activityNote(_ item: PlanItem, movedByAgent: Bool) -> String {
        if movedByAgent { return "Moved for something on your calendar." }
        if item.source == .comeback { return "\(item.slot.minutes) minutes keeps your \(item.points) points." }
        return "\(item.slot.minutes) minutes · counts toward this week"
    }

    static func activityDone(points: Int) -> String {
        "Done: \(points) points earned."
    }
}
