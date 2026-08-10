package com.rocketflow.companion.focus

import kotlin.math.roundToInt

data class FocusItem(
    val taskId: String,
    val title: String,
    val status: String,
    val effort: Int,
    val path: String,
    val displayOrder: Int,
    val historyOnly: Boolean = false,
    val plannedTime: String? = null,
    val dueTime: String? = null
) {
    val effectiveWeight: Int get() = effort.coerceAtLeast(1)
    val done: Boolean get() = status == "done"
}

data class FocusProgress(
    val completedWeight: Int,
    val totalWeight: Int
) {
    val percent: Int
        get() = if (totalWeight == 0) {
            0
        } else {
            ((completedWeight * 100.0) / totalWeight).roundToInt().coerceIn(0, 100)
        }

    companion object {
        fun from(items: List<FocusItem>): FocusProgress {
            val visible = items.filterNot { it.historyOnly }
            return FocusProgress(
                completedWeight = visible.filter { it.done }.sumOf { it.effectiveWeight },
                totalWeight = visible.sumOf { it.effectiveWeight }
            )
        }
    }
}

data class FocusRolloverOffer(
    val sourcePeriodId: String,
    val taskIds: List<String>
)

data class FocusPeriod(
    val id: String,
    val weekStart: String,
    val weekEndExclusive: String,
    val timezone: String,
    val status: String,
    val version: Long,
    val items: List<FocusItem>,
    val rolloverOffer: FocusRolloverOffer? = null
) {
    val progress: FocusProgress get() = FocusProgress.from(items)
}

data class FocusHistorySummary(
    val id: String,
    val weekStart: String,
    val weekEndExclusive: String,
    val timezone: String,
    val status: String,
    val version: Long,
    val progress: FocusProgress
)

data class FocusNotificationSettings(
    val intervalMinutes: Int?,
    val quietStart: String?,
    val quietEnd: String?,
    val version: Long = 0
) {
    companion object {
        val DEFAULT = FocusNotificationSettings(intervalMinutes = 120, quietStart = "22:00", quietEnd = "08:00")
        val ALLOWED_INTERVALS = listOf<Int?>(null, 30, 60, 120, 240)
    }
}

internal enum class QuietHoursValidationError {
    PAIR_REQUIRED,
    INVALID_FORMAT
}

internal fun FocusNotificationSettings.quietHoursValidationError(): QuietHoursValidationError? {
    if ((quietStart == null) != (quietEnd == null)) return QuietHoursValidationError.PAIR_REQUIRED
    if (quietStart == null) return null
    return if (QUIET_HOURS_PATTERN.matches(quietStart) && QUIET_HOURS_PATTERN.matches(quietEnd.orEmpty())) {
        null
    } else {
        QuietHoursValidationError.INVALID_FORMAT
    }
}

private val QUIET_HOURS_PATTERN = Regex("(?:[01]\\d|2[0-3]):[0-5]\\d")

data class FocusCandidate(
    val taskId: String,
    val title: String,
    val status: String,
    val effort: Int,
    val folderId: String?,
    val folderName: String?,
    val goalId: String?,
    val goalName: String?,
    val path: String,
    val shared: Boolean
)

data class FocusCandidatePage(
    val items: List<FocusCandidate>,
    val nextCursor: String?
)

data class FocusLoadResult(
    val period: FocusPeriod?,
    val offline: Boolean,
    val pendingCount: Int,
    val error: String? = null
)

internal data class FocusPendingAction(
    val id: String,
    val action: String,
    val taskId: String?,
    val periodId: String?,
    val expectedVersion: Long?,
    val payloadJson: String,
    val conflictAttempts: Int = 0
)
