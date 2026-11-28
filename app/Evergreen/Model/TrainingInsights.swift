import Foundation

/// What Evergreen reads from Apple Health workouts to tailor the plan: recent
/// training load against the person's usual, their longest recent run and
/// their heart rate. Computed on the phone from the workouts it already has.
///
/// Training load works like Apple Fitness's: each workout's effort (1–10)
/// times its minutes, the last 7 days against the last 28. The effort is the
/// person's own rating, else Apple's estimate, else one from the workout's
/// average heart rate (the hackathon plan's fallback), else `unratedEffort`.
struct TrainingInsights: Equatable {
    /// Runs in the last 30 days.
    var runs30: Int
    /// Average heart rate across the last 7 days' workouts, if any carried one.
    var avgHeartRate: Int?
    /// Training minutes in the last 7 days.
    var weekMinutes: Int
    /// Training load (effort × minutes) in the last 7 days, and in the last 28 (the 7 included).
    var weekLoad: Double
    var monthLoad: Double
    /// Days of history in each window: 7 and 28, or fewer when the first
    /// workout Evergreen knows of is more recent, so a short history isn't
    /// read as weeks of rest.
    var weekDays: Double = 7
    var monthDays: Double = 28
    /// The average effort per minute over the last 28 days, for turning load into minutes.
    var typicalEffort: Double
    /// The longest run in the last 14 days, in minutes.
    var longestRecentRun: Int

    /// A workout with no rating, no estimate and no heart rate counts as moderate.
    static let unratedEffort = 5.0

    /// Apple's scale from average heart rate: 3 easy (under 135), 4 (135–149),
    /// 5 moderate (150–159), 7 hard (160+). Provisional, like the brake's thresholds.
    static func estimatedEffort(_ averageHeartRate: Int) -> Double {
        averageHeartRate >= 160 ? 7 : averageHeartRate >= 150 ? 5 : averageHeartRate >= 135 ? 4 : 3
    }

    /// The usual week's load: the 28-day load per day, times 7. Per day of
    /// history actually covered, so two weeks of history aren't halved.
    var usualWeekLoad: Double { monthLoad / monthDays * 7 }

    /// The 7-day load against the 28-day one, per day, as Apple Fitness shows
    /// it: 0.18 is 18% more.
    var loadChange: Double {
        monthLoad > 0 ? (weekLoad / weekDays) / (monthLoad / monthDays) - 1 : 0
    }

    static func load(_ workout: Workout) -> Double {
        (workout.effort ?? workout.avgHeartRate.map(estimatedEffort) ?? unratedEffort) * workout.minutes
    }

    init(workouts: [Workout], storyDay: Date, calendar: Calendar = .current) {
        func since(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: storyDay) ?? storyDay }
        let past = workouts.filter { $0.start < storyDay }
        // From the first workout's day: history shorter than a window covers only its own days.
        let covered = past.map(\.start).min().map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: storyDay)).day ?? 0
        } ?? 28
        weekDays = Double(min(7, max(covered, 1)))
        monthDays = Double(min(28, max(covered, 1)))
        let week = past.filter { $0.start >= since(7) }
        let month = past.filter { $0.start >= since(28) }
        runs30 = past.filter { $0.activityType == "Running" && $0.start >= since(30) }.count
        let rates = week.compactMap(\.avgHeartRate)
        avgHeartRate = rates.isEmpty ? nil : rates.reduce(0, +) / rates.count
        weekMinutes = Int(week.reduce(0) { $0 + $1.minutes }.rounded())
        weekLoad = week.reduce(0) { $0 + Self.load($1) }
        monthLoad = month.reduce(0) { $0 + Self.load($1) }
        let monthMinutes = month.reduce(0) { $0 + $1.minutes }
        typicalEffort = monthMinutes > 0 ? monthLoad / monthMinutes : Self.unratedEffort
        longestRecentRun = Int(past
            .filter { $0.activityType == "Running" && $0.start >= since(14) }
            .map(\.minutes).max()?.rounded() ?? 0)
    }
}

extension AppModel {
    var insights: TrainingInsights { TrainingInsights(workouts: workouts, storyDay: storyDay) }

    /// Why Evergreen picked this workout, from the health data and the calendar:
    /// "Easy pace. Your training load is up 18% on your usual week, so tonight stays light."
    func reason(for item: PlanItem) -> String? {
        if persona.key.isReal {
            return HistoryPlan.reason(for: item, workouts: health.workouts, storyDay: storyDay, calendar: .current,
                                      insights: insights)
        }
        guard let focus = PinnedPlan.focus(for: item.id, key: persona.key) else { return nil }
        let data = insights
        switch focus {
        case .easy:
            let percent = Int((data.loadChange * 100).rounded())
            return percent >= 10
                ? "Easy pace: your load is up \(percent)%."
                : "Easy pace to keep your week steady."
        case .long:
            let extra = item.slot.minutes - data.longestRecentRun
            return data.longestRecentRun > 0 && extra > 0
                ? "Builds endurance: \(extra) min past your longest run."
                : "Builds endurance in your open morning."
        case .strength:
            return "Strength for your legs as miles climb."
        }
    }

    /// "Calendar: free Fri evening, Sat & Sun mornings"
    var openTimesShort: String {
        var byPart: [(part: String, days: [String])] = []
        for item in plan {
            let hour = Calendar.current.component(.hour, from: item.slot.start)
            let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
            let day = item.slot.start.formatted(.dateTime.weekday(.abbreviated))
            if let i = byPart.firstIndex(where: { $0.part == part }) { byPart[i].days.append(day) }
            else { byPart.append((part, [day])) }
        }
        let parts = byPart.map { group in
            group.days.joined(separator: " & ") + " " + group.part + (group.days.count > 1 ? "s" : "")
        }
        return "Calendar: free " + parts.joined(separator: ", ")
    }

    /// "Friday evening, Saturday morning and Sunday morning": when the plan's
    /// workouts sit, which is where the calendar had room.
    var openTimes: String {
        let parts = plan.map { item -> String in
            let hour = Calendar.current.component(.hour, from: item.slot.start)
            let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
            return "\(item.slot.start.formatted(.dateTime.weekday(.wide))) \(part)"
        }
        return parts.formatted(.list(type: .and))
    }
}
