import Foundation

/// Sleep the agent defends (TODOS item 4): the evening before a long or hard
/// morning run, a bedtime that leaves the person's usual night of sleep
/// before they're up for it. "Lights out by 10:30 for tomorrow’s long run."
/// One pure function over plain values, like the brake's rule. The numbers
/// are provisional.
///
/// It doesn't nag: one a night, at most `perWeek` a week (the biggest runs
/// first), never sent after 10 PM, and the first note dropped when a night
/// already has two (`GuardrailSchedule`). After a short night, readiness
/// (`BodySignal`) eases the run. Wellness wording: it says when to sleep for
/// the run, never what skipping it does.
struct Bedtime: Equatable, Sendable {
    enum Why: String, Equatable, Sendable { case long, hard }

    var run: PlannedRun
    var why: Why
    /// Up this long before the run.
    var wake: Date
    var lightsOut: Date
    /// The person's usual night, if Evergreen has enough nights to know it.
    var usualSleep: Double?
    /// When the note goes out: an hour before lights out.
    var fireAt: Date

    /// Up an hour before the run.
    static let wakeLead: TimeInterval = 60 * 60
    /// Without enough nights, plan for 7h 30.
    static let defaultSleep = 450.0
    /// Never plan for less than 7 hours, even for someone who usually sleeps less.
    static let minimumSleep = 420.0
    /// Nights needed to know the usual, from the 28 before.
    static let minimumNights = 7
    static let usualNights = 28
    /// Lights out no earlier than 9 PM; a run that leaves room to sleep past 11 PM needs no nudge.
    static let earliestHour = 21
    static let latestHour = 23
    /// The note an hour before lights out, so it's never sent after 10 PM.
    static let noteLead: TimeInterval = 60 * 60
    /// One a night, and this many a week.
    static let perWeek = 2
    /// Today shows the line from 6 PM the evening before.
    static let showsFromHour = 18

    /// The night planned for, in minutes: the usual, at least 7 hours.
    var planned: Double {
        max(usualSleep ?? Self.defaultSleep, Self.minimumSleep)
    }

    /// An early run pushed lights out to 9 PM, leaving less than `planned`.
    var isShort: Bool { wake.timeIntervalSince(lightsOut) / 60 < planned - 1 }

    /// The usual night: the average of the 28 nights before `day`, once 7 are known.
    static func usualSleep(_ days: [HealthHistory.Day], before day: Date, calendar: Calendar) -> Double? {
        let today = calendar.startOfDay(for: day)
        let from = calendar.date(byAdding: .day, value: -usualNights, to: today) ?? today
        let nights = days.filter { $0.date >= from && $0.date < today }.compactMap(\.sleepMin).filter { $0 > 0 }
        return nights.count >= minimumNights ? nights.reduce(0, +) / Double(nights.count) : nil
    }

    /// The bedtimes for `runs`, at most one a night and `perWeek` a week.
    static func plan(runs: [PlannedRun], usualSleep: Double?, calendar: Calendar) -> [Bedtime] {
        let context = GuardrailRule.Context(history: [], injuryMonth: nil, check: nil, upcoming: runs, calendar: calendar)
        let each = runs.compactMap { make($0, context: context, usualSleep: usualSleep, calendar: calendar) }
        // One a night: the earliest run of the morning sets the alarm.
        let nights = Dictionary(grouping: each) { calendar.startOfDay(for: $0.run.start) }.values
            .compactMap { $0.min { $0.lightsOut < $1.lightsOut } }
        // At most `perWeek` a week: long runs first, then the longest, then the earliest.
        let weeks = Dictionary(grouping: nights) { PainWeek.monday(of: $0.run.start, calendar: calendar) }.values
        return weeks.flatMap { week in
            week.sorted { a, b in
                if a.why != b.why { return a.why == .long }
                if a.run.minutes != b.run.minutes { return a.run.minutes > b.run.minutes }
                return a.run.start < b.run.start
            }.prefix(perWeek)
        }.sorted { $0.fireAt < $1.fireAt }
    }

    static func make(_ run: PlannedRun, context: GuardrailRule.Context, usualSleep: Double?,
                     calendar: Calendar) -> Bedtime? {
        guard !run.isAllDay else { return nil }
        let long = run.size.map { GuardrailRule.isLong(run, $0, context) }
            ?? (run.minutes >= (GuardrailRule.longThreshold[.minutes] ?? 60))
        guard long || run.isHard else { return nil }
        let wake = run.start.addingTimeInterval(-wakeLead)
        let sleep = max(usualSleep ?? defaultSleep, minimumSleep)
        let evening = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: run.start)) ?? run.start
        guard let earliest = calendar.date(bySettingHour: earliestHour, minute: 0, second: 0, of: evening),
              let latest = calendar.date(bySettingHour: latestHour, minute: 0, second: 0, of: evening) else { return nil }
        // A quarter hour down from the wake-up less the night, but not before 9 PM.
        let ideal = wake.addingTimeInterval(-sleep * 60)
        let quarter = (ideal.timeIntervalSince(earliest) / 900).rounded(.down) * 900
        let lightsOut = max(earliest, earliest.addingTimeInterval(quarter))
        guard lightsOut <= latest else { return nil }
        return Bedtime(run: run, why: long ? .long : .hard, wake: wake, lightsOut: lightsOut,
                       usualSleep: usualSleep, fireAt: lightsOut.addingTimeInterval(-noteLead))
    }

    /// Whether Today shows the line: from 6 PM the evening before until the run's day starts.
    func shows(at now: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: run.start)
        let evening = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let from = calendar.date(bySettingHour: Self.showsFromHour, minute: 0, second: 0, of: evening) ?? evening
        return now >= from && now < day
    }

    // MARK: Words

    private var runWord: String { why == .long ? "long run" : "hard workout" }

    /// Today's line: "Lights out by 10:30 for tomorrow’s long run."
    func line(calendar: Calendar) -> String {
        "Lights out by \(Self.time(lightsOut, calendar, amPM: false)) for tomorrow’s \(runWord)."
    }

    /// Under it: "That leaves your usual 7h 30 of sleep before a 6:00 wake-up."
    func reason(calendar: Calendar) -> String {
        let wakeUp = Self.time(wake, calendar, amPM: false)
        if isShort {
            return "That leaves \(GuardrailCopy.sleepLabel(wake.timeIntervalSince(lightsOut) / 60)) of sleep before a \(wakeUp) wake-up."
        }
        let usual = (usualSleep ?? 0) >= Self.minimumSleep
        return "That leaves \(usual ? "your usual " : "")\(GuardrailCopy.sleepLabel(planned)) of sleep before a \(wakeUp) wake-up."
    }

    /// The Lock Screen note, with no sleep numbers on it.
    func note(calendar: Calendar) -> (title: String, body: String) {
        ("Lights out by \(Self.time(lightsOut, calendar, amPM: false))",
         "Tomorrow’s \(runWord) is at \(Self.time(run.start, calendar, amPM: true)). "
            + "That leaves a full night before a \(Self.time(wake, calendar, amPM: false)) wake-up.")
    }

    static func time(_ date: Date, _ calendar: Calendar, amPM: Bool) -> String {
        var style = Date.FormatStyle(timeZone: calendar.timeZone).locale(Locale(identifier: "en_US"))
        style = amPM ? style.hour().minute() : style.hour(.defaultDigits(amPM: .omitted)).minute()
        return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
