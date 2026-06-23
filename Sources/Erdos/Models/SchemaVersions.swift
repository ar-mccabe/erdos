import SwiftData

/// Version 1 of the Erdos store schema — a retroactive baseline that matches
/// the models exactly as originally shipped (via an unversioned `Schema`).
///
/// Establishing a versioned baseline now is what makes future schema changes
/// survivable: a later version becomes `ErdosSchemaV2` plus a `MigrationStage`,
/// instead of an incompatible store that fails to open. Because V1's entities
/// are unchanged, SwiftData opens the existing store as V1 with no migration.
enum ErdosSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Experiment.self,
            Note.self,
            Artifact.self,
            ClaudeSession.self,
            TimelineEvent.self,
            TaskUpdate.self,
        ]
    }
}

/// Ordered list of schema versions and the migration stages between them.
/// Append new versions and stages here as the model evolves.
enum ErdosMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ErdosSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []  // V1 baseline; no migrations yet.
    }
}
