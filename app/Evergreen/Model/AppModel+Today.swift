import Foundation

extension AppModel {
    /// The move or shrink still in effect that last changed this workout, for
    /// the "Moved" badge on its row.
    func movedAction(for item: PlanItem) -> AgentAction? {
        appliedActions.last {
            $0.planItemId == item.id && ($0.kind == .move || $0.kind == .shrink) && !isUndone($0)
        }
    }

    /// How many workouts are on the plan: "three".
    var planCountWord: String { Self.word(plan.count) }

    /// "three" for 3; numerals past ten.
    static func word(_ number: Int) -> String {
        guard (0...10).contains(number) else { return "\(number)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }
}
