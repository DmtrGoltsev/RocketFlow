package com.rocketflow.companion.planning

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanningPendingIssueClassifierUnitTest {

    @Test
    fun recognizesGoalMissingFolderConflict() {
        val issue = PlanningPendingIssue(
            entityType = PlanningLocalStore.TABLE_GOALS,
            id = "goal-1",
            action = "create",
            error = "POST /folders/folder-1/goals - HTTP 404 - not_found - Folder was not found.",
            blocked = true
        )

        assertTrue(PlanningPendingIssueClassifier.isGoalMissingFolder(issue))
    }

    @Test
    fun ignoresRetryableGoalErrors() {
        val issue = PlanningPendingIssue(
            entityType = PlanningLocalStore.TABLE_GOALS,
            id = "goal-1",
            action = "create",
            error = "Network unavailable.",
            blocked = false
        )

        assertFalse(PlanningPendingIssueClassifier.isGoalMissingFolder(issue))
    }

    @Test
    fun ignoresUnblockedMissingFolderErrors() {
        val issue = PlanningPendingIssue(
            entityType = PlanningLocalStore.TABLE_GOALS,
            id = "goal-1",
            action = "create",
            error = "Folder was not found.",
            blocked = false
        )

        assertFalse(PlanningPendingIssueClassifier.isGoalMissingFolder(issue))
    }

    @Test
    fun ignoresMissingFolderErrorsForOtherEntities() {
        val issue = PlanningPendingIssue(
            entityType = PlanningLocalStore.TABLE_TASKS,
            id = "task-1",
            action = "create",
            error = "Folder was not found.",
            blocked = true
        )

        assertFalse(PlanningPendingIssueClassifier.isGoalMissingFolder(issue))
    }
}
