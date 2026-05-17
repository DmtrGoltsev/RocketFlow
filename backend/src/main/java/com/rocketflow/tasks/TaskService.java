package com.rocketflow.tasks;

import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.recurrence.RecurrenceService;
import com.rocketflow.reminders.ReminderService;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.GoalAccess;
import com.rocketflow.sharing.SharingAccessService.TaskAccess;

@Service
public class TaskService {

    private final TaskRepository taskRepository;
    private final UserRepository userRepository;
    private final SharingAccessService sharingAccessService;
    private final TaskTagRepository taskTagRepository;
    private final TaskTagLinkRepository taskTagLinkRepository;
    private final RecurrenceService recurrenceService;
    private final ReminderService reminderService;

    public TaskService(
            TaskRepository taskRepository,
            UserRepository userRepository,
            SharingAccessService sharingAccessService,
            TaskTagRepository taskTagRepository,
            TaskTagLinkRepository taskTagLinkRepository,
            RecurrenceService recurrenceService,
            ReminderService reminderService
    ) {
        this.taskRepository = taskRepository;
        this.userRepository = userRepository;
        this.sharingAccessService = sharingAccessService;
        this.taskTagRepository = taskTagRepository;
        this.taskTagLinkRepository = taskTagLinkRepository;
        this.recurrenceService = recurrenceService;
        this.reminderService = reminderService;
    }

    @Transactional(readOnly = true)
    public TaskListResponse list(UUID actorUserId, UUID goalId) {
        GoalAccess goalAccess = sharingAccessService.requireGoalAccess(goalId, actorUserId);
        List<Task> tasks = taskRepository.findByGoalIdAndOwnerUserIdOrderByCreatedAtAsc(goalId, goalAccess.goal().getOwnerUserId());
        List<UUID> taskIds = tasks.stream().map(Task::getId).toList();
        Set<UUID> directlySharedTaskIds = sharingAccessService.findSharedTaskIds(taskIds);
        Map<UUID, List<TagDto>> tagsByTaskId = resolveTags(taskIds);
        Map<UUID, RecurrenceDto> recurrenceByTaskId = recurrenceService.findDtos(taskIds);

        return new TaskListResponse(tasks.stream()
                .map(task -> toDto(
                        task,
                        tagsByTaskId.getOrDefault(task.getId(), List.of()),
                        goalAccess.shared() || directlySharedTaskIds.contains(task.getId()),
                        recurrenceByTaskId.get(task.getId())))
                .toList());
    }

    @Transactional
    public TaskDto create(UUID actorUserId, UUID goalId, CreateTaskRequest request) {
        GoalAccess goalAccess = sharingAccessService.requireGoalTaskCreateAccess(goalId, actorUserId);
        Instant now = Instant.now();
        Task task = new Task();
        task.setId(UUID.randomUUID());
        task.setGoalId(goalAccess.goal().getId());
        task.setOwnerUserId(goalAccess.goal().getOwnerUserId());
        task.setCreatorUserId(actorUserId);
        task.setTitle(request.title().trim());
        task.setDescription(request.description());
        task.setType(request.type());
        task.setPriority(request.priority());
        task.setStatus(request.status());
        task.setPlannedTime(request.plannedTime());
        task.setDueTime(request.dueTime());
        task.setCompletedAt(resolveCompletedAt(request.status(), null));
        task.setArchived(false);
        task.setCreatedAt(now);
        task.setUpdatedAt(now);
        Task saved = taskRepository.save(task);
        replaceTags(saved.getId(), saved.getOwnerUserId(), request.tagIds());
        return toDto(
                saved,
                resolveTags(saved.getId()),
                goalAccess.shared(),
                recurrenceService.findDto(saved.getId()));
    }

    @Transactional(readOnly = true)
    public TaskDto get(UUID actorUserId, UUID taskId) {
        TaskAccess access = sharingAccessService.requireTaskAccess(taskId, actorUserId);
        return toDto(
                access.task(),
                resolveTags(access.task().getId()),
                access.shared(),
                recurrenceService.findDto(access.task().getId()));
    }

    @Transactional
    public TaskDto update(UUID actorUserId, UUID taskId, UpdateTaskRequest request) {
        TaskAccess access = sharingAccessService.requireTaskAccess(taskId, actorUserId);
        Task task = access.task();
        ensureVersion(task.getVersion(), request.version(), "Task");
        if (!access.owner()) {
            ensureSharedTaskUpdateAllowed(task, request);
            task.setTitle(request.title().trim());
            task.setDescription(request.description());
            task.setType(request.type());
            task.setPriority(request.priority());
            task.setStatus(request.status());
            task.setPlannedTime(request.plannedTime());
            task.setDueTime(request.dueTime());
            task.setCompletedAt(resolveCompletedAt(request.status(), task.getCompletedAt()));
            task.setUpdatedAt(Instant.now());
            task = taskRepository.save(task);
            return toDto(
                    task,
                    resolveTags(task.getId()),
                    access.shared(),
                    recurrenceService.findDto(task.getId()));
        }

        task.setTitle(request.title().trim());
        task.setDescription(request.description());
        task.setType(request.type());
        task.setPriority(request.priority());
        task.setStatus(request.status());
        task.setPlannedTime(request.plannedTime());
        task.setDueTime(request.dueTime());
        task.setCompletedAt(resolveCompletedAt(request.status(), task.getCompletedAt()));
        task.setArchived(request.archived());
        task.setUpdatedAt(Instant.now());
        Task saved = taskRepository.save(task);
        if (request.tagIds() != null) {
            replaceTags(saved.getId(), saved.getOwnerUserId(), request.tagIds());
        }
        return toDto(
                saved,
                resolveTags(saved.getId()),
                access.shared(),
                recurrenceService.findDto(saved.getId()));
    }

