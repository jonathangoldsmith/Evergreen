import Foundation

/// Today's state the phone sends the watch (range plan item 19). The rule runs
/// on the phone only; the watch shows this and sends answers back.
struct WatchState: Codable, Hashable, Sendable {
    /// The next run that needs something, if any.
    struct Run: Codable, Hashable, Sendable {
        var key: String
        /// "Sun · Long run 18 km at 8:00 AM"
        var line: String
        var start: Date
        /// The morning check is open for it.
        var asksCheck: Bool
        /// A swap question: "Make tomorrow's run 13 km?"
        var question: String?
        var acceptLabel: String?
        var keepLabel: String?
        /// Once decided: "Changed to 13 km" or "Kept 18 km."
        var decided: String?
    }

    var run: Run?
    /// "5/6" for the circular complication; "—" before any counted day.
    var inRange: String
    /// "5 of 6 days in range" for VoiceOver.
    var inRangeSpoken: String
    /// The rectangular complication's line: "Sun · 12 km (was 18)", "Rest day".
    var today: String
    /// Tomorrow's line, so the complication rolls over at midnight without the phone.
    var tomorrow: String? = nil
    var sentAt: Date

    static let empty = WatchState(run: nil, inRange: "—", inRangeSpoken: "No days counted yet",
                                  today: "Rest day", sentAt: .distantPast)

    static let contextKey = "state"

    func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.contextKey: data]
    }

    init(run: Run?, inRange: String, inRangeSpoken: String, today: String, tomorrow: String? = nil, sentAt: Date) {
        self.run = run
        self.inRange = inRange
        self.inRangeSpoken = inRangeSpoken
        self.today = today
        self.tomorrow = tomorrow
        self.sentAt = sentAt
    }

    init?(_ dictionary: [String: Any]) {
        guard let data = dictionary[Self.contextKey] as? Data,
              let state = try? JSONDecoder().decode(WatchState.self, from: data) else { return nil }
        self = state
    }
}
