import Foundation

/// What the memory bundle needs from the app for one sync: the person, their
/// workouts and the demo clock. Turns into the memory snapshot
/// (memory-agent/docs/CONTRACT.md) with times in the phone's time zone.
struct MemoryInput: Sendable {
    var personaKey: String
    var historyStart: Date
    var now: Date
    var workouts: [Workout]
    var calendar: Calendar

    /// Local midnight that starts `now`'s day: rolling there describes yesterday as a completed day.
    var midnight: Date { calendar.startOfDay(for: now) }

    func timestamp(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.timeZone = calendar.timeZone
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: date)
    }

    /// The snapshot as of `exportDate`. Every day from the history start to the
    /// day before is marked logged: the app has the person's whole history for
    /// those days, so a day without a workout really had none.
    func snapshot(exportDate: Date) -> [String: Any] {
        var days: [[String: Any]] = []
        var day = calendar.startOfDay(for: historyStart)
        let end = calendar.startOfDay(for: exportDate)
        let dayFormat = DateFormatter()
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        while day < end {
            days.append(["date": dayFormat.string(from: day)])
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return [
            "exportDate": timestamp(exportDate),
            "persona": ["key": personaKey],
            "dailySummaries": days,
            "workouts": workouts.filter { $0.end > $0.start }.map(entry),
        ]
    }

    private func entry(_ workout: Workout) -> [String: Any] {
        var entry: [String: Any] = [
            "id": "wk_" + MemoryFiles.sha256(workout.id).prefix(16),
            "activityType": workout.activityType,
            "start": timestamp(workout.start),
            "end": timestamp(workout.end),
            "durationMin": min(1440, (workout.minutes * 100).rounded() / 100),
            "source": Self.source(workout.source),
        ]
        if let effort = workout.effort, (1...10).contains(effort) {
            entry["effort"] = (effort * 100).rounded() / 100
        }
        return entry
    }

    /// The memory bundle's sources are mock, phone, watch and manual.
    private static func source(_ source: Workout.Source) -> String {
        switch source {
        case .mock: "mock"
        case .health: "phone"
        case .demo: "manual"
        }
    }
}
