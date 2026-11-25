import Foundation
import SwiftData

/// Adds what outlives the story day for a real person (eng review D4):
/// guardrail decisions, morning checks, pain answers, the profile and the
/// upload outbox.
enum EvergreenSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        EvergreenSchemaV1.models + [GuardrailDecision.self, CheckInRecord.self, PainRecord.self, Profile.self,
                                     OutboxEvent.self]
    }
}
