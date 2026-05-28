package com.rocketflow.companion.planning

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlanningLocalStoreMigrationUnitTest {
    private lateinit var context: Context
    private var store: PlanningLocalStore? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
    }

    @After
    fun tearDown() {
        store?.close()
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun upgradeFromV13IdeaSchemaAddsPendingBlockedWithDefaultAndMatchesFreshSchema() {
        createV13DatabaseWithIdeaMissingPendingBlocked()

        store = PlanningLocalStore(context)
        val upgradedColumns = ideaColumns(store!!.writableDatabase)
        val upgradedPendingBlocked = upgradedColumns["pending_blocked"]

        assertNotNull(upgradedPendingBlocked)
        assertEquals("INTEGER", upgradedPendingBlocked!!.type)
        assertEquals(1, upgradedPendingBlocked.notNull)
        assertEquals("0", upgradedPendingBlocked.defaultValue)
        assertEquals(0, ideaPendingBlockedValue(store!!.readableDatabase, "user-1", "idea-legacy"))

        store!!.close()
        store = null
        context.deleteDatabase(DATABASE_NAME)

        store = PlanningLocalStore(context)
        val freshColumns = ideaColumns(store!!.writableDatabase)

        assertEquals(freshColumns, upgradedColumns)
    }

    @Test
    fun insertReplaceRemoteIdeaDoesNotThrowAfterUpgradeFromMissingPendingBlockedColumn() {
        createV13DatabaseWithIdeaMissingPendingBlocked()
        store = PlanningLocalStore(context)

        store!!.upsertRemoteIdeas("user-1", listOf(remoteIdea("idea-remote")))

        assertEquals("Remote idea", store!!.findIdea("user-1", "idea-remote")!!.title)
        assertEquals(0, ideaPendingBlockedValue(store!!.readableDatabase, "user-1", "idea-remote"))
    }

    @Test
    fun resetPendingCreateIdeaClearsBlockedIssue() {
        store = PlanningLocalStore(context)
        insertPendingCreateIdea(store!!.writableDatabase, "user-1", "idea-pending")

        val blockedSnapshot = store!!.snapshot("user-1", offline = false, lastSyncError = null)
        val issue = blockedSnapshot.pendingIssues.single()
        assertEquals(1, blockedSnapshot.pendingCount)
        assertEquals(PlanningLocalStore.TABLE_IDEAS, issue.entityType)
        assertTrue(issue.blocked)

        store!!.resetPendingIssue("user-1", issue)

        val resetSnapshot = store!!.snapshot("user-1", offline = false, lastSyncError = null)
        assertEquals(0, resetSnapshot.pendingCount)
        assertTrue(resetSnapshot.pendingIssues.isEmpty())
        assertEquals(null, store!!.findIdea("user-1", "idea-pending"))
    }

    private fun createV13DatabaseWithIdeaMissingPendingBlocked() {
        context.openOrCreateDatabase(DATABASE_NAME, Context.MODE_PRIVATE, null).use { db ->
            db.execSQL(
                """
                CREATE TABLE ideas (
                    user_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active',
                    display_order INTEGER NOT NULL DEFAULT 0,
                    archived INTEGER NOT NULL,
                    shared INTEGER NOT NULL,
                    full_access INTEGER NOT NULL DEFAULT 0,
                    allow_author_note_edits INTEGER NOT NULL DEFAULT 0,
                    creator_user_id TEXT,
                    creator_email TEXT,
                    creator_name TEXT,
                    version INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    pending_action TEXT,
                    last_error TEXT,
                    locally_deleted INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO ideas (
                    user_id, id, folder_id, title, body, status, display_order, archived, shared,
                    full_access, allow_author_note_edits, version, created_at, updated_at,
                    pending_action, last_error, locally_deleted
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "user-1",
                    "idea-legacy",
                    "folder-1",
                    "Legacy idea",
                    "",
                    "active",
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    "2026-05-29T00:00:00Z",
                    "2026-05-29T00:00:00Z",
                    null,
                    null,
                    0
                )
            )
            db.version = 13
        }
    }

    private fun insertPendingCreateIdea(db: SQLiteDatabase, userId: String, ideaId: String) {
        db.execSQL(
            """
            INSERT INTO ideas (
                user_id, id, folder_id, title, body, status, display_order, archived, shared,
                full_access, allow_author_note_edits, version, created_at, updated_at,
                pending_action, pending_blocked, last_error, locally_deleted
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(
                userId,
                ideaId,
                "missing-folder",
                "Blocked idea",
                "",
                "active",
                0,
                0,
                0,
                0,
                0,
                0,
                "2026-05-29T00:00:00Z",
                "2026-05-29T00:00:00Z",
                "create",
                1,
                "POST /folders/missing-folder/ideas - HTTP 404 - not_found - Folder was not found.",
                0
            )
        )
    }

    private fun remoteIdea(id: String): PlanningIdea {
        return PlanningIdea(
            id = id,
            folderId = "folder-1",
            title = "Remote idea",
            body = "",
            status = "active",
            displayOrder = 0,
            archived = false,
            shared = false,
            fullAccess = true,
            allowAuthorNoteEdits = false,
            creatorUserId = "user-1",
            creatorEmail = null,
            creatorName = null,
            version = 1,
            createdAt = "2026-05-29T00:00:00Z",
            updatedAt = "2026-05-29T00:00:00Z",
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun ideaPendingBlockedValue(db: SQLiteDatabase, userId: String, ideaId: String): Int {
        return db.rawQuery(
            "SELECT pending_blocked FROM ideas WHERE user_id = ? AND id = ?",
            arrayOf(userId, ideaId)
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            cursor.getInt(0)
        }
    }

    private fun ideaColumns(db: SQLiteDatabase): Map<String, ColumnInfo> {
        return db.rawQuery("PRAGMA table_info(${PlanningLocalStore.TABLE_IDEAS})", emptyArray()).use { cursor ->
            buildMap {
                while (cursor.moveToNext()) {
                    val name = cursor.getString(cursor.getColumnIndexOrThrow("name"))
                    put(
                        name,
                        ColumnInfo(
                            type = cursor.getString(cursor.getColumnIndexOrThrow("type")),
                            notNull = cursor.getInt(cursor.getColumnIndexOrThrow("notnull")),
                            defaultValue = cursor.getString(cursor.getColumnIndexOrThrow("dflt_value")),
                            pk = cursor.getInt(cursor.getColumnIndexOrThrow("pk"))
                        )
                    )
                }
            }
        }
    }

    private data class ColumnInfo(
        val type: String,
        val notNull: Int,
        val defaultValue: String?,
        val pk: Int
    )

    private companion object {
        const val DATABASE_NAME = "rocketflow_planning.db"
    }
}
