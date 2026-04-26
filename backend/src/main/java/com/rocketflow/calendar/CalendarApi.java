package com.rocketflow.calendar;

import java.time.Instant;
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
}
