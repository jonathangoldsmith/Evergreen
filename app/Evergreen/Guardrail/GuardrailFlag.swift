import Foundation

/// Why a planned run was flagged, and what Evergreen suggests instead
/// (plan items 5 and 6). One flag per run.
struct GuardrailFlag: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        /// More than 10% (5% after an injury) past the longest run in 30 days.
        case spike
        /// After an injury, with almost no recent runs: anything over 30 min or 5 km.
        case returnSpike
        case sore
        case tired
        /// No morning answer, and two of this morning's readings are off the
        /// person's usual (`BodySignal`): cut like Tired.
        case body
        /// Longer than today's range leaves room for (`TodayRange`): cut to fit.
        case load
    }

    var kind: Kind
    var planned: RunSize
    var suggested: RunSize
    /// The longest comparable run in the previous 30 days; nil for a return spike or no history.
    var longest30: RunSize?
    /// Sore or Tired where the cut would be under 10%: "Keep the distance, run it easy."
    var keepEasy: Bool
    /// After an injury in the last 12 months, the tighter rule applied.
    var injuryAdjusted: Bool
    /// For a body flag, the readings behind it, so the card can say which.
    var body: BodySignal? = nil

    /// How far past the 30-day longest the planned run is, in percent.
    var jumpPercent: Int? {
        guard let longest30, longest30.value > 0 else { return nil }
        return Int(((planned.value / longest30.value - 1) * 100).rounded())
    }
}
