import Foundation

/// Hand-written demo plans (eng review D12). Sam's always includes the lunchtime
/// walk on the story day, so the 1:30 PM miss happens every rehearsal; Claude's
/// live `/plan` runs only before going on stage or in an optional "regenerate" beat.
enum PinnedPlan {
    struct Entry {
        let dayOffset: Int
        let hour: Int
        let minute: Int
        let minutes: Int
        let activityType: String
    }

    static func entries(for key: PersonaKey) -> [Entry] {
        switch key {
        case .sam:
            [
                Entry(dayOffset: 0, hour: 12, minute: 0, minutes: 30, activityType: "Walking"),
                Entry(dayOffset: 1, hour: 7, minute: 30, minutes: 25, activityType: "Elliptical"),
                Entry(dayOffset: 3, hour: 10, minute: 0, minutes: 30, activityType: "TraditionalStrengthTraining"),
            ]
        case .alex:
            [
                Entry(dayOffset: 0, hour: 12, minute: 30, minutes: 45, activityType: "TraditionalStrengthTraining"),
                Entry(dayOffset: 1, hour: 18, minute: 0, minutes: 30, activityType: "Running"),
                Entry(dayOffset: 2, hour: 9, minute: 0, minutes: 40, activityType: "Yoga"),
            ]
        case .jordan:
            [
                Entry(dayOffset: 0, hour: 18, minute: 0, minutes: 45, activityType: "Running"),
                Entry(dayOffset: 1, hour: 8, minute: 30, minutes: 90, activityType: "Running"),
                Entry(dayOffset: 2, hour: 7, minute: 0, minutes: 40, activityType: "FunctionalStrengthTraining"),
            ]
        }
    }

    /// The plan is "made" at 5 AM on the story day, so earlier windows never count
    /// as misses (outside voice 10).
    static func createdAt(storyDay: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 5, to: storyDay)!
    }

    static func items(for key: PersonaKey, storyDay: Date, calendar: Calendar = .current) -> [PlanItem] {
        entries(for: key).map { entry in
            let day = calendar.date(byAdding: .day, value: entry.dayOffset, to: storyDay)!
            let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day)!
            let end = start.addingTimeInterval(Double(entry.minutes) * 60)
            return PlanItem(
                id: "plan-\(key.rawValue)-d\(entry.dayOffset)-\(entry.hour)\(entry.minute)",
                slot: Slot(start: start, end: end, activityType: entry.activityType),
                points: StandInAgent.basePoints,
                source: .plan
            )
        }
    }
}
