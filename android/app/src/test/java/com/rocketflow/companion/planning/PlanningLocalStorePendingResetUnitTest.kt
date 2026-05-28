package com.rocketflow.companion.planning

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlanningLocalStorePendingResetUnitTest {
    private lateinit var context: Context
    private lateinit var store: PlanningLocalStore

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
        store = PlanningLocalStore(context)
    }

    @After
    fun tearDown() {
        store.close()
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun resetPendingCreateGoalClearsBlockedMissingFolderIssue() {
        val userId = "user-1"
        val goalId = store.createGoal(
            userId = userId,
            folderId = "missing-folder",
            draft = GoalDraft(name = "Blocked goal", description = "")
        )
        store.markSyncError(
            userId = userId,
            table = PlanningLocalStore.TABLE_GOALS,
            id = goalId,
            error = "POST /folders/missing-folder/goals - HTTP 404 - not_found - Folder was not found.",
            conflict = true
        )

        val blockedSnapshot = store.snapshot(userId, offline = false, lastSyncError = "Folder was not found.")
        val issue = blockedSnapshot.pendingIssues.single()
        assertEquals(1, blockedSnapshot.pendingCount)
        assertTrue(PlanningPendingIssueClassifier.isGoalMissingFolder(issue))

        store.resetPendingIssue(userId, issue)

        val resetSnapshot = store.snapshot(userId, offline = false, lastSyncError = null)
        assertEquals(0, resetSnapshot.pendingCount)
        assertTrue(resetSnapshot.pendingIssues.isEmpty())
        assertTrue(resetSnapshot.goals.none { it.id == goalId })
        assertEquals(null, resetSnapshot.lastSyncError)
    }

    private companion object {
        const val DATABASE_NAME = "rocketflow_planning.db"
    }
}
