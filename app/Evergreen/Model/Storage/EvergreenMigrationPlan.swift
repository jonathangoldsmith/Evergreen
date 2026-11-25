import Foundation
import SwiftData

/// Every schema the app has shipped, oldest first, and how to move between them.
enum EvergreenMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [EvergreenSchemaV1.self, EvergreenSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: EvergreenSchemaV1.self, toVersion: EvergreenSchemaV2.self)]
    }
}
