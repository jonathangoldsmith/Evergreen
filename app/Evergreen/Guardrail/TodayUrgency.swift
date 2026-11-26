import Foundation

/// The one urgency order, most urgent first (design decisions 1, 10 and 13;
/// eng re-run Section 1 #1 and Section 2 #1). Today's cards, the notification
/// budget and the watch all sort by it, so none of them decides it alone.
enum TodayUrgency: Int, Comparable, CaseIterable, Sendable {
    /// A run that's a big jump: "Make it 12 km?"
    case swap
    /// "How do your legs feel?" before a run.
    case morningCheck
    /// Sunday's "Any pain?"
    case pain
    /// The return-plan offer, or the plan in progress.
    case returnPlan
    /// The agent asks before buying.
    case ask
    /// Something already done, while its Undo is live.
    case undoable
    /// Information: an answer's confirmation, or a note from the agent.
    case note

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
