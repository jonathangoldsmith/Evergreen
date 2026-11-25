import Foundation
import SwiftData

/// Adds the return-to-running plan's state (range plan item 21).
enum EvergreenSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { EvergreenSchemaV2.models + [ReturnPlanState.self] }
}
