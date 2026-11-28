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
        case .load:
            return "\(flag.planned.label) would put your 7-day training load more than 30% over your usual. \(flag.suggested.label) keeps it in range."
        case .body:
            let readings = flag.body.map(bodyReadings) ?? "This morning’s readings are off your usual"
            return flag.keepEasy
                ? "\(readings). Keep the distance and run it easy."
                : "\(readings), and this one is long or hard."
        }
    }

    /// "Your resting heart rate is 6 bpm above your usual and you slept 5h 40
    /// instead of your usual 7h 30": each reading that's off, with its numbers.
    static func bodyReadings(_ body: BodySignal) -> String {
        let parts = body.off.map { off -> String in
            switch off.reading {
            case .restingHeartRate:
                "your resting heart rate is \(Int((off.now - off.usual).rounded())) bpm above your usual"
            case .hrv:
                "your heart rate variability is \(Int(((1 - off.now / off.usual) * 100).rounded()))% under your usual"
            case .sleep:
                "you slept \(sleepLabel(off.now)) instead of your usual \(sleepLabel(off.usual))"
            }
        }
        return capitalizedFirst(joined(parts))
    }

    /// "resting heart rate and sleep": which readings, without their values,
    /// for the Lock Screen.
    static func bodyReadingNames(_ body: BodySignal) -> String {
        joined(body.off.map {
            switch $0.reading {
            case .restingHeartRate: "resting heart rate"
            case .hrv: "heart rate variability"
            case .sleep: "sleep"
            }
        })
    }

    /// "5h 40", or "7h" on the hour, to the nearest 5 minutes.
    static func sleepLabel(_ minutes: Double) -> String {
        let total = Int((minutes / 5).rounded()) * 5
        let (hours, rest) = (total / 60, total % 60)
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest < 10 ? "0" : "")\(rest)"
    }

    /// "a", "a and b", "a, b and c".
    static func joined(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
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
    /// The morning check's answer when there's no swap to offer (design decision 7).
    static func checkedIn(_ check: MorningCheck) -> String {
        switch check {
        case .fresh: "Got it. Enjoy the run."
        case .tired, .sore: "Keep it easy today."
        }
    }

    /// A swap with calendar access off (design decision 7).
    static let calendarOff = "Changed in Evergreen. Allow calendar access to update your calendar."

    static func decided(_ decision: GuardrailDecision) -> String {
        switch decision.choice {
        case .accept: decision.keepEasy ? "Running it easy" : "Changed to \(decision.suggested.label)"
        case .keep: "Kept \(decision.planned.label)."
        }
    }

    // MARK: VoiceOver (design decision 16): each card as one sentence

    /// "Thursday · Easy 40 min at 6:00 PM", under each run card's headline.
    static func runLine(_ run: PlannedRun) -> String {
        "\(run.start.formatted(.dateTime.weekday(.wide))) · \(run.title) at \(run.start.clock)"
    }

    /// "Thursday’s Easy 40 min at 6:00 PM", the same for VoiceOver.
    static func spokenRun(_ run: PlannedRun) -> String {
        "\(run.start.formatted(.dateTime.weekday(.wide)))’s \(run.title) at \(run.start.clock)"
    }

    /// "Change tomorrow’s run from 18 km to 12 km? 18 km is 38% past your longest
    /// run this month (13 km)." The strikethrough is visual only, so the
    /// spoken question says both sizes.
    static func spoken(_ run: PlannedRun, _ flag: GuardrailFlag, now: Date, calendar: Calendar = .current) -> String {
        let day = dayPossessive(run.start, now: now, calendar: calendar)
        let ask = flag.keepEasy
            ? question(run, flag, now: now, calendar: calendar)
            : "Change \(day) run from \(flag.planned.label) to \(flag.suggested.label)?"
        return "\(ask) \(reason(flag))"
    }

    /// "Changed to 12 km: Monday’s Long run at 8:00 AM. Runna will still say 18 km."
    static func spokenDecided(_ decision: GuardrailDecision, run: PlannedRun, calendarOn: Bool) -> String {
        var line = "\(decided(decision).trimmingCharacters(in: ["."])): \(spokenRun(run))."
        if decision.choice == .accept {
            line += " \(sourceNote(run, decision.planned))"
            if !calendarOn { line += " \(calendarOff)" }
        }
        return line
    }

    /// "How do your legs feel before Thursday’s Easy 40 min at 6:00 PM?"
    static func spokenMorningCheck(_ run: PlannedRun) -> String {
        "How do your legs feel before \(spokenRun(run))?"
    }

    /// "Got it. Enjoy the run: Thursday’s Easy 40 min at 6:00 PM."
    static func spokenCheckedIn(_ check: MorningCheck, run: PlannedRun) -> String {
        "\(checkedIn(check).trimmingCharacters(in: ["."])): \(spokenRun(run))."
    }

    // MARK: Notifications (design decision 10)

    /// "Tomorrow’s 18 km is a big jump from your longest run (13 km). Make it 12?"
    static func spikeNote(_ run: PlannedRun, _ flag: GuardrailFlag, now: Date,
                          calendar: Calendar = .current) -> (title: String, body: String) {
        let day = dayPossessive(run.start, now: now, calendar: calendar).capitalized(with: nil)
        let body: String = switch flag.kind {
        case .spike:
            "\(day) \(flag.planned.label) is a big jump from your longest run (\(flag.longest30?.label ?? "this month")). Make it \(Self.number(flag.suggested))?"
        case .body:
            // Readings stay off the Lock Screen: only which ones are off.
            "Your \(flag.body.map(bodyReadingNames) ?? "morning readings") are off your usual this morning. "
                + (flag.keepEasy ? "Run \(flag.planned.label) easy?" : "Make it \(Self.number(flag.suggested))?")
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
