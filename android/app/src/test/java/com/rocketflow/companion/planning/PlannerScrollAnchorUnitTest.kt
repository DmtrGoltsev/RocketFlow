package com.rocketflow.companion.planning

import org.junit.Assert.assertEquals
import org.junit.Test

class PlannerScrollAnchorUnitTest {
    private val folder = PlannerRowKey("folder", "folder-1")
    private val goal = PlannerRowKey("goal", "goal-1")
    private val task = PlannerRowKey("task", "task-1")

    @Test
    fun captureUsesFirstVisibleStableRowAndPixelOffset() {
        val captured = PlannerScrollAnchor.capture(expandedRows(), scrollY = 125)

        assertEquals(task, captured.anchorKey)
        assertEquals(listOf(goal, folder), captured.ancestorKeys)
        assertEquals(5, captured.pixelOffset)
        assertEquals(125, captured.absoluteScrollY)
    }

    @Test
    fun restoreKeepsAnchorOffsetWhenRowsAboveChange() {
        val captured = PlannerScrollAnchor.capture(expandedRows(), scrollY = 125)
        val changedRows = listOf(
            row(folder, null, 80, 130),
            row(goal, folder, 170, 220),
            row(task, goal, 260, 310)
        )

        assertEquals(265, PlannerScrollAnchor.restore(captured, changedRows, maxScrollY = 500))
    }

    @Test
    fun restoreUsesNearestSurvivingParentWhenAnchorDisappears() {
        val captured = PlannerScrollAnchor.capture(expandedRows(), scrollY = 125)
        val collapsedRows = listOf(
            row(folder, null, 20, 70),
            row(goal, folder, 80, 130)
        )

        assertEquals(85, PlannerScrollAnchor.restore(captured, collapsedRows, maxScrollY = 500))
    }

    @Test
    fun restoreFallsBackToClampedAbsolutePositionWhenHierarchyDisappears() {
        val captured = PlannerScrollAnchor.capture(expandedRows(), scrollY = 125)

        assertEquals(90, PlannerScrollAnchor.restore(captured, emptyList(), maxScrollY = 90))
    }

    private fun expandedRows(): List<PlannerRowGeometry> = listOf(
        row(folder, null, 0, 50),
        row(goal, folder, 60, 110),
        row(task, goal, 120, 170)
    )

    private fun row(key: PlannerRowKey, parent: PlannerRowKey?, top: Int, bottom: Int) =
        PlannerRowGeometry(key, parent, top, bottom)
}
