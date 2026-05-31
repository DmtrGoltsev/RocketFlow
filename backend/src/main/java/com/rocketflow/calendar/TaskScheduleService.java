package com.rocketflow.calendar;

import static com.rocketflow.tasks.TasksApi.*;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class TaskScheduleService {

    private static final Map<String, Duration> PRESET_DURATIONS = Map.of(
            "30m", Duration.ofMinutes(30),
            "1h", Duration.ofHours(1),
            "3h", Duration.ofHours(3),
            "24h", Duration.ofHours(24)
    );

    private final SharingAccessService sharingAccessService;
    private final TaskRepository taskRepository;
    private final TaskRescheduleEventRepository taskRescheduleEventRepository;

    public TaskScheduleService(
            SharingAccessService sharingAccessService,
            TaskRepository taskRepository,
            TaskRescheduleEventRepository taskRescheduleEventRepository
    ) {
        this.sharingAccessService = sharingAccessService;
        this.taskRepository = taskRepository;
        this.taskRescheduleEventRepository = taskRescheduleEventRepository;
    }

    @Transactional
    public MoveTaskResponse moveTask(UUID actorUserId, UUID taskId, MoveTaskRequest request) {
        Task task = sharingAccessService.requireTaskOwner(taskId, actorUserId).task();
        Instant previousPlannedTime = task.getPlannedTime();
        Instant newPlannedTime = request.plannedTime();
        Instant now = Instant.now();
        int priorityBefore = task.getPriority();

        applyTaskUpdate(task, newPlannedTime, now);
        if (shouldRecordReschedule(previousPlannedTime, newPlannedTime)) {
            taskRescheduleEventRepository.save(buildEvent(task, actorUserId, previousPlannedTime, newPlannedTime, priorityBefore, now));
        }
        taskRepository.save(task);

        return new MoveTaskResponse(task.getId(), task.getPlannedTime(), task.getPriority(), task.getUpdatedAt());
    }

    @Transactional
    public QuickRescheduleResponse quickReschedule(UUID actorUserId, UUID taskId, QuickRescheduleRequest request) {
        Task task = sharingAccessService.requireTaskOwner(taskId, actorUserId).task();
        Instant previousPlannedTime = task.getPlannedTime();
        if (previousPlannedTime == null) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "validation_error",
                    "Task planned time must be set before quick reschedule."
            );
        }

        Instant newPlannedTime = previousPlannedTime.plus(resolveDuration(request));
        Instant now = Instant.now();
        int priorityBefore = task.getPriority();

        applyTaskUpdate(task, newPlannedTime, now);
        TaskRescheduleEvent event = taskRescheduleEventRepository.save(
                buildEvent(task, actorUserId, previousPlannedTime, newPlannedTime, priorityBefore, now)
        );
        taskRepository.save(task);

        return new QuickRescheduleResponse(
                new RescheduledTaskDto(task.getId(), task.getPlannedTime(), task.getPriority(), task.getUpdatedAt()),
                new RescheduleEventDto(event.getId(), event.getPreviousPlannedTime(), event.getNewPlannedTime(), event.getCreatedAt()),
                false
        );
    }

    private void applyTaskUpdate(Task task, Instant plannedTime, Instant updatedAt) {
        task.setPlannedTime(plannedTime);
        task.setUpdatedAt(updatedAt);
    }

    private boolean shouldRecordReschedule(Instant previousPlannedTime, Instant newPlannedTime) {
        return previousPlannedTime != null && newPlannedTime != null && newPlannedTime.isAfter(previousPlannedTime);
    }

    private TaskRescheduleEvent buildEvent(
            Task task,
            UUID actorUserId,
            Instant previousPlannedTime,
            Instant newPlannedTime,
            int priorityBefore,
            Instant now
    ) {
        TaskRescheduleEvent event = new TaskRescheduleEvent();
        event.setId(UUID.randomUUID());
        event.setTaskId(task.getId());
        event.setRescheduledByUserId(actorUserId);
        event.setPreviousPlannedTime(previousPlannedTime);
        event.setNewPlannedTime(newPlannedTime);
        event.setReason(null);
        event.setPriorityBefore(priorityBefore);
        event.setPriorityAfter(priorityBefore);
        event.setPriorityDecayApplied(false);
        event.setCreatedAt(now);
        return event;
    }

    private Duration resolveDuration(QuickRescheduleRequest request) {
        boolean hasPreset = request.preset() != null && !request.preset().isBlank();
        boolean hasMinutes = request.minutes() != null;
        if (hasPreset == hasMinutes) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "validation_error",
                    "Quick reschedule requires exactly one supported preset or minutes value."
            );
        }

        if (hasPreset) {
            Duration duration = PRESET_DURATIONS.get(request.preset());
            if (duration == null) {
                throw unsupportedPreset();
            }
            return duration;
        }

        Duration duration = switch (request.minutes()) {
            case 30 -> PRESET_DURATIONS.get("30m");
            case 60 -> PRESET_DURATIONS.get("1h");
            case 180 -> PRESET_DURATIONS.get("3h");
            case 1440 -> PRESET_DURATIONS.get("24h");
            default -> null;
        };
        if (duration == null) {
            throw unsupportedPreset();
        }
        return duration;
    }

    private ApiException unsupportedPreset() {
        return new ApiException(
                HttpStatus.BAD_REQUEST,
                "validation_error",
                "Quick reschedule supports only 30m, 1h, 3h, or 24h."
        );
    }
}
