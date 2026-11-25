import Foundation

/// One guardrail notification to schedule (plan item 7, design decision 10).
struct GuardrailNote: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        /// The evening (or morning) note that a run is a big jump: "Make it 12?"
        case swap
        /// "How do your legs feel?" Fresh / Tired / Sore.
        case morningCheck
        /// Sunday 6 PM: "How was your week? Any pain?" No / A little / Yes. Never dropped.
        case pain
    }

    var kind: Kind
    var fireAt: Date
    var title: String
    var body: String
    /// The run it's about (swap and morning check).
    var run: PlannedRun?
    var flag: GuardrailFlag?
    /// The pain week's Monday.
    var weekStart: Date?

    /// Stable, so rescheduling replaces rather than duplicates.
    var id: String {
        switch kind {
        case .swap, .morningCheck: "guardrail-\(kind.rawValue)-\(StableHash.hex(run?.key ?? "", length: 12))"
        case .pain: "guardrail-pain-\(Int((weekStart ?? fireAt).timeIntervalSince1970))"
        }
    }
}
