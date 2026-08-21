package com.rocketflow.companion.planning

data class PlannerRowKey(
    val resourceType: String,
    val resourceId: String
)

data class PlannerRowGeometry(
    val key: PlannerRowKey,
    val parentKey: PlannerRowKey?,
    val top: Int,
    val bottom: Int
)

data class PlannerScrollPosition(
    val anchorKey: PlannerRowKey?,
    val ancestorKeys: List<PlannerRowKey>,
    val pixelOffset: Int,
    val absoluteScrollY: Int
)

object PlannerScrollAnchor {
    fun capture(rows: List<PlannerRowGeometry>, scrollY: Int): PlannerScrollPosition {
        val clampedScrollY = scrollY.coerceAtLeast(0)
        val anchor = rows.firstOrNull { it.bottom > clampedScrollY }
            ?: rows.lastOrNull()
        if (anchor == null) {
            return PlannerScrollPosition(null, emptyList(), 0, clampedScrollY)
        }

        val byKey = rows.associateBy { it.key }
        val ancestors = buildList {
            val visited = mutableSetOf<PlannerRowKey>()
            var parent = anchor.parentKey
            while (parent != null && visited.add(parent)) {
                add(parent)
                parent = byKey[parent]?.parentKey
            }
        }
        return PlannerScrollPosition(
            anchorKey = anchor.key,
            ancestorKeys = ancestors,
            pixelOffset = clampedScrollY - anchor.top,
            absoluteScrollY = clampedScrollY
        )
    }

    fun restore(
        position: PlannerScrollPosition?,
        rows: List<PlannerRowGeometry>,
        maxScrollY: Int
    ): Int {
        if (position == null) return 0
        val byKey = rows.associateBy { it.key }
        val survivingAnchor = sequenceOf(position.anchorKey)
            .plus(position.ancestorKeys.asSequence())
            .filterNotNull()
            .mapNotNull(byKey::get)
            .firstOrNull()
        val requested = survivingAnchor?.let { it.top + position.pixelOffset }
            ?: position.absoluteScrollY
        return requested.coerceIn(0, maxScrollY.coerceAtLeast(0))
    }
}
