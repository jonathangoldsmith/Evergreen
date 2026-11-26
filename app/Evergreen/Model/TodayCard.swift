import Foundation

/// One card on Today (design decisions 1, 13 and 14). Only things that need
/// an answer, or an action whose Undo is live, are cards; the rest are rows.
enum TodayCard: Hashable, Identifiable {
    /// A run on a training calendar: its swap, morning check, or the choice with Undo.
    case run(PlannedRun)
    /// The week's pain check-in, or its thanks once answered.
    case pain(Date)
    /// The return-plan offer or the plan in progress.
    case returnPlan
    /// The agent's latest action while its Undo is live, a purchase, or a note.
    case action(AgentAction)

    var id: String {
        switch self {
        case .run(let run): "run-\(run.key)"
        case .pain(let week): "pain-\(week.timeIntervalSince1970)"
        case .returnPlan: "return"
        case .action(let action): "action-\(action.id)"
        }
    }

    /// A card with its place in the order: urgency first, then the sooner one.
    struct Ranked: Hashable {
        let card: TodayCard
        let urgency: TodayUrgency
        let at: Date
    }

    /// The order, in one place (eng re-run Section 1 #1): views never decide it.
    static func ordered(_ cards: [Ranked]) -> [TodayCard] {
        cards.sorted { ($0.urgency, $0.at) < ($1.urgency, $1.at) }.map(\.card)
    }
}
