import Foundation

/// A mock person's workout history, re-anchored so it ends the day before the
/// story day. The story day is always today (eng review D6), so any day works
/// for a rehearsal.
struct Persona {
    let key: PersonaKey
    let name: String
    let historyStart: Date
    let workouts: [Workout]

    private struct File: Decodable {
        struct Entry: Decodable {
            let id: String
            let activityType: String
            let start: String
            let end: String
            let avgHeartRate: Int?
            let effort: Double?
        }
        let name: String
        let historyStart: String
        let historyEnd: String
        let workouts: [Entry]
    }

    static func load(_ key: PersonaKey, storyDay: Date, calendar: Calendar = .current) -> Persona {
        guard let url = Bundle.main.url(forResource: key.rawValue, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            return Persona(key: key, name: key.name, historyStart: storyDay, workouts: [])
        }

        // Mock times are wall-clock times; read them in the phone's time zone so a
        // lunchtime walk stays at lunchtime wherever the demo runs.
        let parse = DateFormatter()
        parse.calendar = calendar
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = calendar.timeZone
        parse.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let dayParse = DateFormatter()
        dayParse.calendar = calendar
        dayParse.locale = Locale(identifier: "en_US_POSIX")
        dayParse.timeZone = calendar.timeZone
        dayParse.dateFormat = "yyyy-MM-dd"

        let historyEnd = dayParse.date(from: file.historyEnd) ?? storyDay
        let lastDay = calendar.date(byAdding: .day, value: -1, to: storyDay)!
        let shift = calendar.dateComponents([.day], from: historyEnd, to: lastDay).day ?? 0
        func shifted(_ date: Date) -> Date { calendar.date(byAdding: .day, value: shift, to: date) ?? date }

        let workouts: [Workout] = file.workouts.compactMap { entry in
            guard let start = parse.date(from: entry.start), let end = parse.date(from: entry.end) else { return nil }
            return Workout(
                id: entry.id, activityType: entry.activityType,
                start: shifted(start), end: shifted(end),
                effort: entry.effort, avgHeartRate: entry.avgHeartRate, source: .mock
            )
        }
        let historyStart = shifted(dayParse.date(from: file.historyStart) ?? storyDay)
        return Persona(key: key, name: file.name, historyStart: historyStart, workouts: workouts)
    }
}
