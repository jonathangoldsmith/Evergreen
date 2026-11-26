import Foundation

/// One event on the Evergreen calendar, as the plan says it should be.
/// The key goes in the event's URL field, so each plan item maps to one event
/// across launches and repeated ticks (outside voice 5). `eventIdentifier` is
/// never used as a key.
struct CalendarEntry: Equatable, Sendable {
    static let scheme = "evergreen"
    /// The scheme events carried before the rename from Tracker++. They're
    /// still read as the app's own, so a sync replaces them instead of leaving
    /// a duplicate next to each new event.
    static let legacySchemes: Set<String> = ["trackerplusplus"]

    /// Whether an event URL is one of the app's plan keys, new or from before the rename.
    static func isAppKey(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme else { return false }
        return scheme == Self.scheme || legacySchemes.contains(scheme)
    }

    let key: URL
    let title: String
    let notes: String
    let start: Date
    let end: Date

    /// One entry per plan item, keyed by the story day and the item's id. The
    /// story day is in the key because pinned plan ids repeat from day to day.
    /// `reasons` holds the latest action's reason for each plan item it touched;
    /// `titles` overrides an item's title (a swap: "Easy run 12 km (was 18 km)").
    static func entries(
        for plan: [PlanItem], reasons: [String: String], titles: [String: String] = [:],
        storyDay: Date, calendar: Calendar
    ) -> [CalendarEntry] {
        let day = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day().format(storyDay)
        return plan.compactMap { item in
            guard let key = URL(string: "\(scheme)://plan/\(day)/\(item.id)") else { return nil }
            return CalendarEntry(
                key: key,
                title: titles[item.id] ?? title(for: item),
                notes: [reasons[item.id], "Planned by Evergreen."].compactMap(\.self).joined(separator: "\n\n"),
                start: item.slot.start,
                end: item.slot.end
            )
        }
    }

    /// "Walk", "Comeback walk · 2× points" or "Run (routine)".
    private static func title(for item: PlanItem) -> String {
        switch item.source {
        case .plan: Activity.title(item.slot.activityType)
        case .comeback: "Comeback \(Activity.noun(item.slot.activityType)) · 2× points"
        case .routine: "\(Activity.title(item.slot.activityType)) (routine)"
        case .swap: "Easy \(Activity.noun(item.slot.activityType))"
        case .returnSession: "Walk-run (return plan)"
        }
    }
}
