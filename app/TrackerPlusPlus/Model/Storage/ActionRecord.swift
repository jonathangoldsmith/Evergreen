import Foundation
import SwiftData

/// An applied action: the agent's, or the person's own "Pick another time".
/// This is the event log the feed shows.
@Model
final class ActionRecord {
    var actionId: String
    /// Order applied. The feed and the plan replay go by this, since two actions
    /// from one tick share a timestamp.
    var sequence: Int
    var kind: String
    var title: String?
    var planItemId: String?
    var before: Slot?
    var after: Slot?
    var reason: String
    var points: Int?
    var createdAt: Date
    /// Undone actions stay in the feed and are sent so the agent won't redo them.
    var undone: Bool
    var run: Run?

    init(_ action: AgentAction, sequence: Int) {
        actionId = action.id
        self.sequence = sequence
        kind = action.kind.rawValue
        title = action.title
        planItemId = action.planItemId
        before = action.before
        after = action.after
        reason = action.reason
        points = action.points
        createdAt = action.createdAt
        undone = false
    }

    var action: AgentAction {
        AgentAction(id: actionId, kind: AgentAction.Kind(rawValue: kind) ?? .note, title: title,
                    planItemId: planItemId, before: before, after: after, reason: reason,
                    points: points, createdAt: createdAt)
    }
}
