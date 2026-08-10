package com.rocketflow.companion.calendar

import java.time.LocalDate

enum class CalendarMarkerKind {
    Planned,
    Deadline;

    companion object {
        fun fromApi(value: String): CalendarMarkerKind =
            if (value.equals("deadline", ignoreCase = true)) Deadline else Planned
    }
}

data class CalendarMarker(
    val markerId: String,
    val occurrenceId: String,
    val taskId: String,
    val goalId: String?,
    val kind: CalendarMarkerKind,
    val at: String,
    val localDate: LocalDate,
    val title: String,
    val status: String,
    val effort: Int,
    val recurring: Boolean
)

data class CalendarMonth(
    val timezone: String,
    val from: LocalDate,
    val toExclusive: LocalDate,
    val markers: List<CalendarMarker>,
    val offline: Boolean = false,
    val error: String? = null
) {
    fun on(date: LocalDate): List<CalendarMarker> = markers
        .filter { it.localDate == date }
        .sortedWith(compareBy<CalendarMarker> { it.at }.thenBy { it.title }.thenBy { it.kind.ordinal })
}