    @Transactional
    public TaskRecurrenceResponse upsertRecurrence(UUID actorUserId, UUID taskId, UpsertRecurrenceRequest request) {
        TaskAccess access = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return new TaskRecurrenceResponse(access.task().getId(), recurrenceService.upsert(access.task(), request));
    }

    @Transactional
    public TaskRemindersResponse replaceReminders(UUID actorUserId, UUID taskId, ReplaceRemindersRequest request) {
        TaskAccess access = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return new TaskRemindersResponse(access.task().getId(), reminderService.replace(access.task(), request));
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID taskId) {
        Task task = sharingAccessService.requireTaskOwner(taskId, actorUserId).task();
        task.setArchived(true);
        task.setUpdatedAt(Instant.now());
        taskRepository.save(task);
    }

    @Transactional(readOnly = true)
    public Task requireTaskOwner(UUID taskId, UUID ownerUserId) {
        return sharingAccessService.requireTaskOwner(taskId, ownerUserId).task();
    }

    TaskDto toDto(
            Task task,
            List<TagDto> tags,
            boolean shared,
            RecurrenceDto recurrence
    ) {
        CreatorDetails creator = creatorDetails(task.getCreatorUserId());
        return new TaskDto(
                task.getId(),
                task.getGoalId(),
                task.getTitle(),
                task.getDescription(),
                task.getType(),
                task.getPriority(),
                task.getStatus(),
                task.getPlannedTime(),
                task.getDueTime(),
                task.isArchived(),
                shared,
                task.getCreatorUserId(),
                creator.email(),
                creator.name(),
                task.getVersion(),
                tags,
                recurrence,
                List.of(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }

    private CreatorDetails creatorDetails(UUID creatorUserId) {
        return userRepository.findById(creatorUserId)
                .map(user -> new CreatorDetails(user.getEmail(), user.getDisplayName()))
                .orElse(new CreatorDetails(null, null));
    }

    private record CreatorDetails(String email, String name) {
    }

    private void replaceTags(UUID taskId, UUID ownerUserId, List<UUID> tagIds) {
        taskTagLinkRepository.deleteByTaskId(taskId);
        if (tagIds == null || tagIds.isEmpty()) {
            return;
        }

        List<TaskTag> tags = taskTagRepository.findByOwnerUserIdAndIdIn(ownerUserId, tagIds);
        if (tags.size() != tagIds.size()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "One or more tags are invalid.");
        }

        for (UUID tagId : tagIds) {
            TaskTagLink link = new TaskTagLink();
            link.setTaskId(taskId);
            link.setTagId(tagId);
            taskTagLinkRepository.save(link);
        }
    }

    private List<TagDto> resolveTags(UUID taskId) {
        return resolveTags(List.of(taskId)).getOrDefault(taskId, List.of());
    }

    private Map<UUID, List<TagDto>> resolveTags(List<UUID> taskIds) {
        if (taskIds.isEmpty()) {
            return Map.of();
        }
        List<TaskTagLink> links = taskTagLinkRepository.findByTaskIdIn(taskIds);
        if (links.isEmpty()) {
            return Map.of();
        }
        Map<UUID, TaskTag> tagsById = taskTagRepository.findAllById(links.stream().map(TaskTagLink::getTagId).toList())
                .stream()
                .collect(Collectors.toMap(TaskTag::getId, Function.identity()));

        Map<UUID, List<TagDto>> result = new HashMap<>();
        for (TaskTagLink link : links) {
            TaskTag tag = tagsById.get(link.getTagId());
            if (tag == null) {
                continue;
            }
            result.computeIfAbsent(link.getTaskId(), ignored -> new ArrayList<>())
                    .add(new TagDto(tag.getId(), tag.getName(), tag.getColor()));
        }
        return result;
    }

    private Instant resolveCompletedAt(String status, Instant currentCompletedAt) {
        if ("done".equals(status)) {
            return currentCompletedAt != null ? currentCompletedAt : Instant.now();
        }
        return null;
    }

    private void ensureSharedTaskUpdateAllowed(Task task, UpdateTaskRequest request) {
        if (task.isArchived() != request.archived()) {
            throw notFound("Task");
        }
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }
}
