package com.rocketflow.recurrence;

import java.time.DayOfWeek;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import com.rocketflow.common.ApiException;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TasksApi.UpsertRecurrenceRequest;

@Component
public class RecurrenceValidator {

    public void validate(Task task, UpsertRecurrenceRequest request, ZoneId ownerZone, List<DayOfWeek> normalizedDaysOfWeek) {
        if (!List.of("daily", "weekly", "monthly").contains(request.mode())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Recurrence mode is not supported.");
        }
        if (request.endAt() != null && !request.endAt().isAfter(request.startAt())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Recurrence endAt must be after startAt.");
        }
        if (task.getPlannedTime() == null && task.getDueTime() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Recurrence requires the task to have plannedTime or dueTime.");
        }
        if (!matchesTaskAnchor(task, request.startAt())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Recurrence startAt must match the task plannedTime or dueTime.");
        }

        switch (request.mode()) {
            case "daily" -> validateDaily(request);
            case "weekly" -> validateWeekly(request, ownerZone, normalizedDaysOfWeek);
            case "monthly" -> validateMonthly(request, ownerZone);
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Recurrence mode is not supported.");
        }
    }

    public List<DayOfWeek> normalizeDaysOfWeek(List<DayOfWeek> daysOfWeek) {
        if (daysOfWeek == null || daysOfWeek.isEmpty()) {
            return List.of();
        }
        EnumSet<DayOfWeek> unique = EnumSet.copyOf(daysOfWeek);
        if (unique.size() != daysOfWeek.size()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Weekly recurrence contains duplicate weekdays.");
        }
        List<DayOfWeek> normalized = new ArrayList<>(unique);
        normalized.sort(Enum::compareTo);
        return List.copyOf(normalized);
    }

    private void validateDaily(UpsertRecurrenceRequest request) {
        if (request.dayOfMonth() != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Daily recurrence does not support dayOfMonth.");
        }
        if (request.daysOfWeek() != null && !request.daysOfWeek().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Daily recurrence does not support daysOfWeek.");
        }
    }

    private void validateWeekly(UpsertRecurrenceRequest request, ZoneId ownerZone, List<DayOfWeek> normalizedDaysOfWeek) {
        if (normalizedDaysOfWeek.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Weekly recurrence requires at least one weekday.");
        }
        if (request.dayOfMonth() != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Weekly recurrence does not support dayOfMonth.");
        }
        DayOfWeek startDay = request.startAt().atZone(ownerZone).getDayOfWeek();
        if (!normalizedDaysOfWeek.contains(startDay)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Weekly recurrence must include the owner-local weekday of startAt.");
        }
    }

    private void validateMonthly(UpsertRecurrenceRequest request, ZoneId ownerZone) {
        if (request.dayOfMonth() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Monthly recurrence requires dayOfMonth.");
        }
        if (request.daysOfWeek() != null && !request.daysOfWeek().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Monthly recurrence does not support daysOfWeek.");
        }
        int startDayOfMonth = request.startAt().atZone(ownerZone).getDayOfMonth();
        if (startDayOfMonth != request.dayOfMonth()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Monthly recurrence dayOfMonth must match the owner-local day of startAt.");
        }
    }

    private boolean matchesTaskAnchor(Task task, java.time.Instant startAt) {
        return startAt.equals(task.getPlannedTime()) || startAt.equals(task.getDueTime());
    }
}
