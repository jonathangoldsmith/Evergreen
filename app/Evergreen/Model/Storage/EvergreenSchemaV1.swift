import Foundation
import SwiftData

/// The store as it shipped before the range plan: the demo run only.
///
/// These reference the live model classes, which is safe while a change is
/// additive (new models, new properties with defaults). Before changing or
/// removing a stored property on Run, ActionRecord or LoggedWorkout, freeze
/// copies of today's classes inside this enum so V1 keeps describing the old
/// file (eng review D5).
enum EvergreenSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Run.self, ActionRecord.self, LoggedWorkout.self] }
}
