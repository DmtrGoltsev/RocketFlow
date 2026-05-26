package com.rocketflow.companion.planning

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

class FolderActivityOrdering(
    private val store: BucketStore
) {
    constructor(context: Context) : this(
        SharedPreferencesBucketStore(
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        )
    )

    data class SnapshotData(
        val folders: List<PlanningFolder>,
        val goals: List<PlanningGoal>,
        val tasks: List<PlanningTask>,
        val ideas: List<PlanningIdea>,
        val ideaNotes: List<IdeaNote>,
        val notes: List<PlanningNote>
    )

    data class StoredOrder(
        val folderIds: List<String>,
        val lastAppliedAtMillis: Long
    )

    interface BucketStore {
        fun read(userId: String, bucketId: String): StoredOrder?
        fun write(userId: String, bucketId: String, order: StoredOrder)
    }

    fun orderSiblings(
        userId: String,
        parentFolderId: String?,
        scope: String,
        siblingFolders: List<PlanningFolder>,
        snapshot: SnapshotData,
        persist: Boolean = true,
        nowMillis: Long = System.currentTimeMillis()
    ): List<PlanningFolder> {
        if (siblingFolders.size < 2) return siblingFolders

        val bucketId = bucketId(scope, parentFolderId)
        val candidate = candidateOrder(siblingFolders, snapshot)
        val candidateIds = candidate.map { it.id }
        val stored = store.read(userId, bucketId)
        if (stored == null || nowMillis - stored.lastAppliedAtMillis >= APPLY_INTERVAL_MILLIS) {
            if (persist) {
                store.write(userId, bucketId, StoredOrder(candidateIds, nowMillis))
            }
            return candidate
        }

        val folderById = siblingFolders.associateBy { it.id }
        val existingIds = stored.folderIds.filter { it in folderById }
        val newIds = candidateIds.filterNot { it in existingIds }
        if (newIds.isEmpty() && existingIds.size == siblingFolders.size) {
            return existingIds.mapNotNull(folderById::get)
        }

        val activity = ActivityIndex(snapshot).folderActivityMillis()
        val mergedIds = insertNewIdsByActivity(existingIds, newIds, candidateIds, activity)
        if (persist) {
            store.write(
                userId,
                bucketId,
                StoredOrder(
                    folderIds = mergedIds,
                    lastAppliedAtMillis = stored.lastAppliedAtMillis
                )
            )
        }
        return mergedIds.mapNotNull(folderById::get)
    }

    private fun candidateOrder(
        siblingFolders: List<PlanningFolder>,
        snapshot: SnapshotData
    ): List<PlanningFolder> {
        val localIndex = siblingFolders.mapIndexed { index, folder -> folder.id to index }.toMap()
        val activity = ActivityIndex(snapshot).folderActivityMillis()
        return siblingFolders.sortedWith(
            compareByDescending<PlanningFolder> { activity[it.id] ?: 0L }
                .thenBy { localIndex[it.id] ?: Int.MAX_VALUE }
        )
    }

    private fun insertNewIdsByActivity(
        existingIds: List<String>,
        newIds: List<String>,
        candidateIds: List<String>,
        activity: Map<String, Long>
    ): List<String> {
        val candidateIndex = candidateIds.mapIndexed { index, id -> id to index }.toMap()
        val result = existingIds.toMutableList()
        newIds.sortedBy { candidateIndex[it] ?: Int.MAX_VALUE }.forEach { newId ->
            val newActivity = activity[newId] ?: 0L
            val insertAt = result.indexOfFirst { existingId ->
                val existingActivity = activity[existingId] ?: 0L
                existingActivity < newActivity ||
                    (existingActivity == newActivity &&
                        (candidateIndex[newId] ?: Int.MAX_VALUE) < (candidateIndex[existingId] ?: Int.MAX_VALUE))
            }
            if (insertAt >= 0) {
                result.add(insertAt, newId)
            } else {
                result.add(newId)
            }
        }
        return result
    }

    private fun bucketId(scope: String, parentFolderId: String?): String {
        return "$scope:${parentFolderId ?: ROOT_PARENT_ID}"
    }

    private class ActivityIndex(
        private val snapshot: SnapshotData
    ) {
        private val foldersById = snapshot.folders.associateBy { it.id }
        private val childrenByParent = snapshot.folders.groupBy { it.parentFolderId }
        private val goalsByFolder = snapshot.goals.groupBy { it.folderId }
        private val tasksByGoal = snapshot.tasks.groupBy { it.goalId }
        private val ideasByFolder = snapshot.ideas.groupBy { it.folderId }
        private val ideaNotesByIdea = snapshot.ideaNotes.groupBy { it.ideaId }
        private val notesByFolder = snapshot.notes.groupBy { it.folderId }
        private val activityCache = mutableMapOf<String, Long>()

        fun folderActivityMillis(): Map<String, Long> {
            return snapshot.folders.associate { folder -> folder.id to activityForFolder(folder.id) }
        }

        private fun activityForFolder(folderId: String): Long {
            activityCache[folderId]?.let { return it }
            val visited = mutableSetOf<String>()
            var latest = foldersById[folderId]?.let { parseMillis(it.updatedAt, it.createdAt) } ?: 0L

            fun collect(currentFolderId: String) {
                if (!visited.add(currentFolderId)) return
                foldersById[currentFolderId]?.let { folder ->
                    latest = maxOf(latest, parseMillis(folder.updatedAt, folder.createdAt))
                }
                goalsByFolder[currentFolderId].orEmpty().forEach { goal ->
                    latest = maxOf(latest, parseMillis(goal.updatedAt, goal.createdAt))
                    tasksByGoal[goal.id].orEmpty().forEach { task ->
                        latest = maxOf(latest, parseMillis(task.updatedAt, task.createdAt))
                    }
                }
                ideasByFolder[currentFolderId].orEmpty().forEach { idea ->
                    latest = maxOf(latest, parseMillis(idea.updatedAt, idea.createdAt))
                    ideaNotesByIdea[idea.id].orEmpty().forEach { note ->
                        latest = maxOf(latest, parseMillis(note.updatedAt, note.createdAt))
                    }
                }
                notesByFolder[currentFolderId].orEmpty().forEach { note ->
                    latest = maxOf(latest, parseMillis(note.updatedAt, note.createdAt))
                }
                childrenByParent[currentFolderId].orEmpty().forEach { child ->
                    collect(child.id)
                }
            }

            collect(folderId)
            activityCache[folderId] = latest
            return latest
        }
    }

    private class SharedPreferencesBucketStore(
        private val preferences: SharedPreferences
    ) : BucketStore {
        override fun read(userId: String, bucketId: String): StoredOrder? {
            val raw = preferences.getString(key(userId, bucketId), null) ?: return null
            return runCatching {
                val json = JSONObject(raw)
                val ids = json.optJSONArray("folderIds") ?: JSONArray()
                StoredOrder(
                    folderIds = List(ids.length()) { index -> ids.optString(index) }
                        .filter { it.isNotBlank() },
                    lastAppliedAtMillis = json.optLong("lastAppliedAtMillis", 0L)
                )
            }.getOrNull()
        }

        override fun write(userId: String, bucketId: String, order: StoredOrder) {
            val ids = JSONArray()
            order.folderIds.forEach(ids::put)
            val json = JSONObject()
                .put("folderIds", ids)
                .put("lastAppliedAtMillis", order.lastAppliedAtMillis)
            preferences.edit()
                .putString(key(userId, bucketId), json.toString())
                .apply()
        }

        private fun key(userId: String, bucketId: String): String {
            return "$userId::$bucketId"
        }
    }

    companion object {
        private const val PREFERENCES_NAME = "folder_activity_ordering"
        private const val ROOT_PARENT_ID = "root"
        const val APPLY_INTERVAL_MILLIS = 24L * 60L * 60L * 1000L

        fun parseMillis(updatedAt: String?, createdAt: String?): Long {
            return parseDateMillis(updatedAt)
                ?: parseDateMillis(createdAt)
                ?: 0L
        }

        private fun parseDateMillis(value: String?): Long? {
            val trimmed = value?.trim().orEmpty()
            if (trimmed.isBlank()) return null
            return runCatching { Instant.parse(trimmed).toEpochMilli() }.getOrNull()
                ?: runCatching { OffsetDateTime.parse(trimmed).toInstant().toEpochMilli() }.getOrNull()
                ?: runCatching {
                    LocalDateTime.parse(trimmed, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                        .toInstant(ZoneOffset.UTC)
                        .toEpochMilli()
                }.getOrNull()
        }
    }
}
