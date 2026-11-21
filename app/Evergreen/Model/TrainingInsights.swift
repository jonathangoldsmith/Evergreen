import Foundation

/// What Evergreen reads from Apple Health workouts to tailor the plan: recent
/// load against the person's usual week, their longest recent run and their
/// heart rate. Computed on the phone from the workouts it already has.
struct TrainingInsights: Equatable {
    /// Runs in the last 30 days.
    var runs30: Int
    /// Average heart rate across the last 7 days' workouts, if any carried one.
    var avgHeartRate: Int?
    /// Training minutes in the last 7 days.
    var weekMinutes: Int
    /// The usual week: average weekly minutes over the 3 weeks before that.
    var usualWeekMinutes: Int
    /// The longest run in the last 14 days, in minutes.
    var longestRecentRun: Int

    /// Last week against the usual one: 0.18 is 18% more.
    var loadChange: Double {
        usualWeekMinutes > 0 ? Double(weekMinutes - usualWeekMinutes) / Double(usualWeekMinutes) : 0
    }

    init(workouts: [Workout], storyDay: Date, calendar: Calendar = .current) {
        func since(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: storyDay) ?? storyDay }
        let past = workouts.filter { $0.start < storyDay }
        let week = past.filter { $0.start >= since(7) }
        let before = past.filter { $0.start >= since(28) && $0.start < since(7) }
        runs30 = past.filter { $0.activityType == "Running" && $0.start >= since(30) }.count
        let rates = week.compactMap(\.avgHeartRate)
        avgHeartRate = rates.isEmpty ? nil : rates.reduce(0, +) / rates.count
        weekMinutes = Int(week.reduce(0) { $0 + $1.minutes }.rounded())
        usualWeekMinutes = Int((before.reduce(0) { $0 + $1.minutes } / 3).rounded())
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
