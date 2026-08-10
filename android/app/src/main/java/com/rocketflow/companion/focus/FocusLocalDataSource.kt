package com.rocketflow.companion.focus

import android.content.ContentValues
import com.rocketflow.companion.calendar.CalendarMarker
import com.rocketflow.companion.calendar.CalendarMarkerKind
import com.rocketflow.companion.calendar.CalendarMonth
import com.rocketflow.companion.planning.PlanningLocalStore
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

class FocusLocalDataSource(private val store: PlanningLocalStore) {

    fun savePeriod(userId: String, period: FocusPeriod) {
        val db = store.writableDatabase
        db.beginTransaction()
        try {
            db.insertWithOnConflict(
                PlanningLocalStore.TABLE_FOCUS_PERIODS,
                null,
                ContentValues().apply {
                    put("user_id", userId)
                    put("id", period.id)
                    put("week_start", period.weekStart)
                    put("week_end_exclusive", period.weekEndExclusive)
                    put("timezone", period.timezone)
                    put("status", period.status)
                    put("version", period.version)
                    put("completed_weight", period.progress.completedWeight)
                    put("total_weight", period.progress.totalWeight)
                    put("progress_percent", period.progress.percent)
                    put("rollover_json", period.rolloverOffer?.let(::rolloverJson))
                    put("updated_at", PlanningLocalStore.nowIso())
                },
                android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
            )
            db.delete(
                PlanningLocalStore.TABLE_FOCUS_ITEMS,
                "user_id = ? AND period_id = ?",
                arrayOf(userId, period.id)
            )
            period.items.forEach { item -> insertItem(userId, period.id, item) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun loadCurrent(userId: String): FocusPeriod? = loadPeriods(userId, "status = 'active'").maxByOrNull { it.weekStart }

    fun loadHistory(userId: String): List<FocusPeriod> = loadPeriods(userId, "status <> 'active'")
        .sortedByDescending { it.weekStart }

    fun saveHistorySummary(userId: String, summary: FocusHistorySummary) {
        store.writableDatabase.insertWithOnConflict(
            PlanningLocalStore.TABLE_FOCUS_PERIODS,
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("id", summary.id)
                put("week_start", summary.weekStart)
                put("week_end_exclusive", summary.weekEndExclusive)
                put("timezone", summary.timezone)
                put("status", summary.status)
                put("version", summary.version)
                put("completed_weight", summary.progress.completedWeight)
                put("total_weight", summary.progress.totalWeight)
                put("progress_percent", summary.progress.percent)
                putNull("rollover_json")
                put("updated_at", PlanningLocalStore.nowIso())
            },
            android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun loadHistorySummaries(userId: String): List<FocusHistorySummary> = store.readableDatabase.rawQuery(
        "SELECT id, week_start, week_end_exclusive, timezone, status, version, completed_weight, total_weight FROM ${PlanningLocalStore.TABLE_FOCUS_PERIODS} WHERE user_id = ? AND status <> 'active' ORDER BY week_start DESC",
        arrayOf(userId)
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(
                    FocusHistorySummary(
                        id = cursor.getString(0),
                        weekStart = cursor.getString(1),
                        weekEndExclusive = cursor.getString(2),
                        timezone = cursor.getString(3),
                        status = cursor.getString(4),
                        version = cursor.getLong(5),
                        progress = FocusProgress(cursor.getInt(6), cursor.getInt(7))
                    )
                )
            }
        }
    }

    fun loadPeriod(userId: String, periodId: String): FocusPeriod? =
        loadPeriods(userId, "id = ?", arrayOf(periodId)).firstOrNull()

    fun addLocalItem(userId: String, periodId: String, item: FocusItem) {
        insertItem(userId, periodId, item)
    }

    fun removeLocalItem(userId: String, periodId: String, taskId: String) {
        store.writableDatabase.delete(
            PlanningLocalStore.TABLE_FOCUS_ITEMS,
            "user_id = ? AND period_id = ? AND task_id = ?",
            arrayOf(userId, periodId, taskId)
        )
    }

    fun reorderLocalItems(userId: String, periodId: String, taskIds: List<String>) {
        val db = store.writableDatabase
        db.beginTransaction()
        try {
            taskIds.forEachIndexed { index, taskId ->
                db.update(
                    PlanningLocalStore.TABLE_FOCUS_ITEMS,
                    ContentValues().apply { put("display_order", index) },
                    "user_id = ? AND period_id = ? AND task_id = ?",
                    arrayOf(userId, periodId, taskId)
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun saveSettings(userId: String, settings: FocusNotificationSettings) {
        store.writableDatabase.insertWithOnConflict(
            PlanningLocalStore.TABLE_FOCUS_NOTIFICATION_SETTINGS,
            null,
            ContentValues().apply {
                put("user_id", userId)
                if (settings.intervalMinutes == null) putNull("interval_minutes") else put("interval_minutes", settings.intervalMinutes)
                put("quiet_start", settings.quietStart)
                put("quiet_end", settings.quietEnd)
                put("version", settings.version)
                put("updated_at", PlanningLocalStore.nowIso())
            },
            android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun loadSettings(userId: String): FocusNotificationSettings = store.readableDatabase.rawQuery(
        "SELECT interval_minutes, quiet_start, quiet_end, version FROM ${PlanningLocalStore.TABLE_FOCUS_NOTIFICATION_SETTINGS} WHERE user_id = ?",
        arrayOf(userId)
    ).use { cursor ->
        if (!cursor.moveToFirst()) return@use FocusNotificationSettings.DEFAULT
        FocusNotificationSettings(
            intervalMinutes = if (cursor.isNull(0)) null else cursor.getInt(0),
            quietStart = if (cursor.isNull(1)) null else cursor.getString(1),
            quietEnd = if (cursor.isNull(2)) null else cursor.getString(2),
            version = cursor.getLong(3)
        )
    }

    internal fun enqueue(userId: String, action: FocusPendingAction) {
        val db = store.writableDatabase
        db.delete(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            "user_id = ? AND action = ? AND terminal = 1",
            arrayOf(userId, action.action)
        )
        db.insertWithOnConflict(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("id", action.id)
                put("action", action.action)
                put("task_id", action.taskId)
                put("period_id", action.periodId)
                action.expectedVersion?.let { put("expected_version", it) }
                put("payload_json", action.payloadJson)
                put("created_at", PlanningLocalStore.nowIso())
                put("conflict_attempts", action.conflictAttempts)
                put("terminal", 0)
            },
            android.database.sqlite.SQLiteDatabase.CONFLICT_IGNORE
        )
    }

    internal fun pending(userId: String): List<FocusPendingAction> = store.readableDatabase.rawQuery(
        "SELECT id, action, task_id, period_id, expected_version, payload_json, conflict_attempts FROM ${PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS} WHERE user_id = ? AND terminal = 0 ORDER BY created_at, id",
        arrayOf(userId)
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(
                    FocusPendingAction(
                        id = cursor.getString(0),
                        action = cursor.getString(1),
                        taskId = if (cursor.isNull(2)) null else cursor.getString(2),
                        periodId = if (cursor.isNull(3)) null else cursor.getString(3),
                        expectedVersion = if (cursor.isNull(4)) null else cursor.getLong(4),
                        payloadJson = cursor.getString(5),
                        conflictAttempts = cursor.getInt(6)
                    )
                )
            }
        }
    }

    fun removePending(userId: String, id: String) {
        store.writableDatabase.delete(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            "user_id = ? AND id = ?",
            arrayOf(userId, id)
        )
    }

    fun markPendingError(userId: String, id: String, error: String) {
        store.writableDatabase.update(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            ContentValues().apply { put("last_error", error.take(500)) },
            "user_id = ? AND id = ?",
            arrayOf(userId, id)
        )
    }

    fun incrementConflictAttempts(userId: String, id: String): Int {
        val db = store.writableDatabase
        db.execSQL(
            "UPDATE ${PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS} SET conflict_attempts = conflict_attempts + 1 WHERE user_id = ? AND id = ? AND terminal = 0",
            arrayOf(userId, id)
        )
        return db.rawQuery(
            "SELECT conflict_attempts FROM ${PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS} WHERE user_id = ? AND id = ?",
            arrayOf(userId, id)
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getInt(0) else 0 }
    }

    fun terminalizePending(userId: String, id: String, error: String) {
        store.writableDatabase.update(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            ContentValues().apply {
                put("last_error", error.take(500))
                put("terminal", 1)
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, id)
        )
    }

    fun latestTerminalError(userId: String): String? = store.readableDatabase.rawQuery(
        "SELECT last_error FROM ${PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS} WHERE user_id = ? AND terminal = 1 AND last_error IS NOT NULL ORDER BY created_at DESC, id DESC LIMIT 1",
        arrayOf(userId)
    ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    fun updatePendingPayload(userId: String, id: String, payloadJson: String) {
        store.writableDatabase.update(
            PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS,
            ContentValues().apply {
                put("payload_json", payloadJson)
                putNull("last_error")
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, id)
        )
    }

    fun pendingCount(userId: String): Int = store.readableDatabase.rawQuery(
        "SELECT COUNT(*) FROM ${PlanningLocalStore.TABLE_FOCUS_PENDING_ACTIONS} WHERE user_id = ? AND terminal = 0",
        arrayOf(userId)
    ).use { cursor -> if (cursor.moveToFirst()) cursor.getInt(0) else 0 }

    fun saveCalendar(userId: String, month: CalendarMonth) {
        val db = store.writableDatabase
        db.beginTransaction()
        try {
            db.delete(
                PlanningLocalStore.TABLE_CALENDAR_MARKERS,
                "user_id = ? AND range_from = ? AND range_to_exclusive = ?",
                arrayOf(userId, month.from.toString(), month.toExclusive.toString())
            )
            db.insertWithOnConflict(
                PlanningLocalStore.TABLE_CALENDAR_CACHE_RANGES,
                null,
                ContentValues().apply {
                    put("user_id", userId)
                    put("range_from", month.from.toString())
                    put("range_to_exclusive", month.toExclusive.toString())
                    put("timezone", month.timezone)
                    put("updated_at", PlanningLocalStore.nowIso())
                },
                android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
            )
            month.markers.forEach { marker ->
                db.insertWithOnConflict(
                    PlanningLocalStore.TABLE_CALENDAR_MARKERS,
                    null,
                    ContentValues().apply {
                        put("user_id", userId)
                        put("marker_id", marker.markerId)
                        put("occurrence_id", marker.occurrenceId)
                        put("task_id", marker.taskId)
                        put("goal_id", marker.goalId)
                        put("kind", marker.kind.name.lowercase())
                        put("at_time", marker.at)
                        put("local_date", marker.localDate.toString())
                        put("title", marker.title)
                        put("status", marker.status)
                        put("effort", marker.effort)
                        put("recurring", if (marker.recurring) 1 else 0)
                        put("timezone", month.timezone)
                        put("range_from", month.from.toString())
                        put("range_to_exclusive", month.toExclusive.toString())
                    },
                    android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun loadCalendar(userId: String, from: LocalDate, toExclusive: LocalDate): CalendarMonth? {
        return store.readableDatabase.rawQuery(
            "SELECT marker_id, occurrence_id, task_id, goal_id, kind, at_time, local_date, title, status, effort, recurring, timezone FROM ${PlanningLocalStore.TABLE_CALENDAR_MARKERS} WHERE user_id = ? AND range_from = ? AND range_to_exclusive = ? ORDER BY local_date, at_time",
            arrayOf(userId, from.toString(), toExclusive.toString())
        ).use { cursor ->
            val markers = buildList {
                while (cursor.moveToNext()) {
                    add(
                        CalendarMarker(
                            markerId = cursor.getString(0),
                            occurrenceId = cursor.getString(1),
                            taskId = cursor.getString(2),
                            goalId = if (cursor.isNull(3)) null else cursor.getString(3),
                            kind = CalendarMarkerKind.fromApi(cursor.getString(4)),
                            at = cursor.getString(5),
                            localDate = LocalDate.parse(cursor.getString(6)),
                            title = cursor.getString(7),
                            status = cursor.getString(8),
                            effort = cursor.getInt(9),
                            recurring = cursor.getInt(10) != 0
                        )
                    )
                }
            }
            val timezone = cachedTimezone(userId, from, toExclusive) ?: return@use null
            CalendarMonth(timezone, from, toExclusive, markers, offline = true)
        }
    }

    private fun cachedTimezone(userId: String, from: LocalDate, toExclusive: LocalDate): String? =
        store.readableDatabase.rawQuery(
            "SELECT timezone FROM ${PlanningLocalStore.TABLE_CALENDAR_CACHE_RANGES} WHERE user_id = ? AND range_from = ? AND range_to_exclusive = ? LIMIT 1",
            arrayOf(userId, from.toString(), toExclusive.toString())
        ).use { if (it.moveToFirst()) it.getString(0) else null }

    private fun insertItem(userId: String, periodId: String, item: FocusItem) {
        store.writableDatabase.insertWithOnConflict(
            PlanningLocalStore.TABLE_FOCUS_ITEMS,
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("period_id", periodId)
                put("task_id", item.taskId)
                put("title", item.title)
                put("status", item.status)
                put("effort", item.effort)
                put("path", item.path)
                put("display_order", item.displayOrder)
                put("history_only", if (item.historyOnly) 1 else 0)
                put("planned_time", item.plannedTime)
                put("due_time", item.dueTime)
            },
            android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    private fun loadPeriods(userId: String, extraWhere: String, args: Array<String> = emptyArray()): List<FocusPeriod> {
        return store.readableDatabase.rawQuery(
            "SELECT id, week_start, week_end_exclusive, timezone, status, version, rollover_json FROM ${PlanningLocalStore.TABLE_FOCUS_PERIODS} WHERE user_id = ? AND $extraWhere",
            arrayOf(userId, *args)
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    add(
                        FocusPeriod(
                            id = id,
                            weekStart = cursor.getString(1),
                            weekEndExclusive = cursor.getString(2),
                            timezone = cursor.getString(3),
                            status = cursor.getString(4),
                            version = cursor.getLong(5),
                            items = loadItems(userId, id),
                            rolloverOffer = if (cursor.isNull(6)) null else parseRollover(cursor.getString(6))
                        )
                    )
                }
            }
        }
    }

    private fun loadItems(userId: String, periodId: String): List<FocusItem> = store.readableDatabase.rawQuery(
        "SELECT task_id, title, status, effort, path, display_order, history_only, planned_time, due_time FROM ${PlanningLocalStore.TABLE_FOCUS_ITEMS} WHERE user_id = ? AND period_id = ? ORDER BY display_order, task_id",
        arrayOf(userId, periodId)
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(
                    FocusItem(
                        taskId = cursor.getString(0),
                        title = cursor.getString(1),
                        status = cursor.getString(2),
                        effort = cursor.getInt(3),
                        path = cursor.getString(4),
                        displayOrder = cursor.getInt(5),
                        historyOnly = cursor.getInt(6) != 0,
                        plannedTime = if (cursor.isNull(7)) null else cursor.getString(7),
                        dueTime = if (cursor.isNull(8)) null else cursor.getString(8)
                    )
                )
            }
        }
    }

    private fun rolloverJson(offer: FocusRolloverOffer): String = JSONObject()
        .put("sourcePeriodId", offer.sourcePeriodId)
        .put("taskIds", JSONArray(offer.taskIds))
        .toString()

    private fun parseRollover(raw: String): FocusRolloverOffer? = runCatching {
        val json = JSONObject(raw)
        val ids = json.optJSONArray("taskIds") ?: JSONArray()
        FocusRolloverOffer(
            sourcePeriodId = json.getString("sourcePeriodId"),
            taskIds = List(ids.length()) { ids.getString(it) }
        )
    }.getOrNull()
}
