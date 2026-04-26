package com.rocketflow.reminders;

import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TasksApi.ReminderDto;
import com.rocketflow.tasks.TasksApi.ReplaceRemindersRequest;
import com.rocketflow.tasks.TasksApi.UpsertReminderRequest;

@Service
public class ReminderService {

    private final TaskReminderRuleRepository repository;
    private final UserRepository userRepository;
    private final ReminderEligibilityService eligibilityService;

    public ReminderService(
            TaskReminderRuleRepository repository,
            UserRepository userRepository,
            ReminderEligibilityService eligibilityService
    ) {
        this.repository = repository;
        this.userRepository = userRepository;
        this.eligibilityService = eligibilityService;
    }

    @Transactional
    public List<ReminderDto> replace(Task task, ReplaceRemindersRequest request) {
        User owner = requireOwner(task.getOwnerUserId());
        ZoneId ownerZone = ZoneId.of(owner.getTimezone());
        eligibilityService.validate(task, request.reminders());

        List<TaskReminderRule> existingRules = repository.findByTaskIdOrderBySortOrderAsc(task.getId());
        Map<String, TaskReminderRule> existingByKey = new HashMap<>();
        for (TaskReminderRule existingRule : existingRules) {
            existingByKey.put(key(existingRule.getMode(), existingRule.getOffsetMinutes()), existingRule);
        }

        repository.deleteByTaskId(task.getId());
        if (request.reminders().isEmpty()) {
            return List.of();
        }

        Instant now = Instant.now();
        for (int index = 0; index < request.reminders().size(); index++) {
            UpsertReminderRequest reminder = request.reminders().get(index);
            TaskReminderRule rule = existingByKey.getOrDefault(
                    key(reminder.mode(), reminder.offsetMinutes()),
                    new TaskReminderRule()
            );
            if (rule.getId() == null) {
                rule.setId(UUID.randomUUID());
                rule.setCreatedAt(now);
            }
            rule.setTaskId(task.getId());
            rule.setMode(reminder.mode());
            rule.setOffsetMinutes(reminder.offsetMinutes());
            rule.setActive(reminder.active());
            rule.setSortOrder(index);
            rule.setUpdatedAt(now);
            repository.save(rule);
            eligibilityService.calculateEligibleAt(task, rule, ownerZone);
        }

        return findDtos(task.getId());
    }

    @Transactional(readOnly = true)
    public List<ReminderDto> findDtos(UUID taskId) {
        return repository.findByTaskIdOrderBySortOrderAsc(taskId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    @Transactional(readOnly = true)
    public Map<UUID, List<ReminderDto>> findDtos(List<UUID> taskIds) {
        if (taskIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, List<ReminderDto>> result = new HashMap<>();
        for (TaskReminderRule rule : repository.findByTaskIdInOrderByTaskIdAscSortOrderAsc(taskIds)) {
            result.computeIfAbsent(rule.getTaskId(), ignored -> new ArrayList<>()).add(toDto(rule));
        }
        return result;
    }

    private ReminderDto toDto(TaskReminderRule rule) {
        return new ReminderDto(rule.getId(), rule.getMode(), rule.getOffsetMinutes(), rule.isActive());
    }

    private String key(String mode, int offsetMinutes) {
        return mode + ":" + offsetMinutes;
    }

    private User requireOwner(UUID ownerUserId) {
        return userRepository.findById(ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "User was not found."));
    }
}
