package com.rocketflow.companion.focus

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.rocketflow.companion.calendar.CalendarMonth
import com.rocketflow.companion.planning.PlanningLocalStore
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.LocalDate

@RunWith(RobolectricTestRunner::class)
class FocusLocalDataSourceUnitTest {
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
    fun upgradeFromV15PreservesPlanningDataAndMatchesFreshV16Schema() {
        createRepresentativeV15Database()

        store = PlanningLocalStore(context)
        val db = store!!.writableDatabase

        listOf(
            PlanningLocalStore.TABLE_FOCUS_PERIODS,
            PlanningLocalStore.TABLE_FOCUS_ITEMS,
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            PlanningLocalStore.TABLE_FOCUS_NOTIFICATION_SETTINGS,
            PlanningLocalStore.TABLE_CALENDAR_MARKERS,
            PlanningLocalStore.TABLE_CALENDAR_CACHE_RANGES
        ).forEach { assertTrue("Missing $it", tableExists(db, it)) }
        assertTrue(columnExists(db, PlanningLocalStore.TABLE_FOCUS_NOTIFICATION_SETTINGS, "version"))
        assertTrue(columnExists(db, PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS, "conflict_attempts"))
        assertTrue(columnExists(db, PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS, "terminal"))
        assertEquals(16, db.version)
        db.rawQuery("SELECT name, pending_action, pending_blocked FROM folders WHERE user_id = ? AND id = ?", arrayOf("user-1", "folder-1")).use {
            assertTrue(it.moveToFirst())
            assertEquals("Existing folder", it.getString(0))
            assertEquals("update", it.getString(1))
            assertEquals(1, it.getInt(2))
        }
        db.rawQuery("SELECT name FROM goals WHERE user_id = ? AND id = ?", arrayOf("user-1", "goal-1")).use {
            assertTrue(it.moveToFirst())
            assertEquals("Existing goal", it.getString(0))
        }
        db.rawQuery("SELECT title, effort, pending_action FROM tasks WHERE user_id = ? AND id = ?", arrayOf("user-1", "task-1")).use {
            assertTrue(it.moveToFirst())
            assertEquals("Existing task", it.getString(0))
            assertEquals(3, it.getInt(1))
            assertEquals("update", it.getString(2))
        }
        val upgradedSchema = focusSchema(db)

        store!!.close()
        store = null
        context.deleteDatabase(DATABASE_NAME)
        store = PlanningLocalStore(context)
        val freshSchema = focusSchema(store!!.writableDatabase)

        assertEquals(freshSchema, upgradedSchema)
    }

    @Test
    fun offlineQueueAndCachedFocusSurviveReload() {
        store = PlanningLocalStore(context)
        val local = FocusLocalDataSource(store!!)
        val period = FocusPeriod(
            id = "period-1",
            weekStart = "2026-08-03",
            weekEndExclusive = "2026-08-10",
            timezone = "Europe/Moscow",
            status = "active",
            version = 3,
            items = listOf(FocusItem("task-1", "Task", "todo", 0, "Folder / Goal", 0))
        )
        local.savePeriod("user-1", period)
        local.enqueue("user-1", FocusPendingAction("mutation-1", "add", "task-1", period.id, 3, JSONObject().toString()))

        assertEquals(period, local.loadCurrent("user-1"))
        assertEquals(1, local.pendingCount("user-1"))
        assertEquals("mutation-1", local.pending("user-1").single().id)
    }

    @Test
    fun emptyCalendarResponseIsStillAvailableOffline() {
        store = PlanningLocalStore(context)
        val local = FocusLocalDataSource(store!!)
        val from = LocalDate.parse("2026-08-01")
        val to = from.plusDays(42)
        local.saveCalendar("user-1", CalendarMonth("Europe/Moscow", from, to, emptyList()))

        val cached = local.loadCalendar("user-1", from, to)

        assertNotNull(cached)
        assertTrue(cached!!.offline)
        assertTrue(cached.markers.isEmpty())
        assertEquals("Europe/Moscow", cached.timezone)
    }

    @Test
    fun historySummaryKeepsServerProgressWithoutLoadedItems() {
        store = PlanningLocalStore(context)
        val local = FocusLocalDataSource(store!!)
        local.saveHistorySummary(
            "user-1",
            FocusHistorySummary(
                id = "history-1",
                weekStart = "2026-07-27",
                weekEndExclusive = "2026-08-03",
                timezone = "Europe/Moscow",
                status = "completed",
                version = 4,
                progress = FocusProgress(completedWeight = 7, totalWeight = 10)
            )
        )

        val summary = local.loadHistorySummaries("user-1").single()

        assertEquals(70, summary.progress.percent)
        assertEquals(7, summary.progress.completedWeight)
        assertEquals(10, summary.progress.totalWeight)
    }

