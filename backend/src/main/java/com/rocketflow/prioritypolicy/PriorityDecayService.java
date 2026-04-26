package com.rocketflow.prioritypolicy;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.calendar.TaskRescheduleEvent;
import com.rocketflow.calendar.TaskRescheduleEventRepository;
import com.rocketflow.settings.UserSettings;
import com.rocketflow.settings.UserSettingsService;
import com.rocketflow.tasks.Task;

@Service
public class PriorityDecayService {

    private final UserSettingsService userSettingsService;
    private final TaskRescheduleEventRepository taskRescheduleEventRepository;

    public PriorityDecayService(
            UserSettingsService userSettingsService,
            TaskRescheduleEventRepository taskRescheduleEventRepository
    ) {
        this.userSettingsService = userSettingsService;
        this.taskRescheduleEventRepository = taskRescheduleEventRepository;
    }

    @Transactional(readOnly = true)
    public PriorityDecayResult evaluate(Task task, Instant previousPlannedTime, Instant newPlannedTime) {
        int currentPriority = task.getPriority();
        if (previousPlannedTime == null || newPlannedTime == null || !newPlannedTime.isAfter(previousPlannedTime)) {
            return PriorityDecayResult.noChange(currentPriority);
        }

        UserSettings settings = userSettingsService.getUserSettingsEntity(task.getOwnerUserId());
        Policy policy = resolvePolicy(settings, task.getType());
        if (!policy.enabled()) {
            return PriorityDecayResult.noChange(currentPriority);
        }

        long thresholdSeconds = policy.threshold().toSeconds();
        long beforeSeconds = totalPostponedSeconds(task.getId());
        long currentPostponeSeconds = Duration.between(previousPlannedTime, newPlannedTime).toSeconds();
        long afterSeconds = beforeSeconds + currentPostponeSeconds;
        long crossedThresholds = (afterSeconds / thresholdSeconds) - (beforeSeconds / thresholdSeconds);
        if (crossedThresholds <= 0) {
            return PriorityDecayResult.noChange(currentPriority);
        }

        long decayPoints = crossedThresholds * policy.decayAmount();
        int updatedPriority = (int) Math.max(1, currentPriority - decayPoints);
        if (updatedPriority == currentPriority) {
            return PriorityDecayResult.noChange(currentPriority);
        }

        return new PriorityDecayResult(currentPriority, updatedPriority, true);
    }

    private long totalPostponedSeconds(UUID taskId) {
        long totalSeconds = 0;
        for (TaskRescheduleEvent event : taskRescheduleEventRepository.findByTaskIdOrderByCreatedAtAsc(taskId)) {
            totalSeconds += Duration.between(event.getPreviousPlannedTime(), event.getNewPlannedTime()).toSeconds();
        }
        return totalSeconds;
    }

    private Policy resolvePolicy(UserSettings settings, String taskType) {
        return switch (taskType) {
            case "green" -> new Policy(
                    settings.isGreenPriorityDecayEnabled(),
                    resolveThreshold(settings.getGreenPriorityDecayThreshold()),
                    settings.getGreenPriorityDecayAmount()
            );
            case "red" -> new Policy(
                    settings.isRedPriorityDecayEnabled(),
                    resolveThreshold(settings.getRedPriorityDecayThreshold()),
                    settings.getRedPriorityDecayAmount()
            );
            default -> throw new IllegalStateException("Unsupported task type for priority decay: " + taskType);
        };
    }

    private Duration resolveThreshold(String thresholdPreset) {
        return switch (thresholdPreset) {
            case "day" -> Duration.ofDays(1);
            case "week" -> Duration.ofDays(7);
            case "month" -> Duration.ofDays(30);
            default -> throw new IllegalStateException("Unsupported priority decay threshold: " + thresholdPreset);
        };
    }

    private record Policy(boolean enabled, Duration threshold, int decayAmount) {
    }

    public record PriorityDecayResult(int priorityBefore, int priorityAfter, boolean applied) {

        public static PriorityDecayResult noChange(int currentPriority) {
            return new PriorityDecayResult(currentPriority, currentPriority, false);
        }
    }
}
