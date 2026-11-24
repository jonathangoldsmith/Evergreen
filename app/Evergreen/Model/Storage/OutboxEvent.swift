import Foundation
import SwiftData

/// An event waiting to reach the harness (eng review D1). Removed only when
/// the harness returns its id as stored, so a quiet failure never loses it.
@Model
final class OutboxEvent {
    var eventId: String
    var data: Data
    var createdAt: Date

    init(eventId: String, data: Data, createdAt: Date) {
        self.eventId = eventId
        self.data = data
        self.createdAt = createdAt
    }
}
