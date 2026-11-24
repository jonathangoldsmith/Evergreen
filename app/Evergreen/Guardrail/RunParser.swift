import Foundation

/// Decides which events on a training calendar are planned runs, and how big
/// (plan items 1 and 3). An event is a run when its title has a run word or a
/// distance. The size comes from the title ("Long run 18 km", "Easy 45 min");
/// failing that, a timed event's own length is its duration.
enum RunParser {
    static let runWords: Set<String> = [
        "run", "running", "long", "easy", "tempo", "interval", "intervals", "threshold",
        "recovery", "fartlek", "hills", "track", "race",
    ]
    static let hardWords: Set<String> = [
        "tempo", "interval", "intervals", "threshold", "repeats", "hills", "fartlek", "track", "vo2", "vo2max",
    ]
    /// All-day runs with a size are treated as 8 AM runs (item 1).
    static let allDayHour = 8

    static func parse(
        title: String, start: Date, end: Date, isAllDay: Bool,
        calendarId: String, calendarTitle: String, calendar: Calendar
    ) -> PlannedRun? {
        let words = Self.words(title)
        let distance = Self.distanceKm(title)
        guard distance != nil || !words.isDisjoint(with: runWords) else { return nil }

        let titleMinutes = Self.durationMinutes(title)
        let size: RunSize? = if let distance {
            .km(distance)
        } else if let titleMinutes {
            .minutes(titleMinutes)
        } else if !isAllDay {
            .minutes((end.timeIntervalSince(start) / 60).rounded())
        } else {
            nil
        }

        var runStart = start
        var runEnd = end
        if isAllDay {
            let day = calendar.startOfDay(for: start)
            runStart = calendar.date(bySettingHour: allDayHour, minute: 0, second: 0, of: day) ?? day
            runEnd = runStart.addingTimeInterval((titleMinutes ?? 60) * 60)
        }

        let lower = title.lowercased()
        let hard = !words.isDisjoint(with: hardWords) || lower.contains("race pace")
        let day = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
            .format(calendar.startOfDay(for: runStart))
        return PlannedRun(
            key: "\(calendarId)|\(day)|\(title)", title: title, calendarTitle: calendarTitle,
            start: runStart, end: runEnd, size: size, isHard: hard, isAllDay: isAllDay
        )
    }

    // MARK: Title parsing

    static func words(_ title: String) -> Set<String> {
        Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// "18 km", "18km", "10k", "6.2 mi", "5 miles": in km. Nil without a distance.
    static func distanceKm(_ title: String) -> Double? {
        let pattern = /(?i)(\d+(?:[.,]\d+)?)\s*(km|k|mi|miles?)\b/
        guard let match = title.firstMatch(of: pattern),
              let value = Double(match.1.replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let unit = match.2.lowercased()
        return unit.hasPrefix("mi") ? (value * 1.609344 * 10).rounded() / 10 : value
    }

    /// "45 min", "45min", "1h", "1 h 30", "1.5 hours": in minutes. Nil without one.
    static func durationMinutes(_ title: String) -> Double? {
        if let match = title.firstMatch(of: /(?i)(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)\b(?:\s*(\d+)\s*(?:m|min|mins|minutes)?\b)?/),
           let hours = Double(match.1) {
            let extra = match.2.flatMap { Double($0) } ?? 0
            return hours * 60 + extra
        }
        if let match = title.firstMatch(of: /(?i)(\d+)\s*(?:m|min|mins|minutes)\b/), let minutes = Double(match.1) {
            return minutes
        }
        return nil
    }
}
