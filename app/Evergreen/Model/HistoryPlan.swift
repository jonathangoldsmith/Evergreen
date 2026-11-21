import Foundation

/// The week for a real person, from their own Apple Health history: each
/// weekday they've trained on at least twice in the last 4 weeks becomes a
/// workout at their usual time, of their usual kind and length. The longest
/// usual run is the long run. With no pattern yet, a gentle starter week of two
/// short walks while Evergreen learns their routine (eng review D8).
/// Deterministic, offline and instant; the harness planner refines it in the
/// "Next 7 days" preview.
enum HistoryPlan {
    struct Entry: Equatable {
        var focus: PinnedPlan.Focus
        /// 1 = Sunday … 7 = Saturday, like `Calendar.component(.weekday)`.
        var weekday: Int
        /// Minutes after midnight.
        var startMinute: Int
        var minutes: Int
        var activityType: String
        /// From the person's pattern (true) or the starter week (false).
        var usual: Bool
    }

    static let lookbackDays = 28
    static let minimumDays = 2

    /// Each weekday's usual workout over the last 4 weeks before `storyDay`.
    static func usualWeek(_ workouts: [Workout], storyDay: Date, calendar: Calendar) -> [Entry] {
        let from = calendar.date(byAdding: .day, value: -lookbackDays, to: storyDay) ?? storyDay
        let recent = workouts.filter { $0.start >= from && $0.start < storyDay && $0.minutes >= 10 && $0.activityType != "Other" }
        var entries: [Entry] = []
        for (weekday, rows) in Dictionary(grouping: recent, by: { calendar.component(.weekday, from: $0.start) }) {
            guard Set(rows.map { calendar.startOfDay(for: $0.start) }).count >= minimumDays else { continue }
            let counts = Dictionary(grouping: rows, by: \.activityType).mapValues(\.count)
            guard let activity = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { continue }
            let same = rows.filter { $0.activityType == activity }
            let minutes = max(15, Int((median(same.map(\.minutes)) / 5).rounded()) * 5)
            let starts = same.map { Double(calendar.component(.hour, from: $0.start) * 60 + calendar.component(.minute, from: $0.start)) }
            let start = Int((median(starts) / 15).rounded()) * 15
            entries.append(Entry(focus: focus(activity), weekday: weekday, startMinute: start, minutes: minutes,
                                 activityType: activity, usual: true))
        }
        // The longest usual run, when it's a real long run, is the week's long run.
        let runs = entries.indices.filter { entries[$0].activityType == "Running" }
        if let long = runs.max(by: { entries[$0].minutes < entries[$1].minutes }), entries[long].minutes >= 60 {
            entries[long].focus = .long
        }
        return entries.sorted { $0.weekday < $1.weekday }
    }

    /// Two 30-minute evening walks, the day after the story day and three days later.
    static func starterWeek(storyDay: Date, calendar: Calendar) -> [(day: Date, entry: Entry)] {
        [1, 3].compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: storyDay) else { return nil }
            return (day, Entry(focus: .easy, weekday: calendar.component(.weekday, from: day), startMinute: 18 * 60,
                               minutes: 30, activityType: "Walking", usual: false))
        }
    }

    /// The next 7 days from the story day, each with its day. A workout on the
    /// story day that started before `madeAt` (the plan was made mid-day) is left out.
    static func week(_ workouts: [Workout], storyDay: Date, calendar: Calendar,
                     madeAt: Date? = nil) -> [(day: Date, entry: Entry)] {
        let usual = usualWeek(workouts, storyDay: storyDay, calendar: calendar)
        guard !usual.isEmpty else { return starterWeek(storyDay: storyDay, calendar: calendar) }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: storyDay),
                  let entry = usual.first(where: { $0.weekday == calendar.component(.weekday, from: day) })
            else { return nil }
            if offset == 0, let madeAt,
               let start = calendar.date(byAdding: .minute, value: entry.startMinute, to: calendar.startOfDay(for: day)),
               start < madeAt {
                return nil
            }
            return (day, entry)
        }
    }

    static func items(_ workouts: [Workout], storyDay: Date, calendar: Calendar, madeAt: Date? = nil) -> [PlanItem] {
        week(workouts, storyDay: storyDay, calendar: calendar, madeAt: madeAt).compactMap { day, entry in
            guard let start = calendar.date(byAdding: .minute, value: entry.startMinute, to: calendar.startOfDay(for: day)) else { return nil }
            return PlanItem(
                id: id(day: day, entry: entry, calendar: calendar),
                slot: Slot(start: start, end: start.addingTimeInterval(Double(entry.minutes) * 60), activityType: entry.activityType),
                points: StandInAgent.basePoints,
                source: .plan
            )
        }
    }

    /// "plan-me-2026-11-24-running": stable for the day, so repeat ticks and calendar syncs match.
    static func id(day: Date, entry: Entry, calendar: Calendar) -> String {
        let date = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day().format(day)
        return "plan-me-\(date)-\(entry.activityType.lowercased())"
    }

    /// Why this workout is on the week, from the person's own pattern.
    static func reason(for item: PlanItem, workouts: [Workout], storyDay: Date, calendar: Calendar,
                       insights: TrainingInsights) -> String? {
        guard let entry = week(workouts, storyDay: storyDay, calendar: calendar)
            .first(where: { id(day: $0.day, entry: $0.entry, calendar: calendar) == item.id })?.entry
        else { return nil }
        guard entry.usual else { return "A short walk to start while I learn your routine." }
        let day = item.slot.start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide))
        let noun = Activity.noun(entry.activityType)
        switch entry.focus {
        case .long:
            return "Your long run: you usually go \(entry.minutes) min on \(day)s."
        case .easy:
            let percent = Int((insights.loadChange * 100).rounded())
            return percent >= 10
                ? "Your usual \(day) \(noun), kept easy: your load is up \(percent)%."
                : "Your usual \(day) \(noun), at the time you usually go."
        case .strength:
            return "Your usual \(day) strength session."
        }
    }

    private static func focus(_ activity: String) -> PinnedPlan.Focus {
        activity.contains("StrengthTraining") ? .strength : .easy
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
