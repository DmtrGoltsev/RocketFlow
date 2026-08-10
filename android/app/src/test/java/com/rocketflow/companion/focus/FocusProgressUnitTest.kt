package com.rocketflow.companion.focus

import org.junit.Assert.assertEquals
import org.junit.Test

class FocusProgressUnitTest {
    @Test
    fun progressUsesFallbackWeightAndCountsOnlyDone() {
        val items = listOf(
            item("done-zero", "done", 0),
            item("done-five", "done", 5),
            item("working", "in_progress", 4),
            item("history", "done", 100).copy(historyOnly = true)
        )

        val progress = FocusProgress.from(items)

        assertEquals(6, progress.completedWeight)
        assertEquals(10, progress.totalWeight)
        assertEquals(60, progress.percent)
    }

    @Test
    fun offlineProgressRoundsToSameNearestPercentAsServer() {
        val items = buildList {
            repeat(2) { index -> add(item("done-$index", "done", 1)) }
            repeat(10) { index -> add(item("todo-$index", "todo", 1)) }
        }

        val progress = FocusProgress.from(items)

        assertEquals(2, progress.completedWeight)
        assertEquals(12, progress.totalWeight)
        assertEquals(17, progress.percent)
    }

    private fun item(id: String, status: String, effort: Int) = FocusItem(
        taskId = id,
        title = id,
        status = status,
        effort = effort,
        path = "",
        displayOrder = 0
    )
}
