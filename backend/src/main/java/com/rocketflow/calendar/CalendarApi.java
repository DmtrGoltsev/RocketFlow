package com.rocketflow.calendar;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public final class CalendarApi {

    private CalendarApi() {
    }

    public record CalendarItemDto(
            UUID taskId,
            UUID goalId,
            String title,
            String type,
            int priority,
            String status,
            Instant plannedTime,
            Instant dueTime
    ) {
    }

    public record CalendarResponse(List<CalendarItemDto> items) {
    }

    public record CalendarMarkerDto(
            UUID markerId,
            UUID occurrenceId,
            UUID taskId,
            UUID goalId,
            String title,
            String status,
            int effort,
            String kind,
            Instant at,
            LocalDate localDate,
            boolean recurring
    ) {
    }

    public record CalendarMarkersResponse(
            String timezone,
            LocalDate from,
            LocalDate toExclusive,
            List<CalendarMarkerDto> markers
    ) {
    }
}
