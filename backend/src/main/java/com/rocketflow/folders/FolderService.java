package com.rocketflow.folders;

import static com.rocketflow.folders.FoldersApi.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.focus.FocusLifecycleService;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.ideas.Idea;
import com.rocketflow.ideas.IdeaRepository;
import com.rocketflow.links.EntityLinkCleanupService;
import com.rocketflow.links.EntityLinkService;
import com.rocketflow.notes.Note;
import com.rocketflow.notes.NoteRepository;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class FolderService {

    private final FolderRepository folderRepository;
    private final SharingAccessService sharingAccessService;
    private final GoalRepository goalRepository;
    private final TaskRepository taskRepository;
    private final IdeaRepository ideaRepository;
    private final NoteRepository noteRepository;
    private final EntityLinkCleanupService entityLinkCleanupService;
    private final FocusLifecycleService focusLifecycleService;

    public FolderService(
            FolderRepository folderRepository,
            SharingAccessService sharingAccessService,
            GoalRepository goalRepository,
            TaskRepository taskRepository,
            IdeaRepository ideaRepository,
            NoteRepository noteRepository,
            EntityLinkCleanupService entityLinkCleanupService,
            FocusLifecycleService focusLifecycleService
    ) {
        this.folderRepository = folderRepository;
        this.sharingAccessService = sharingAccessService;
        this.goalRepository = goalRepository;
        this.taskRepository = taskRepository;
        this.ideaRepository = ideaRepository;
        this.noteRepository = noteRepository;
        this.entityLinkCleanupService = entityLinkCleanupService;
        this.focusLifecycleService = focusLifecycleService;
    }

    @Transactional(readOnly = true)
    public FolderListResponse list(UUID ownerUserId) {
        Map<UUID, FolderDto> folders = new LinkedHashMap<>();
        List<Folder> ownerFolders = folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(ownerUserId);
        Map<UUID, Folder> ownerFoldersById = ownerFolders.stream()
                .collect(java.util.stream.Collectors.toMap(Folder::getId, folder -> folder));
        ownerFolders.stream()
                .filter(folder -> isVisibleInActiveTree(folder, ownerFoldersById))
                .forEach(folder -> folders.put(folder.getId(), toDto(folder, sharingAccessService.hasActiveFolderShares(folder.getId()), true)));
        sharingAccessService.accessibleSharedFolders(ownerUserId)
                .forEach(access -> folders.putIfAbsent(access.folder().getId(), toDto(access.folder(), true, access.fullAccess())));
        List<FolderDto> items = folders.values().stream()
                .sorted(Comparator.comparing(FolderDto::displayOrder).thenComparing(FolderDto::createdAt))
                .toList();
        return new FolderListResponse(items);
    }

    @Transactional(readOnly = true)
    public FolderDto get(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderAccess(folderId, actorUserId);
        return toDto(access.folder(), access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto create(UUID ownerUserId, CreateFolderRequest request) {
        return createInternal(ownerUserId, request.parentFolderId(), request.name(), request.description());
    }

    @Transactional
    public FolderDto createChild(UUID actorUserId, UUID parentFolderId, CreateFolderRequest request) {
        return createInternal(actorUserId, parentFolderId, request.name(), request.description());
    }

    private FolderDto createInternal(UUID actorUserId, UUID parentFolderId, String name, String description) {
        Instant now = Instant.now();
        FolderAccess parentAccess = null;
        UUID ownerUserId = actorUserId;
        if (parentFolderId != null) {
            parentAccess = sharingAccessService.requireFolderFullAccess(parentFolderId, actorUserId);
            ownerUserId = parentAccess.folder().getOwnerUserId();
        }
        Folder folder = new Folder();
        folder.setId(UUID.randomUUID());
        folder.setOwnerUserId(ownerUserId);
        folder.setParentFolderId(parentFolderId);
        folder.setName(name.trim());
        folder.setDescription(description);
        folder.setDisplayOrder(nextDisplayOrder(ownerUserId, parentFolderId));
        folder.setArchived(false);
        folder.setCreatedAt(now);
        folder.setUpdatedAt(now);
        Folder saved = folderRepository.save(folder);
        return toDto(saved, parentAccess != null && parentAccess.shared(), true);
    }

    @Transactional
    public FolderDto update(UUID actorUserId, UUID folderId, UpdateFolderRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Folder folder = access.folder();
        ensureVersion(folder.getVersion(), request.version(), "Folder");
        folder.setName(request.name().trim());
        folder.setDescription(request.description());
        folder.setDisplayOrder(request.displayOrder());
        Instant now = Instant.now();
        boolean archiveRequested = request.archived() && !folder.isArchived();
        folder.setArchived(request.archived());
        folder.setUpdatedAt(now);
        Folder saved = folderRepository.save(folder);
        if (archiveRequested) {
            archiveDescendants(saved, now);
            focusLifecycleService.archiveTasks(descendantTaskIds(saved));
            archiveDescendantEntityLinks(saved);
        }
        return toDto(saved, access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto move(UUID actorUserId, UUID folderId, MoveFolderRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Folder folder = access.folder();
        ensureVersion(folder.getVersion(), request.version(), "Folder");
        if (request.targetFolderId() != null) {
            FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
            if (!targetAccess.folder().getOwnerUserId().equals(folder.getOwnerUserId())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be moved across owners.");
            }
            ensureNotSelfOrDescendant(folder.getId(), request.targetFolderId());
        }
        folder.setParentFolderId(request.targetFolderId());
        folder.setUpdatedAt(Instant.now());
        return toDto(folderRepository.save(folder), access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto clone(UUID actorUserId, UUID folderId, CloneFolderRequest request) {
        FolderAccess sourceAccess = sharingAccessService.requireFolderAccess(folderId, actorUserId);
        FolderAccess targetAccess = request.targetFolderId() == null
                ? null
                : sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        UUID ownerUserId = targetAccess == null ? actorUserId : targetAccess.folder().getOwnerUserId();
        if (!sourceAccess.folder().getOwnerUserId().equals(ownerUserId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Folder clone = new Folder();
        clone.setId(UUID.randomUUID());
        clone.setOwnerUserId(ownerUserId);
        clone.setParentFolderId(request.targetFolderId());
        clone.setName(request.name() == null || request.name().isBlank() ? sourceAccess.folder().getName() : request.name().trim());
        clone.setDescription(sourceAccess.folder().getDescription());
        clone.setDisplayOrder(nextDisplayOrder(ownerUserId, request.targetFolderId()));
        clone.setArchived(false);
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        Folder saved = folderRepository.save(clone);
        return toDto(saved, targetAccess != null && targetAccess.shared(), true);
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID folderId) {
        Folder folder = sharingAccessService.requireFolderFullAccess(folderId, actorUserId).folder();
        Instant now = Instant.now();
        folder.setArchived(true);
        folder.setUpdatedAt(now);
        folderRepository.save(folder);
        archiveDescendants(folder, now);
        List<UUID> taskIds = deleteDescendantTasks(folder, now);
        focusLifecycleService.deleteTasks(taskIds);
        archiveDescendantEntityLinks(folder);
    }

    @Transactional(readOnly = true)
    public Folder requireFolder(UUID folderId, UUID ownerUserId) {
        return folderRepository.findByIdAndOwnerUserIdAndArchivedFalse(folderId, ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Folder was not found."));
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderAccess(UUID folderId, UUID actorUserId) {
        return sharingAccessService.requireFolderAccess(folderId, actorUserId);
    }

    FolderDto toDto(Folder folder, boolean shared, boolean fullAccess) {
        return new FolderDto(
                folder.getId(),
                folder.getParentFolderId(),
                folder.getName(),
                folder.getDescription(),
                folder.getDisplayOrder(),
                folder.isArchived(),
                shared,
                fullAccess,
                folder.getVersion(),
                folder.getCreatedAt(),
                folder.getUpdatedAt()
        );
    }

    private int nextDisplayOrder(UUID ownerUserId, UUID parentFolderId) {
        if (parentFolderId == null) {
            return (int) folderRepository.countByOwnerUserIdAndParentFolderIdIsNull(ownerUserId) + 1;
        }
        return (int) folderRepository.countByOwnerUserIdAndParentFolderId(ownerUserId, parentFolderId) + 1;
    }

    private boolean isVisibleInActiveTree(Folder folder, Map<UUID, Folder> foldersById) {
        Set<UUID> seen = new HashSet<>();
        Folder current = folder;
        while (current != null) {
            if (current.isArchived() || !seen.add(current.getId())) {
                return false;
            }
            UUID parentId = current.getParentFolderId();
            if (parentId == null) {
                return true;
            }
            current = foldersById.get(parentId);
            if (current == null) {
                return false;
            }
        }
        return false;
    }

    private void ensureNotSelfOrDescendant(UUID folderId, UUID targetFolderId) {
        UUID currentId = targetFolderId;
        while (currentId != null) {
            if (currentId.equals(folderId)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be moved into itself or a descendant.");
            }
            currentId = folderRepository.findById(currentId)
                    .map(Folder::getParentFolderId)
                    .orElse(null);
        }
    }

    private void archiveDescendantEntityLinks(Folder folder) {
        List<UUID> folderIds = descendantFolderIds(folder);
        List<Goal> goals = goalRepository.findByFolderIdIn(folderIds);
        List<UUID> goalIds = goals.stream().map(Goal::getId).toList();
        List<UUID> taskIds = goalIds.isEmpty()
                ? List.of()
                : taskRepository.findByGoalIdIn(goalIds).stream().map(Task::getId).toList();
        List<UUID> ideaIds = ideaRepository.findByFolderIdIn(folderIds).stream().map(Idea::getId).toList();
        List<UUID> noteIds = noteRepository.findByFolderIdIn(folderIds).stream().map(Note::getId).toList();

        entityLinkCleanupService.archiveLinksForEntities(Map.of(
                EntityLinkService.TYPE_GOAL, goalIds,
                EntityLinkService.TYPE_TASK, taskIds,
                EntityLinkService.TYPE_IDEA, ideaIds,
                EntityLinkService.TYPE_NOTE, noteIds
        ));
    }

    private void archiveDescendants(Folder folder, Instant now) {
        List<UUID> folderIds = descendantFolderIds(folder);
        List<Folder> folders = folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(folder.getOwnerUserId())
                .stream()
                .filter(candidate -> folderIds.contains(candidate.getId()))
                .toList();
        for (Folder descendant : folders) {
            if (!descendant.isArchived()) {
                descendant.setArchived(true);
                descendant.setUpdatedAt(now);
            }
        }
        folderRepository.saveAll(folders);

        List<Goal> goals = goalRepository.findByFolderIdInAndArchivedFalse(folderIds);
        for (Goal goal : goals) {
            goal.setArchived(true);
            goal.setUpdatedAt(now);
        }
        goalRepository.saveAll(goals);

        List<UUID> goalIds = goals.stream().map(Goal::getId).toList();
        if (!goalIds.isEmpty()) {
            List<Task> tasks = taskRepository.findByGoalIdInAndArchivedFalse(goalIds);
            for (Task task : tasks) {
                task.setArchived(true);
                task.setUpdatedAt(now);
            }
            taskRepository.saveAll(tasks);
        }

        List<Idea> ideas = ideaRepository.findByFolderIdInAndArchivedFalse(folderIds);
        for (Idea idea : ideas) {
            idea.setArchived(true);
            idea.setUpdatedAt(now);
        }
        ideaRepository.saveAll(ideas);

        List<Note> notes = noteRepository.findByFolderIdInAndArchivedFalse(folderIds);
        for (Note note : notes) {
            note.setArchived(true);
            note.setUpdatedAt(now);
        }
        noteRepository.saveAll(notes);
    }

    private List<UUID> descendantTaskIds(Folder folder) {
        List<UUID> goalIds = goalRepository.findByFolderIdIn(descendantFolderIds(folder)).stream()
                .map(Goal::getId)
                .toList();
        if (goalIds.isEmpty()) {
            return List.of();
        }
        return taskRepository.findByGoalIdIn(goalIds).stream().map(Task::getId).toList();
    }

    private List<UUID> deleteDescendantTasks(Folder folder, Instant now) {
        List<UUID> goalIds = goalRepository.findByFolderIdIn(descendantFolderIds(folder)).stream()
                .map(Goal::getId)
                .toList();
        if (goalIds.isEmpty()) {
            return List.of();
        }
        List<Task> tasks = taskRepository.findByGoalIdIn(goalIds);
        for (Task task : tasks) {
            task.setArchived(true);
            task.setDeletedAt(now);
            task.setUpdatedAt(now);
        }
        taskRepository.saveAll(tasks);
        return tasks.stream().map(Task::getId).toList();
    }

    private List<UUID> descendantFolderIds(Folder root) {
        List<Folder> folders = folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(root.getOwnerUserId());
        Map<UUID, List<Folder>> childrenByParentId = new LinkedHashMap<>();
        for (Folder folder : folders) {
            if (folder.getParentFolderId() != null) {
                childrenByParentId.computeIfAbsent(folder.getParentFolderId(), ignored -> new ArrayList<>()).add(folder);
            }
        }

        List<UUID> result = new ArrayList<>();
        Set<UUID> seen = new HashSet<>();
        collectDescendantFolderIds(root.getId(), childrenByParentId, result, seen);
        return result;
    }

    private void collectDescendantFolderIds(
            UUID folderId,
            Map<UUID, List<Folder>> childrenByParentId,
            List<UUID> result,
            Set<UUID> seen
    ) {
        if (!seen.add(folderId)) {
            return;
        }
        result.add(folderId);
        for (Folder child : childrenByParentId.getOrDefault(folderId, List.of())) {
            collectDescendantFolderIds(child.getId(), childrenByParentId, result, seen);
        }
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }
}
