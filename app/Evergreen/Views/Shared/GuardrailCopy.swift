import Foundation

/// The words for the brake: the swap card, its decided states and the
/// notifications. Wellness wording only (business notes BN3): Evergreen says
/// what it changed and why ("a big jump from your longest run"), never that a
/// run is safe or that it prevents injury.
enum GuardrailCopy {
    /// "today's", "tomorrow's" or "Sunday's", relative to `now`.
    static func dayPossessive(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today’s" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow’s"
        }
        return date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide)) + "’s"
    }

    /// "Make today’s run 12 km?" or, for a small cut, "Run today’s 18 km easy?"
    static func question(_ run: PlannedRun, _ flag: GuardrailFlag, now: Date, calendar: Calendar = .current) -> String {
        let day = dayPossessive(run.start, now: now, calendar: calendar)
        return flag.keepEasy
            ? "Run \(day) \(flag.planned.label) easy?"
            : "Make \(day) run \(flag.suggested.label)?"
    }

    /// Why, citing the data behind it.
    static func reason(_ flag: GuardrailFlag) -> String {
        switch flag.kind {
        case .spike:
            let longest = flag.longest30?.label ?? "your longest"
            if let percent = flag.jumpPercent {
                return "\(flag.planned.label) is \(percent)% past your longest run this month (\(longest))."
            }
            return "\(flag.planned.label) is a big jump from your longest run this month (\(longest))."
        case .returnSpike:
            return "Coming back after an injury, \(flag.suggested.label) is a gentler start than \(flag.planned.label)."
        case .sore:
            return flag.keepEasy
                ? "You said you’re sore. Keep the distance and run it easy."
                : "You said you’re sore, and this is one of your longer runs."
        case .tired:
            return flag.keepEasy
                ? "You said you’re tired. Keep the distance and run it easy."
                : "You said you’re tired, and this one is long or hard."
        }
    }

    /// "Runna will still say 18 km." The training calendar is never changed.
    static func sourceNote(_ run: PlannedRun, _ planned: RunSize) -> String {
        "\(run.calendarTitle) will still say \(planned.label)."
    }

    /// The primary button: "Make it 12 km" or "Run it easy".
    static func accept(_ flag: GuardrailFlag) -> String {
        flag.keepEasy ? "Run it easy" : "Make it \(flag.suggested.label)"
    }

    /// The ghost button: "Keep 18 km".
    static func keep(_ flag: GuardrailFlag) -> String { "Keep \(flag.planned.label)" }

    /// After the choice (design decision 7): "Changed to 12 km" / "Kept 18 km."
    static func decided(_ decision: GuardrailDecision) -> String {
        switch decision.choice {
        case .accept: decision.keepEasy ? "Running it easy" : "Changed to \(decision.suggested.label)"
        case .keep: "Kept \(decision.planned.label)."
        }
    }

    /// The whole card as one sentence for VoiceOver (design decision 16).
    static func spoken(_ run: PlannedRun, _ flag: GuardrailFlag, now: Date, calendar: Calendar = .current) -> String {
        "\(question(run, flag, now: now, calendar: calendar)) \(reason(flag))"
    }

    // MARK: Notifications (design decision 10)

    /// "Tomorrow’s 18 km is a big jump from your longest run (13 km). Make it 12?"
    static func spikeNote(_ run: PlannedRun, _ flag: GuardrailFlag, now: Date,
                          calendar: Calendar = .current) -> (title: String, body: String) {
        let day = dayPossessive(run.start, now: now, calendar: calendar).capitalized(with: nil)
        let body: String = switch flag.kind {
        case .spike:
            "\(day) \(flag.planned.label) is a big jump from your longest run (\(flag.longest30?.label ?? "this month")). Make it \(Self.number(flag.suggested))?"
        default:
            "\(reason(flag)) Make it \(Self.number(flag.suggested))?"
        }
        return ("Evergreen", body)
    }

    static let morningCheck = (title: "How do your legs feel?", body: "Fresh, tired or sore? I’ll adjust today’s run if it needs it.")

    /// "12" for 12 km, "40 min" for minutes, as in "Make it 12?"
    static func number(_ size: RunSize) -> String {
        size.unit == .km ? String(Int(size.value)) : size.label
    }
}
