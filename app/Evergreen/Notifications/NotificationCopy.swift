import Foundation

/// Every notification's words, in one place so the copy owner (plan item 16:
/// Surya) can change them. Same voice as the app: an encouraging coach that
/// says why, never guilt, streaks or points.
enum NotificationCopy {
    /// 30 minutes before a planned workout (plan item 16).
    static func reminder(_ item: PlanItem) -> (title: String, body: String) {
        ("\(Activity.title(item.slot.activityType)) at \(item.slot.start.clock)",
         "\(item.slot.minutes) minutes. You planned it, now go get it!")
    }

    /// The agent moved a workout off a meeting.
    static func moved(before: Slot, after: Slot, meeting: (title: String, start: Date)?) -> (title: String, body: String) {
        let noun = Activity.noun(before.activityType)
        let what = meeting.map { "\($0.title) at \($0.start.clock)" } ?? "A meeting"
        return ("\(meeting?.title ?? "A meeting") landed on your \(noun)",
                "\(what) overlaps your \(before.start.clock) \(noun), so I moved it to \(after.start.clock). Still on track!")
    }
}
