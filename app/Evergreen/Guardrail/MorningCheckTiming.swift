import Foundation

/// When the morning check is asked for a run (plan item 7): 7 AM or 60
/// minutes before the run, whichever is earlier, never before 5 AM. A run
/// before 6 AM is asked at 8 PM the evening before. The card shows from then
/// until the run starts.
enum MorningCheckTiming {
    static func asks(for run: PlannedRun, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: run.start)
        let hour = calendar.component(.hour, from: run.start)
        if hour < 6 {
            let evening = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: evening) ?? evening
        }
        let seven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
        let five = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: day) ?? day
        return max(five, min(seven, run.start.addingTimeInterval(-3600)))
    }

    /// When the Today card appears: 5 AM on the day, or when it's asked if that's earlier.
    static func opens(for run: PlannedRun, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: run.start)
        let five = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: day) ?? day
        return min(five, asks(for: run, calendar: calendar))
    }
}
