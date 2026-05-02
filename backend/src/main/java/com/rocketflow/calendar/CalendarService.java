package com.rocketflow.calendar;

import static com.rocketflow.calendar.CalendarApi.*;
import static com.rocketflow.sharing.SharingValues.SHARE_ACTIVE;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.sharing.FolderShare;
import com.rocketflow.sharing.FolderShareRepository;
import com.rocketflow.sharing.GoalShare;
import com.rocketflow.sharing.GoalShareRepository;
import com.rocketflow.sharing.TaskShare;
import com.rocketflow.sharing.TaskShareRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class CalendarService {

    private static final Comparator<Task> CALENDAR_ORDER = Comparator
            .comparing(Task::getPlannedTime)
            .thenComparing(Comparator.comparingInt(Task::getPriority).reversed())
            .thenComparing(Task::getCreatedAt);

    private final TaskRepository taskRepository;
    private final GoalRepository goalRepository;
    private final FolderShareRepository folderShareRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;

    public CalendarService(
            TaskRepository taskRepository,
            GoalRepository goalRepository,
            FolderShareRepository folderShareRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository
    ) {
        this.taskRepository = taskRepository;
        this.goalRepository = goalRepository;
        this.folderShareRepository = folderShareRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
    }

    @Transactional(readOnly = true)
    public CalendarResponse getCalendar(UUID actorUserId, Instant from, Instant to) {
        validateRange(from, to);

        List<Task> visibleTasks = new ArrayList<>(taskRepository.findCalendarTasksForOwner(actorUserId, from, to));

        List<UUID> sharedFolderIds = folderShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE)
                .stream()
                .map(FolderShare::getFolderId)
                .distinct()
                .toList();
        List<UUID> folderSharedGoalIds = sharedFolderIds.isEmpty() ? List.of() : goalRepository.findByFolderIdIn(sharedFolderIds)
                .stream()
                .map(Goal::getId)
                .toList();
        if (!folderSharedGoalIds.isEmpty()) {
            visibleTasks.addAll(taskRepository.findCalendarTasksByGoalIds(folderSharedGoalIds, from, to));
        }

        List<UUID> sharedGoalIds = goalShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE)
                .stream()
                .map(GoalShare::getGoalId)
                .toList();
        if (!sharedGoalIds.isEmpty()) {
            visibleTasks.addAll(taskRepository.findCalendarTasksByGoalIds(sharedGoalIds, from, to));
        }

        List<UUID> sharedTaskIds = taskShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE)
                .stream()
                .map(TaskShare::getTaskId)
                .toList();
        if (!sharedTaskIds.isEmpty()) {
            visibleTasks.addAll(taskRepository.findCalendarTasksByIds(sharedTaskIds, from, to));
        }

        Map<UUID, Task> deduplicated = new LinkedHashMap<>();
        for (Task task : visibleTasks) {
            deduplicated.putIfAbsent(task.getId(), task);
        }

        return new CalendarResponse(deduplicated.values().stream()
                .sorted(CALENDAR_ORDER)
                .map(this::toDto)
                .toList());
    }

    private CalendarItemDto toDto(Task task) {
        return new CalendarItemDto(
                task.getId(),
                task.getGoalId(),
                task.getTitle(),
                task.getType(),
                task.getPriority(),
                task.getStatus(),
                task.getPlannedTime(),
                task.getDueTime()
        );
    }

    private void validateRange(Instant from, Instant to) {
        if (from == null || to == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Calendar range requires from and to.");
        }
        if (from.isAfter(to)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Calendar range is invalid.");
        }
    }
}