    @Test
    fun notificationSettingsCachePreservesServerVersion() {
        store = PlanningLocalStore(context)
        val local = FocusLocalDataSource(store!!)
        val settings = FocusNotificationSettings(240, "23:15", "06:45", version = 17)

        local.saveSettings("user-1", settings)

        assertEquals(settings, local.loadSettings("user-1"))
    }

    private fun tableExists(db: android.database.sqlite.SQLiteDatabase, table: String): Boolean =
        db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", arrayOf(table))
            .use { it.moveToFirst() }

    private fun columnExists(db: android.database.sqlite.SQLiteDatabase, table: String, column: String): Boolean =
        db.rawQuery("PRAGMA table_info($table)", emptyArray()).use { cursor ->
            generateSequence { if (cursor.moveToNext()) cursor.getString(1) else null }.any { it == column }
        }

    private fun createRepresentativeV15Database() {
        context.openOrCreateDatabase(DATABASE_NAME, Context.MODE_PRIVATE, null).use { db ->
            db.execSQL(
                """
                CREATE TABLE folders (
                    user_id TEXT NOT NULL, id TEXT NOT NULL, parent_folder_id TEXT, name TEXT NOT NULL,
                    description TEXT NOT NULL, display_order INTEGER NOT NULL, archived INTEGER NOT NULL,
                    shared INTEGER NOT NULL DEFAULT 0, full_access INTEGER NOT NULL DEFAULT 0,
                    version INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    pending_action TEXT, pending_blocked INTEGER NOT NULL DEFAULT 0, last_error TEXT,
                    locally_deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE goals (
                    user_id TEXT NOT NULL, id TEXT NOT NULL, folder_id TEXT NOT NULL, name TEXT NOT NULL,
                    description TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'todo', archived INTEGER NOT NULL,
                    shared INTEGER NOT NULL, can_create_tasks INTEGER NOT NULL DEFAULT 0,
                    full_access INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL, created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL, pending_action TEXT, pending_blocked INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT, locally_deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE tasks (
                    user_id TEXT NOT NULL, id TEXT NOT NULL, goal_id TEXT NOT NULL, title TEXT NOT NULL,
                    description TEXT NOT NULL, type TEXT NOT NULL, priority INTEGER NOT NULL,
                    effort INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, planned_time TEXT, due_time TEXT,
                    archived INTEGER NOT NULL, shared INTEGER NOT NULL, full_access INTEGER NOT NULL DEFAULT 0,
                    creator_user_id TEXT, creator_email TEXT, creator_name TEXT, version INTEGER NOT NULL,
                    tag_ids_json TEXT NOT NULL DEFAULT '[]', recurrence_json TEXT, reminders_json TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, pending_action TEXT,
                    pending_blocked INTEGER NOT NULL DEFAULT 0, last_error TEXT,
                    locally_deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            val now = "2026-08-01T00:00:00Z"
            db.execSQL(
                "INSERT INTO folders VALUES (?, ?, NULL, ?, '', 0, 0, 0, 0, 1, ?, ?, 'update', 1, 'offline', 0)",
                arrayOf("user-1", "folder-1", "Existing folder", now, now)
            )
            db.execSQL(
                "INSERT INTO goals VALUES (?, ?, ?, ?, '', 'todo', 0, 0, 0, 0, 1, ?, ?, NULL, 0, NULL, 0)",
                arrayOf("user-1", "goal-1", "folder-1", "Existing goal", now, now)
            )
            db.execSQL(
                "INSERT INTO tasks VALUES (?, ?, ?, ?, '', 'green', 1, 3, 'todo', NULL, NULL, 0, 0, 0, NULL, NULL, NULL, 2, '[]', NULL, NULL, ?, ?, 'update', 0, NULL, 0)",
                arrayOf("user-1", "task-1", "goal-1", "Existing task", now, now)
            )
            db.version = 15
        }
    }

    private fun focusSchema(db: android.database.sqlite.SQLiteDatabase): Map<String, String> {
        val names = setOf(
            "focus_periods",
            "focus_items",
            "focus_pending_actions",
            "focus_notification_settings",
            "calendar_markers",
            "calendar_cache_ranges",
            "idx_focus_period_user_week",
            "idx_focus_pending_user_created",
            "idx_calendar_user_date"
        )
        return db.rawQuery("SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name", emptyArray()).use { cursor ->
            buildMap {
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0)
                    if (name in names) put(name, cursor.getString(1).replace(Regex("\\s+"), " ").trim())
                }
            }
        }.also { schema -> names.forEach { assertNotNull("Missing schema for $it", schema[it]) } }
    }

    companion object {
        private const val DATABASE_NAME = "rocketflow_planning.db"
    }
}
