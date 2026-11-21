import Foundation

/// Hand-written demo plan (eng review D12): Jordan's three workouts, starting
/// with tonight's 6 PM run. Claude's live `/plan` runs only before going on
/// stage or in an optional "regenerate" beat.
enum PinnedPlan {
    /// What a workout is for, so Evergreen can say why it picked it.
    enum Focus { case easy, long, strength }

    struct Entry {
        let focus: Focus
        let dayOffset: Int
        let hour: Int
        let minute: Int
        let minutes: Int
        let activityType: String
    }

    static func entries(for key: PersonaKey) -> [Entry] {
        switch key {
        case .jordan:
            [
                Entry(focus: .easy, dayOffset: 0, hour: 18, minute: 0, minutes: 45, activityType: "Running"),
                Entry(focus: .long, dayOffset: 1, hour: 8, minute: 30, minutes: 90, activityType: "Running"),
                Entry(focus: .strength, dayOffset: 2, hour: 7, minute: 0, minutes: 40, activityType: "FunctionalStrengthTraining"),
            ]
        case .me:
            [] // A real person's week comes from their history (HistoryPlan).
        }
    }

    /// The plan is "made" at 5 AM on the story day, so earlier windows never count
    /// as misses (outside voice 10).
    static func createdAt(storyDay: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 5, to: storyDay)!
    }

    static func id(_ key: PersonaKey, _ entry: Entry) -> String {
        "plan-\(key.rawValue)-d\(entry.dayOffset)-\(entry.hour)\(entry.minute)"
    }

    /// The focus of a pinned workout, by its plan item id.
    static func focus(for itemId: String, key: PersonaKey) -> Focus? {
        entries(for: key).first { id(key, $0) == itemId }?.focus
    }

    static func items(for key: PersonaKey, storyDay: Date, calendar: Calendar = .current) -> [PlanItem] {
        entries(for: key).map { entry in
            let day = calendar.date(byAdding: .day, value: entry.dayOffset, to: storyDay)!
            let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day)!
            let end = start.addingTimeInterval(Double(entry.minutes) * 60)
            return PlanItem(
                id: id(key, entry),
                slot: Slot(start: start, end: end, activityType: entry.activityType),
                points: StandInAgent.basePoints,
                source: .plan
            )
        }
    }
}
