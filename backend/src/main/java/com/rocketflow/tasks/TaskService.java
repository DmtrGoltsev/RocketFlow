package com.rocketflow.tasks;

import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.links.EntityLinkCleanupService;
import com.rocketflow.links.EntityLinkService;
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
    private final TaskChecklistItemRepository taskChecklistItemRepository;
    private final RecurrenceService recurrenceService;
    private final ReminderService reminderService;
    private final EntityLinkService entityLinkService;
    private final EntityLinkCleanupService entityLinkCleanupService;

    public TaskService(
            TaskRepository taskRepository,
            UserRepository userRepository,
            SharingAccessService sharingAccessService,
            TaskTagRepository taskTagRepository,
            TaskTagLinkRepository taskTagLinkRepository,
            TaskChecklistItemRepository taskChecklistItemRepository,
            RecurrenceService recurrenceService,
            ReminderService reminderService,
            EntityLinkService entityLinkService,
            EntityLinkCleanupService entityLinkCleanupService
    ) {
        this.taskRepository = taskRepository;
        this.userRepository = userRepository;
        this.sharingAccessService = sharingAccessService;
        this.taskTagRepository = taskTagRepository;
        this.taskTagLinkRepository = taskTagLinkRepository;
        this.taskChecklistItemRepository = taskChecklistItemRepository;
        this.recurrenceService = recurrenceService;
        this.reminderService = reminderService;
        this.entityLinkService = entityLinkService;
        this.entityLinkCleanupService = entityLinkCleanupService;
    }

    @Transactional(readOnly = true)
    public TaskListResponse list(UUID actorUserId, UUID goalId) {
        GoalAccess goalAccess = sharingAccessService.requireGoalAccess(goalId, actorUserId);
        List<Task> tasks = taskRepository.findByGoalIdAndOwnerUserIdOrderByPriorityDescCreatedAtAscIdAsc(goalId, goalAccess.goal().getOwnerUserId());
        List<UUID> taskIds = tasks.stream().map(Task::getId).toList();
        Set<UUID> directlySharedTaskIds = sharingAccessService.findSharedTaskIds(taskIds);
        Map<UUID, List<TagDto>> tagsByTaskId = resolveTags(taskIds);
        Map<UUID, List<ChecklistItemDto>> checklistByTaskId = resolveChecklistItems(taskIds);
        Map<UUID, RecurrenceDto> recurrenceByTaskId = recurrenceService.findDtos(taskIds);

        return new TaskListResponse(tasks.stream()
                .map(task -> toDto(
                        task,
                        tagsByTaskId.getOrDefault(task.getId(), List.of()),
                        checklistByTaskId.getOrDefault(task.getId(), List.of()),
                        goalAccess.shared() || directlySharedTaskIds.contains(task.getId()),
                        goalAccess.fullAccess(),
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
        task.setEffort(normalizeEffort(request.effort()));
        task.setStatus(request.status());
        task.setPlannedTime(request.plannedTime());
        task.setDueTime(request.dueTime());
        task.setCompletedAt(resolveCompletedAt(request.status(), null));
        task.setArchived(false);
        task.setCreatedAt(now);
        task.setUpdatedAt(now);
        Task saved = taskRepository.save(task);
        replaceTags(saved.getId(), saved.getOwnerUserId(), request.tagIds());
        if (request.checklistItems() != null) {
            replaceChecklistItems(saved, request.checklistItems(), false);
        }
        return toDto(
                saved,
                resolveTags(saved.getId()),
                resolveChecklistItems(saved.getId()),
                goalAccess.shared(),
                goalAccess.fullAccess(),
                recurrenceService.findDto(saved.getId()));
    }

    @Transactional(readOnly = true)
    public TaskDto get(UUID actorUserId, UUID taskId) {
        TaskAccess access = sharingAccessService.requireTaskAccess(taskId, actorUserId);
        return toDto(
                access.task(),
                resolveTags(access.task().getId()),
                resolveChecklistItems(access.task().getId()),
                access.shared(),
                access.fullAccess(),
                recurrenceService.findDto(access.task().getId()));
    }

    @Transactional
    public TaskDto update(UUID actorUserId, UUID taskId, UpdateTaskRequest request) {
        TaskAccess access = sharingAccessService.requireTaskAccess(taskId, actorUserId);
        Task task = access.task();
        ensureVersion(task.getVersion(), request.version(), "Task");
        ensureTaskCanUseStatus(task, request.status());
        if (!access.fullAccess()) {
            ensureSharedTaskUpdateAllowed(task, request);
            task.setStatus(request.status());
            task.setCompletedAt(resolveCompletedAt(request.status(), task.getCompletedAt()));
            task.setUpdatedAt(Instant.now());
            task = taskRepository.save(task);
            return toDto(
                    task,
                    resolveTags(task.getId()),
                    resolveChecklistItems(task.getId()),
                    access.shared(),
                    access.fullAccess(),
                    recurrenceService.findDto(task.getId()));
        }

        task.setTitle(request.title().trim());
        task.setDescription(request.description());
        task.setType(request.type());
        task.setPriority(request.priority());
        if (request.effort() != null) {
            task.setEffort(normalizeEffort(request.effort()));
        }
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
        if (request.checklistItems() != null) {
            replaceChecklistItems(saved, request.checklistItems(), false);
        }
        return toDto(
                saved,
                resolveTags(saved.getId()),
                resolveChecklistItems(saved.getId()),
                access.shared(),
                access.fullAccess(),
                recurrenceService.findDto(saved.getId()));
    }

    @Transactional
    public TaskDto moveToGoal(UUID actorUserId, UUID taskId, MoveTaskToGoalRequest request) {
        TaskAccess access = sharingAccessService.requireTaskFullAccess(taskId, actorUserId);
        GoalAccess targetAccess = sharingAccessService.requireGoalTaskCreateAccess(request.targetGoalId(), actorUserId);
        if (!targetAccess.fullAccess()) {
            throw notFound("Goal");
        }
        Task task = access.task();
        ensureVersion(task.getVersion(), request.version(), "Task");
        if (!task.getOwnerUserId().equals(targetAccess.goal().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Task cannot be moved across owners.");
        }
        task.setGoalId(targetAccess.goal().getId());
        task.setUpdatedAt(Instant.now());
        Task saved = taskRepository.save(task);
        return toDto(saved, resolveTags(saved.getId()), resolveChecklistItems(saved.getId()), targetAccess.shared(), targetAccess.fullAccess(), recurrenceService.findDto(saved.getId()));
    }

    @Transactional
    public TaskDto clone(UUID actorUserId, UUID taskId, CloneTaskRequest request) {
        TaskAccess sourceAccess = sharingAccessService.requireTaskAccess(taskId, actorUserId);
        GoalAccess targetAccess = sharingAccessService.requireGoalTaskCreateAccess(request.targetGoalId(), actorUserId);
        if (!targetAccess.fullAccess()) {
            throw notFound("Goal");
        }
        Task source = sourceAccess.task();
        if (!source.getOwnerUserId().equals(targetAccess.goal().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Task cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Task clone = new Task();
        clone.setId(UUID.randomUUID());
        clone.setGoalId(targetAccess.goal().getId());
        clone.setOwnerUserId(source.getOwnerUserId());
        clone.setCreatorUserId(actorUserId);
        clone.setTitle(request.title() == null || request.title().isBlank() ? source.getTitle() : request.title().trim());
        clone.setDescription(source.getDescription());
        clone.setType(source.getType());
        clone.setPriority(source.getPriority());
        clone.setEffort(source.getEffort());
        clone.setStatus(source.getStatus());
        clone.setPlannedTime(source.getPlannedTime());
        clone.setDueTime(source.getDueTime());
        clone.setCompletedAt(resolveCompletedAt(source.getStatus(), null));
        clone.setArchived(false);
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        Task saved = taskRepository.save(clone);
        if (Boolean.TRUE.equals(request.includeTags())) {
            replaceTags(saved.getId(), saved.getOwnerUserId(), taskTagLinkRepository.findByTaskId(source.getId())
                    .stream()
                    .map(TaskTagLink::getTagId)
                    .toList());
        }
        List<ChecklistItemRequest> sourceChecklistItems = taskChecklistItemRepository.findByTaskIdOrderByDisplayOrderAscCreatedAtAscIdAsc(source.getId())
                .stream()
                .map(item -> new ChecklistItemRequest(null, item.getText(), item.isChecked(), item.getDisplayOrder()))
                .toList();
        if (!sourceChecklistItems.isEmpty()) {
            replaceChecklistItems(saved, sourceChecklistItems, false);
        }
        return toDto(saved, resolveTags(saved.getId()), resolveChecklistItems(saved.getId()), targetAccess.shared(), targetAccess.fullAccess(), recurrenceService.findDto(saved.getId()));
    }

    @Transactional
    public TaskChecklistResponse replaceChecklist(UUID actorUserId, UUID taskId, ReplaceChecklistRequest request) {
        Task task = sharingAccessService.requireTaskFullAccess(taskId, actorUserId).task();
        return new TaskChecklistResponse(task.getId(), replaceChecklistItems(task, request.items(), true));
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
        Task task = sharingAccessService.requireTaskFullAccess(taskId, actorUserId).task();
        task.setArchived(true);
        task.setUpdatedAt(Instant.now());
        taskRepository.save(task);
        entityLinkCleanupService.archiveLinksForEntity(EntityLinkService.TYPE_TASK, task.getId());
    }

    @Transactional(readOnly = true)
    public Task requireTaskOwner(UUID taskId, UUID ownerUserId) {
        return sharingAccessService.requireTaskOwner(taskId, ownerUserId).task();
    }

    TaskDto toDto(
            Task task,
            List<TagDto> tags,
            List<ChecklistItemDto> checklistItems,
            boolean shared,
            boolean fullAccess,
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
                task.getEffort(),
                task.getStatus(),
                task.getPlannedTime(),
                task.getDueTime(),
                task.isArchived(),
                shared,
                fullAccess,
                task.getCreatorUserId(),
                creator.email(),
                creator.name(),
                task.getVersion(),
                tags,
                checklistItems,
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

    private List<ChecklistItemDto> resolveChecklistItems(UUID taskId) {
        return resolveChecklistItems(List.of(taskId)).getOrDefault(taskId, List.of());
    }

    Map<UUID, List<ChecklistItemDto>> resolveChecklistItems(List<UUID> taskIds) {
        if (taskIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, List<ChecklistItemDto>> result = new HashMap<>();
        for (TaskChecklistItem item : taskChecklistItemRepository.findByTaskIdInOrderByDisplayOrderAscCreatedAtAscIdAsc(taskIds)) {
            result.computeIfAbsent(item.getTaskId(), ignored -> new ArrayList<>())
                    .add(toChecklistDto(item));
        }
        return result;
    }

    private List<ChecklistItemDto> replaceChecklistItems(Task task, List<ChecklistItemRequest> requestedItems, boolean touchTask) {
        List<TaskChecklistItem> existingItems = taskChecklistItemRepository.findByTaskIdOrderByDisplayOrderAscCreatedAtAscIdAsc(task.getId());
        Map<UUID, TaskChecklistItem> existingById = existingItems.stream()
                .collect(Collectors.toMap(TaskChecklistItem::getId, Function.identity()));
        if (requestedItems == null || requestedItems.isEmpty()) {
            taskChecklistItemRepository.deleteAll(existingItems);
            if (touchTask) {
                task.setUpdatedAt(Instant.now());
                taskRepository.save(task);
            }
            return List.of();
        }

        Instant now = Instant.now();
        List<TaskChecklistItem> savedItems = new ArrayList<>();
        List<UUID> retainedIds = new ArrayList<>();
        for (ChecklistItemRequest requestedItem : requestedItems) {
            TaskChecklistItem existing = requestedItem.id() == null ? null : existingById.get(requestedItem.id());
            TaskChecklistItem item = existing == null ? new TaskChecklistItem() : existing;
            if (existing == null) {
                item.setId(UUID.randomUUID());
                item.setCreatedAt(now);
            }
            item.setTaskId(task.getId());
            item.setText(requestedItem.text().trim());
            item.setChecked(Boolean.TRUE.equals(requestedItem.checked()));
            item.setDisplayOrder(requestedItem.displayOrder());
            item.setUpdatedAt(now);
            TaskChecklistItem saved = taskChecklistItemRepository.save(item);
            savedItems.add(saved);
            retainedIds.add(saved.getId());
        }
        for (TaskChecklistItem existingItem : existingItems) {
            if (!retainedIds.contains(existingItem.getId())) {
                taskChecklistItemRepository.delete(existingItem);
            }
        }
        if (touchTask) {
            task.setUpdatedAt(now);
            taskRepository.save(task);
        }
        return savedItems.stream()
                .map(this::toChecklistDto)
                .sorted((left, right) -> {
                    int order = Integer.compare(left.displayOrder(), right.displayOrder());
                    if (order != 0) {
                        return order;
                    }
                    int created = left.createdAt().compareTo(right.createdAt());
                    if (created != 0) {
                        return created;
                    }
                    return left.id().compareTo(right.id());
                })
                .toList();
    }

    private ChecklistItemDto toChecklistDto(TaskChecklistItem item) {
        return new ChecklistItemDto(
                item.getId(),
                item.getTaskId(),
                item.getText(),
                item.isChecked(),
                item.getDisplayOrder(),
                item.getVersion(),
                item.getCreatedAt(),
                item.getUpdatedAt()
        );
    }

    private Instant resolveCompletedAt(String status, Instant currentCompletedAt) {
        if ("done".equals(status)) {
            return currentCompletedAt != null ? currentCompletedAt : Instant.now();
        }
        return null;
    }

    private int normalizeEffort(Integer effort) {
        return effort == null ? 0 : effort;
    }

    private void ensureTaskCanUseStatus(Task task, String requestedStatus) {
        if ("done".equals(requestedStatus) && !"done".equals(task.getStatus())) {
            entityLinkService.ensureTaskCanBeDone(task.getId());
        }
    }

    private void ensureSharedTaskUpdateAllowed(Task task, UpdateTaskRequest request) {
        if (!Objects.equals(task.getTitle(), request.title().trim())
                || !Objects.equals(task.getDescription(), request.description())
                || !Objects.equals(task.getType(), request.type())
                || task.getPriority() != request.priority().intValue()
                || (request.effort() != null && task.getEffort() != request.effort().intValue())
                || !Objects.equals(task.getPlannedTime(), request.plannedTime())
                || !Objects.equals(task.getDueTime(), request.dueTime())
                || task.isArchived() != request.archived()
                || !equalTagIds(task.getId(), request.tagIds())) {
            throw notFound("Task");
        }
    }

    private boolean equalTagIds(UUID taskId, List<UUID> requestedTagIds) {
        if (requestedTagIds == null) {
            return true;
        }
        Set<UUID> actualTagIds = taskTagLinkRepository.findByTaskId(taskId).stream()
                .map(TaskTagLink::getTagId)
                .collect(Collectors.toSet());
        Set<UUID> requestedTagIdSet = requestedTagIds.stream()
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        return requestedTagIdSet.size() == requestedTagIds.size() && actualTagIds.equals(requestedTagIdSet);
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
