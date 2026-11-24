import Foundation

/// The weekly pain check-in's calendar (plan item 17): weeks run Monday to
/// Sunday in local time. Sunday's week is asked at 6 PM, and its card stays
/// until Tuesday night; after that the week is "no answer".
enum PainWeek {
    static let askHour = 18

    /// Monday 00:00 of the week `date` falls in.
    static func monday(of date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Sunday 6 PM of the week starting `weekStart`.
    static func asksAt(_ weekStart: Date, calendar: Calendar) -> Date {
        let sunday = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return calendar.date(bySettingHour: askHour, minute: 0, second: 0, of: sunday) ?? sunday
    }

    /// The end of the Tuesday after the week (Wednesday 00:00).
    static func closesAt(_ weekStart: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 9, to: weekStart) ?? weekStart
    }

    /// The week being asked about at `now`: from its Sunday 6 PM through Tuesday night.
    static func openWeek(at now: Date, calendar: Calendar) -> Date? {
        let thisWeek = monday(of: now, calendar: calendar)
        if now >= asksAt(thisWeek, calendar: calendar) { return thisWeek }
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        return now < closesAt(lastWeek, calendar: calendar) ? lastWeek : nil
    }
}
