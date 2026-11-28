import Foundation

/// Every Amplitude event the brake sends (plan item 9). Properties are fixed
/// words, never a distance, a soreness answer, a pain answer or an injury, so
/// a new event can't leak a health value (task T7 tests this list).
enum AnalyticsEvent: Hashable, Sendable {
    case flagShown(GuardrailFlag.Kind)
    case choice(String)
    case painCheckIn(answered: Bool)
    case backtestCompleted(answered: Int)
    case rangeReportViewed
    /// The push (range plan item 16): no durations or health values.
    case comebackBooked
    case comebackDone
    /// paired or unpaired (item 9's list).
    case buddy(String)
    /// check_in or swap, never the answer (item 9's list).
    case watchAction(String)

    var name: String {
        switch self {
        case .flagShown: "guardrail_flag_shown"
        case .choice: "guardrail_choice"
        case .painCheckIn: "pain_checkin"
        case .backtestCompleted: "backtest_completed"
        case .rangeReportViewed: "range_report_viewed"
        case .comebackBooked: "comeback_booked"
        case .comebackDone: "comeback_done"
        case .buddy: "buddy"
        case .watchAction: "watch_action"
        }
    }

    /// The one word a flag kind sends: never the readings or the answer.
    private static func word(for kind: GuardrailFlag.Kind) -> String {
        switch kind {
        case .spike, .returnSpike: "spike"
        case .body: "body"
        case .load: "load"
        case .sore, .tired: "check_in"
        }
    }

    var properties: [String: String] {
        switch self {
        case .flagShown(let kind):
            // Sore and Tired come from the morning check; only that it was a check-in leaves the phone.
            // The body signal sends that it was one, never the readings.
            ["kind": Self.word(for: kind)]
        case .choice(let choice):
            ["choice": ["accept", "keep", "undo"].contains(choice) ? choice : "other"]
        case .painCheckIn(let answered):
            ["answered": answered ? "true" : "false"]
        case .backtestCompleted(let answered):
            ["answered": String(answered)]
        case .watchAction(let kind):
            ["kind": kind == "swap" ? "swap" : "check_in"]
        case .buddy(let action):
            ["action": action == "paired" ? "paired" : "unpaired"]
        case .rangeReportViewed, .comebackBooked, .comebackDone:
            [:]
        }
    }
}
