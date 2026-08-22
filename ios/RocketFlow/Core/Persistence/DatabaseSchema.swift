import Foundation
import GRDB

enum DatabaseSchema {
    static var migrator: DatabaseMigrator {
        makeMigrator(includeFeaturePersistence: true)
    }

    static var preFeaturePersistenceMigrator: DatabaseMigrator {
        makeMigrator(includeFeaturePersistence: false)
    }

    private static func makeMigrator(includeFeaturePersistence: Bool) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createPlanningTables(in: db)
            try createCollaborationAndCacheTables(in: db)
            try createSyncTables(in: db)
        }
        migrator.registerMigration("v2-entity-order") { db in
            try createEntityOrderTable(in: db)
        }
        migrator.registerMigration("v3-conflict-server-deleted") { db in
            try db.alter(table: "sync_conflicts") { table in
                table.add(column: "serverDeleted", .boolean).notNull().defaults(to: false)
            }
        }
        if includeFeaturePersistence {
            migrator.registerMigration("v4-feature-persistence") { db in
                try createFeaturePersistenceTables(in: db)
            }
        }
        return migrator
    }

    private static func createFeaturePersistenceTables(in db: Database) throws {
        try db.create(table: "feature_account_leases") { table in
            table.column("accountID", .text).primaryKey()
            table.column("generation", .integer).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_accounts") { table in
            table.column("accountID", .text).primaryKey()
            table.column("generation", .integer).notNull()
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_calendar_ranges") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("timezoneID", .text).notNull()
            table.column("fromDate", .text).notNull()
            table.column("toExclusive", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
            table.primaryKey(["accountID", "timezoneID", "fromDate", "toExclusive"])
        }

        try db.create(table: "feature_focus_snapshots") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("cacheKind", .text).notNull()
            table.column("entityID", .text).notNull().defaults(to: "")
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
            table.primaryKey(["accountID", "cacheKind", "entityID"])
        }

        try db.create(table: "feature_focus_actions") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("actionID", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("expectedVersion", .integer).notNull()
            table.column("conflictAttempts", .integer).notNull().defaults(to: 0)
            table.column("retryCount", .integer).notNull().defaults(to: 0)
            table.column("nextRetryAt", .text)
            table.column("lastErrorCode", .text)
            table.column("sequence", .integer).notNull()
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.primaryKey(["accountID", "actionID"])
            table.uniqueKey(["accountID", "sequence"])
        }
        try db.create(
            index: "feature_focus_actions_fifo",
            on: "feature_focus_actions",
            columns: ["accountID", "sequence", "createdAt", "actionID"]
        )

        try db.create(table: "feature_focus_terminal_issues") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("issueID", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("createdAt", .text).notNull()
            table.primaryKey(["accountID", "issueID"])
        }

        try db.create(table: "feature_task_reminders") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("taskID", .text).notNull()
            table.column("reminderID", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("taskState", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.primaryKey(["accountID", "taskID", "reminderID"])
        }

        try db.create(table: "feature_default_reminders") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_reminder_reconciliation") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("reason", .text).notNull()
            table.column("reconciledAt", .text).notNull()
        }

        try db.create(table: "feature_remote_notification_events") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("eventID", .text).notNull()
            table.column("seenAt", .text).notNull()
            table.primaryKey(["accountID", "eventID"])
        }
        try db.create(
            index: "feature_remote_notification_events_expiry",
            on: "feature_remote_notification_events",
            columns: ["accountID", "seenAt"]
        )

        try db.create(table: "feature_settings_snapshots") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(table: "feature_settings_pending") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_device_registration_state") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("fcmToken", .text).notNull()
            table.column("installationID", .text).notNull()
            table.column("deviceName", .text)
            table.column("registrationID", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_installation_identity") { table in
            table.column("accountID", .text).primaryKey()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("installationID", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "feature_persistence_corruptions") { table in
            table.column("accountID", .text).notNull()
                .references("feature_accounts", column: "accountID", onDelete: .cascade)
            table.column("tableName", .text).notNull()
            table.column("recordKey", .text).notNull()
            table.column("code", .text).notNull()
            table.column("detectedAt", .text).notNull()
            table.primaryKey(["accountID", "tableName", "recordKey"])
        }
    }

    private static func createPlanningTables(in db: Database) throws {
        try db.create(table: "folders") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("parentID", .text)
                .references("folders", column: "id", onDelete: .cascade)
            table.column("name", .text).notNull()
            table.column("details", .text).notNull().defaults(to: "")
            table.column("displayOrder", .integer).notNull().defaults(to: 0)
            table.column("archived", .boolean).notNull().defaults(to: false)
            table.column("shared", .boolean).notNull().defaults(to: false)
            table.column("fullAccess", .boolean).notNull().defaults(to: true)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "folders_parent_order", on: "folders", columns: ["parentID", "createdAt", "id"])

        try db.create(table: "goals") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("folderID", .text).notNull()
                .references("folders", column: "id", onDelete: .cascade)
            table.column("name", .text).notNull()
            table.column("details", .text).notNull().defaults(to: "")
            table.column("status", .text).notNull()
            table.column("archived", .boolean).notNull().defaults(to: false)
            table.column("shared", .boolean).notNull().defaults(to: false)
            table.column("fullAccess", .boolean).notNull().defaults(to: true)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "goals_folder_order", on: "goals", columns: ["folderID", "createdAt", "id"])

        try db.create(table: "tasks") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("goalID", .text).notNull()
                .references("goals", column: "id", onDelete: .cascade)
            table.column("title", .text).notNull()
            table.column("details", .text).notNull().defaults(to: "")
            table.column("type", .text).notNull()
            table.column("priorityShadow", .integer).notNull().defaults(to: TaskPriorityCompatibility.defaultShadow)
            table.column("effort", .integer).notNull().defaults(to: 0)
            table.column("status", .text).notNull()
            table.column("plannedTime", .text)
            table.column("dueTime", .text)
            table.column("archived", .boolean).notNull().defaults(to: false)
            table.column("shared", .boolean).notNull().defaults(to: false)
            table.column("fullAccess", .boolean).notNull().defaults(to: true)
            table.column("creatorUserID", .text)
            table.column("creatorEmail", .text)
            table.column("creatorName", .text)
            table.column("recurrenceJSON", .blob)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "tasks_goal_due_order", on: "tasks", columns: ["goalID", "dueTime", "createdAt", "id"])

        try db.create(table: "checklist_items") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("taskID", .text).notNull()
                .references("tasks", column: "id", onDelete: .cascade)
            table.column("text", .text).notNull()
            table.column("checked", .boolean).notNull().defaults(to: false)
            table.column("displayOrder", .integer).notNull().defaults(to: 0)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(index: "checklist_task_order", on: "checklist_items", columns: ["taskID", "displayOrder", "createdAt", "id"])

        try db.create(table: "tags") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("name", .text).notNull()
            table.column("color", .text)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "tags_name_id", on: "tags", columns: ["name", "id"])

        try db.create(table: "task_tags") { table in
            table.column("taskID", .text).notNull()
                .references("tasks", column: "id", onDelete: .cascade)
            table.column("tagID", .text).notNull()
                .references("tags", column: "id", onDelete: .cascade)
            table.primaryKey(["taskID", "tagID"])
        }

        try db.create(table: "ideas") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("folderID", .text).notNull()
                .references("folders", column: "id", onDelete: .cascade)
            table.column("title", .text).notNull()
            table.column("body", .text).notNull().defaults(to: "")
            table.column("status", .text).notNull()
            table.column("displayOrder", .integer).notNull().defaults(to: 0)
            table.column("archived", .boolean).notNull().defaults(to: false)
            table.column("allowAuthorNoteEdits", .boolean).notNull().defaults(to: false)
            table.column("shared", .boolean).notNull().defaults(to: false)
            table.column("fullAccess", .boolean).notNull().defaults(to: true)
            table.column("creatorUserID", .text)
            table.column("creatorEmail", .text)
            table.column("creatorName", .text)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "ideas_folder_order", on: "ideas", columns: ["folderID", "createdAt", "id"])

        try db.create(table: "idea_notes") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("ideaID", .text).notNull()
                .references("ideas", column: "id", onDelete: .cascade)
            table.column("eventType", .text).notNull()
            table.column("body", .text).notNull().defaults(to: "")
            table.column("metadataJSON", .blob).notNull()
            table.column("authorUserID", .text)
            table.column("authorEmail", .text)
            table.column("authorName", .text)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(index: "idea_notes_idea_order", on: "idea_notes", columns: ["ideaID", "createdAt", "id"])

        try db.create(table: "notes") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("folderID", .text).notNull()
                .references("folders", column: "id", onDelete: .cascade)
            table.column("title", .text).notNull()
            table.column("body", .text).notNull().defaults(to: "")
            table.column("displayOrder", .integer).notNull().defaults(to: 0)
            table.column("archived", .boolean).notNull().defaults(to: false)
            table.column("shared", .boolean).notNull().defaults(to: false)
            table.column("fullAccess", .boolean).notNull().defaults(to: true)
            table.column("authorUserID", .text)
            table.column("authorEmail", .text)
            table.column("authorName", .text)
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "notes_folder_order", on: "notes", columns: ["folderID", "createdAt", "id"])
    }

    private static func createCollaborationAndCacheTables(in db: Database) throws {
        try db.create(table: "entity_links") { table in
            table.column("id", .text).primaryKey()
            table.column("remoteID", .text).unique()
            table.column("sourceType", .text).notNull()
            table.column("sourceID", .text).notNull()
            table.column("targetType", .text).notNull()
            table.column("targetID", .text).notNull()
            table.column("relationType", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("syncState", .text).notNull().defaults(to: SyncState.synced.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
            table.column("deletedAt", .text)
        }
        try db.create(index: "entity_links_source", on: "entity_links", columns: ["sourceType", "sourceID"])
        try db.create(index: "entity_links_target", on: "entity_links", columns: ["targetType", "targetID"])

        try db.create(table: "collaboration_cache") { table in
            table.column("cacheKey", .text).primaryKey()
            table.column("payloadJSON", .blob).notNull()
            table.column("updatedAt", .text).notNull()
        }

        try db.create(table: "calendar_ranges") { table in
            table.column("rangeKey", .text).primaryKey()
            table.column("fromDate", .text).notNull()
            table.column("toExclusive", .text).notNull()
            table.column("timezone", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(table: "calendar_markers") { table in
            table.column("rangeKey", .text).notNull()
                .references("calendar_ranges", column: "rangeKey", onDelete: .cascade)
            table.column("markerID", .text).notNull()
            table.column("occurrenceID", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.primaryKey(["rangeKey", "markerID"])
        }
        try db.create(index: "calendar_occurrence", on: "calendar_markers", columns: ["occurrenceID"])

        try db.create(table: "settings_cache") { table in
            table.column("cacheKey", .text).primaryKey()
            table.column("payloadJSON", .blob).notNull()
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("updatedAt", .text).notNull()
        }
        try db.create(table: "focus_cache") { table in
            table.column("cacheKey", .text).primaryKey()
            table.column("payloadJSON", .blob).notNull()
            table.column("version", .integer).notNull().defaults(to: 0)
            table.column("updatedAt", .text).notNull()
        }

    }

    private static func createEntityOrderTable(in db: Database) throws {
        try db.create(table: "entity_order") { table in
            table.column("entityType", .text).notNull()
            table.column("entityID", .text).notNull()
            table.column("position", .integer).notNull()
            table.primaryKey(["entityType", "entityID"])
        }
        try db.create(index: "entity_order_position", on: "entity_order", columns: ["entityType", "position", "entityID"])
    }

    private static func createSyncTables(in db: Database) throws {
        try db.create(table: "pending_mutations") { table in
            table.column("id", .text).primaryKey()
            table.column("dedupeKey", .text).notNull().unique()
            table.column("entityType", .text).notNull()
            table.column("entityID", .text).notNull()
            table.column("operation", .text).notNull()
            table.column("payloadJSON", .blob).notNull()
            table.column("baseVersion", .integer)
            table.column("attemptCount", .integer).notNull().defaults(to: 0)
            table.column("nextRetryAt", .text)
            table.column("lastErrorCode", .text)
            table.column("state", .text).notNull().defaults(to: MutationState.queued.rawValue)
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(index: "pending_ready", on: "pending_mutations", columns: ["state", "nextRetryAt", "createdAt", "id"])

        try db.create(table: "pending_mutation_dependencies") { table in
            table.column("mutationID", .text).notNull()
                .references("pending_mutations", column: "id", onDelete: .cascade)
            table.column("entityID", .text).notNull()
            table.primaryKey(["mutationID", "entityID"])
        }
        try db.create(index: "pending_dependency_entity", on: "pending_mutation_dependencies", columns: ["entityID"])

        try db.create(table: "sync_conflicts") { table in
            table.column("id", .text).primaryKey()
            table.column("mutationID", .text).notNull().unique()
                .references("pending_mutations", column: "id", onDelete: .cascade)
            table.column("entityType", .text).notNull()
            table.column("entityID", .text).notNull()
            table.column("operation", .text).notNull()
            table.column("localPayloadJSON", .blob).notNull()
            table.column("serverPayloadJSON", .blob)
            table.column("baseVersion", .integer)
            table.column("serverVersion", .integer)
            table.column("errorCode", .text).notNull()
            table.column("createdAt", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
        try db.create(index: "sync_conflicts_entity", on: "sync_conflicts", columns: ["entityType", "entityID"])

        try db.create(table: "id_mappings") { table in
            table.column("entityType", .text).notNull()
            table.column("localID", .text).notNull()
            table.column("remoteID", .text).notNull()
            table.column("createdAt", .text).notNull()
            table.primaryKey(["entityType", "localID"])
            table.uniqueKey(["entityType", "remoteID"])
        }

        try db.create(table: "sync_metadata") { table in
            table.column("key", .text).primaryKey()
            table.column("value", .text).notNull()
            table.column("updatedAt", .text).notNull()
        }
    }
}
