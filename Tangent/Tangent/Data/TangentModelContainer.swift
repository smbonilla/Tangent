import Foundation
import SwiftData

enum TangentModelContainer {
    static let schema = Schema(TangentSchemaV3.models, version: TangentSchemaV3.versionIdentifier)

    static func make(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: TangentMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
