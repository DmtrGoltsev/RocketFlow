package com.rocketflow.recurrence;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TasksApi.RecurrenceDto;
import com.rocketflow.tasks.TasksApi.UpsertRecurrenceRequest;

@Service
public class RecurrenceService {

    private final TaskRecurrenceRuleRepository repository;
    private final UserRepository userRepository;
    private final RecurrenceValidator validator;

    public RecurrenceService(
            TaskRecurrenceRuleRepository repository,
            UserRepository userRepository,
            RecurrenceValidator validator
    ) {
        this.repository = repository;
        this.userRepository = userRepository;
        this.validator = validator;
    }

    @Transactional
    public RecurrenceDto upsert(Task task, UpsertRecurrenceRequest request) {
        User owner = requireOwner(task.getOwnerUserId());
        ZoneId ownerZone = ZoneId.of(owner.getTimezone());
        List<DayOfWeek> normalizedDaysOfWeek = validator.normalizeDaysOfWeek(request.daysOfWeek());
        validator.validate(task, request, ownerZone, normalizedDaysOfWeek);

        Instant now = Instant.now();
        TaskRecurrenceRule rule = repository.findByTaskId(task.getId()).orElseGet(TaskRecurrenceRule::new);
        if (rule.getId() == null) {
            rule.setId(UUID.randomUUID());
            rule.setTaskId(task.getId());
            rule.setCreatedAt(now);
        }
        rule.setMode(request.mode());
        rule.setIntervalValue(request.interval());
        rule.setDaysOfWeek(joinDaysOfWeek(normalizedDaysOfWeek));
        rule.setDayOfMonth(request.dayOfMonth());
        rule.setStartAt(request.startAt());
        rule.setEndAt(request.endAt());
        rule.setActive(request.active());
        rule.setUpdatedAt(now);

        return toDto(repository.save(rule));
    }

    @Transactional(readOnly = true)
    public RecurrenceDto findDto(UUID taskId) {
        return repository.findByTaskId(taskId)
                .map(this::toDto)
                .orElse(null);
    }

    @Transactional(readOnly = true)
    public Map<UUID, RecurrenceDto> findDtos(List<UUID> taskIds) {
        if (taskIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, RecurrenceDto> result = new HashMap<>();
        for (TaskRecurrenceRule rule : repository.findByTaskIdIn(taskIds)) {
            result.put(rule.getTaskId(), toDto(rule));
        }
        return result;
    }

    static List<DayOfWeek> parseDaysOfWeek(String rawValue) {
        if (rawValue == null || rawValue.isBlank()) {
            return List.of();
        }
        return Arrays.stream(rawValue.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .map(DayOfWeek::valueOf)
                .sorted()
                .collect(Collectors.toList());
    }

    private String joinDaysOfWeek(List<DayOfWeek> daysOfWeek) {
        if (daysOfWeek.isEmpty()) {
            return null;
        }
        return daysOfWeek.stream()
                .map(DayOfWeek::name)
                .collect(Collectors.joining(","));
    }

    private RecurrenceDto toDto(TaskRecurrenceRule rule) {
        return new RecurrenceDto(
                rule.getMode(),
                rule.getIntervalValue(),
                parseDaysOfWeek(rule.getDaysOfWeek()),
                rule.getDayOfMonth(),
                rule.getStartAt(),
                rule.getEndAt(),
                rule.isActive()
        );
    }

    private User requireOwner(UUID ownerUserId) {
        return userRepository.findById(ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "User was not found."));
    }
}
