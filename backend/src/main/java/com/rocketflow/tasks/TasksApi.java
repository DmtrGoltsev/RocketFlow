package com.rocketflow.tasks;

import java.time.DayOfWeek;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import com.fasterxml.jackson.annotation.JsonIgnore;

public final class TasksApi {

    private TasksApi() {
    }

    public record TagDto(UUID id, String name, String color) {
    }

    public record RecurrenceDto(
            String mode,
            int interval,
            List<DayOfWeek> daysOfWeek,
            Integer dayOfMonth,
            Instant startAt,
            Instant endAt,
            boolean active
    ) {
    }

    public record ReminderDto(
            UUID id,
            String mode,
            int offsetMinutes,
            boolean active
    ) {
    }

    public record TaskDto(
            UUID id,
            UUID goalId,
            String title,
            String description,
            String type,
            int priority,
            String status,
            Instant plannedTime,
            Instant dueTime,
            boolean archived,
            boolean shared,
            boolean fullAccess,
            UUID creatorUserId,
            String creatorEmail,
            String creatorName,
            long version,
            List<TagDto> tags,
            RecurrenceDto recurrence,
            @JsonIgnore
            List<ReminderDto> reminders,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record TaskListResponse(List<TaskDto> items) {
    }

    public record CreateTaskRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 2000) String description,
            @NotBlank @Pattern(regexp = "green|red") String type,
            @NotNull @Min(1) @Max(10) Integer priority,
            @NotBlank @Pattern(regexp = "todo|in_progress|done|cancelled") String status,
            Instant plannedTime,
            Instant dueTime,
            List<UUID> tagIds
    ) {
    }

    public record UpdateTaskRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 2000) String description,
            @NotBlank @Pattern(regexp = "green|red") String type,
            @NotNull @Min(1) @Max(10) Integer priority,
            @NotBlank @Pattern(regexp = "todo|in_progress|done|cancelled") String status,
            Instant plannedTime,
            Instant dueTime,
            @NotNull Boolean archived,
            List<UUID> tagIds,
            @NotNull Long version
    ) {
    }

    public record MoveTaskRequest(@NotNull Instant plannedTime) {
    }

    public record MoveTaskToGoalRequest(@NotNull UUID targetGoalId, @NotNull Long version) {
    }

    public record CloneTaskRequest(@NotNull UUID targetGoalId, @Size(max = 200) String title, Boolean includeTags) {
    }

    public record MoveTaskResponse(
            UUID id,
            Instant plannedTime,
            int priority,
            Instant updatedAt
    ) {
    }

    public record QuickRescheduleRequest(
            @Pattern(regexp = "30m|1h|3h|24h") String preset,
            @Min(1) Integer minutes
    ) {
    }

    public record RescheduledTaskDto(
            UUID id,
            Instant plannedTime,
            int priority,
            Instant updatedAt
    ) {
    }

    public record RescheduleEventDto(
            UUID id,
            Instant previousPlannedTime,
            Instant newPlannedTime,
            Instant createdAt
    ) {
    }

    public record QuickRescheduleResponse(
            RescheduledTaskDto task,
            RescheduleEventDto rescheduleEvent,
            boolean priorityDecayApplied
    ) {
    }

    public record UpsertRecurrenceRequest(
            @NotBlank String mode,
            @NotNull @Min(1) Integer interval,
            List<DayOfWeek> daysOfWeek,
            @Min(1) @Max(31) Integer dayOfMonth,
            @NotNull Instant startAt,
            Instant endAt,
            @NotNull Boolean active
    ) {
    }

    public record TaskRecurrenceResponse(UUID taskId, RecurrenceDto recurrence) {
    }

    public record UpsertReminderRequest(
            @NotBlank String mode,
            @NotNull @Min(1) Integer offsetMinutes,
            @NotNull Boolean active
    ) {
    }

    public record ReplaceRemindersRequest(@NotNull List<@Valid UpsertReminderRequest> reminders) {
    }

    public record TaskRemindersResponse(UUID taskId, List<ReminderDto> reminders) {
    }

    public record CreateTagRequest(
            @NotBlank @Size(max = 80) String name,
            @Size(max = 16) String color
    ) {
    }

    public record TagListResponse(List<TagDto> items) {
    }
}
