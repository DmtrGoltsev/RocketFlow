package com.rocketflow.links;

import static com.rocketflow.links.LinksApi.*;

import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.folders.Folder;
import com.rocketflow.folders.FolderRepository;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.ideas.Idea;
import com.rocketflow.ideas.IdeaService;
import com.rocketflow.notes.Note;
import com.rocketflow.notes.NoteService;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class EntityLinkService {

    public static final String TYPE_GOAL = "goal";
    public static final String TYPE_TASK = "task";
    public static final String TYPE_IDEA = "idea";
    public static final String TYPE_NOTE = "note";
    public static final String RELATION_RELATED = "related";
    public static final String RELATION_DEPENDENCY = "dependency";

    private final EntityLinkRepository entityLinkRepository;
    private final SharingAccessService sharingAccessService;
    private final IdeaService ideaService;
    private final NoteService noteService;
    private final GoalRepository goalRepository;
    private final TaskRepository taskRepository;
    private final FolderRepository folderRepository;
    private final UserRepository userRepository;

    public EntityLinkService(
            EntityLinkRepository entityLinkRepository,
            SharingAccessService sharingAccessService,
            IdeaService ideaService,
            NoteService noteService,
            GoalRepository goalRepository,
            TaskRepository taskRepository,
            FolderRepository folderRepository,
            UserRepository userRepository
    ) {
        this.entityLinkRepository = entityLinkRepository;
        this.sharingAccessService = sharingAccessService;
        this.ideaService = ideaService;
        this.noteService = noteService;
        this.goalRepository = goalRepository;
        this.taskRepository = taskRepository;
        this.folderRepository = folderRepository;
        this.userRepository = userRepository;
    }

    @Transactional(readOnly = true)
    public EntityLinkListResponse list(UUID actorUserId, String entityType, UUID entityId) {
        EntityRefData requested = resolveAccess(entityType, entityId, actorUserId);
        List<EntityLinkDto> items = entityLinkRepository.findActiveForEntity(requested.type(), requested.id())
                .stream()
                .map(link -> toDtoIfVisible(link, actorUserId))
                .filter(dto -> dto != null)
                .toList();
        return new EntityLinkListResponse(items);
    }

    @Transactional
    public EntityLinkDto create(UUID actorUserId, CreateEntityLinkRequest request) {
        EntityRefData source = resolveFullAccess(request.sourceType(), request.sourceId(), actorUserId);
        EntityRefData target = resolveAccess(request.targetType(), request.targetId(), actorUserId);
        validateRelation(source, target, request.relationType());
        ensureNoDuplicate(source, target, request.relationType());
        if (RELATION_DEPENDENCY.equals(request.relationType())) {
            ensureNoDependencyCycle(source.id(), target.id());
        }

        Instant now = Instant.now();
        EntityLink link = new EntityLink();
        link.setId(UUID.randomUUID());
        link.setOwnerUserId(source.ownerUserId());
        link.setSourceType(source.type());
        link.setSourceId(source.id());
        link.setTargetType(target.type());
        link.setTargetId(target.id());
        link.setRelationType(request.relationType());
        link.setCreatedByUserId(actorUserId);
        link.setArchived(false);
        link.setCreatedAt(now);
        link.setUpdatedAt(now);
        return toDto(entityLinkRepository.save(link), source.ref(), target.ref());
    }

    @Transactional
    public EntityLinkDto update(UUID actorUserId, UUID linkId, UpdateEntityLinkRequest request) {
        EntityLink link = entityLinkRepository.findById(linkId).orElseThrow(() -> notFound("Entity link"));
        EntityRefData source = resolveFullAccess(link.getSourceType(), link.getSourceId(), actorUserId);
        EntityRefData target = resolveAccess(link.getTargetType(), link.getTargetId(), actorUserId);
        ensureVersion(link.getVersion(), request.version(), "Entity link");
        validateRelation(source, target, request.relationType());
        if (!link.getRelationType().equals(request.relationType())) {
            ensureNoDuplicate(source, target, request.relationType());
            if (RELATION_DEPENDENCY.equals(request.relationType())) {
                ensureNoDependencyCycle(source.id(), target.id());
            }
        }
        link.setRelationType(request.relationType());
        link.setUpdatedAt(Instant.now());
        return toDto(entityLinkRepository.save(link), source.ref(), target.ref());
    }

    @Transactional
    public void delete(UUID actorUserId, UUID linkId) {
        EntityLink link = entityLinkRepository.findById(linkId).orElseThrow(() -> notFound("Entity link"));
        resolveFullAccess(link.getSourceType(), link.getSourceId(), actorUserId);
        link.setArchived(true);
        link.setUpdatedAt(Instant.now());
        entityLinkRepository.save(link);
    }

    @Transactional(readOnly = true)
    public void ensureTaskCanBeDone(UUID taskId) {
        List<Task> blockers = entityLinkRepository.findByRelationTypeAndSourceTypeAndSourceIdAndArchivedFalse(
                        RELATION_DEPENDENCY,
                        TYPE_TASK,
                        taskId
                )
                .stream()
                .map(link -> taskRepository.findById(link.getTargetId()).orElse(null))
                .filter(task -> task != null && !task.isArchived() && !"done".equals(task.getStatus()))
                .toList();
        if (!blockers.isEmpty()) {
            String blockerNames = blockers.stream().map(Task::getTitle).toList().toString();
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "dependency_blocked",
                    "Task cannot be completed before blocking tasks are done: " + blockerNames
            );
        }
    }

    private EntityLinkDto toDtoIfVisible(EntityLink link, UUID actorUserId) {
        try {
            EntityRefData source = resolveAccess(link.getSourceType(), link.getSourceId(), actorUserId);
            EntityRefData target = resolveAccess(link.getTargetType(), link.getTargetId(), actorUserId);
            return toDto(link, source.ref(), target.ref());
        } catch (ApiException exception) {
            return null;
        }
    }

    private EntityLinkDto toDto(EntityLink link, EntityRefDto source, EntityRefDto target) {
        String createdByName = userRepository.findById(link.getCreatedByUserId())
                .map(user -> user.getDisplayName())
                .orElse(null);
        return new EntityLinkDto(
                link.getId(),
                source,
                target,
                link.getRelationType(),
                link.getCreatedByUserId(),
                createdByName,
                link.getCreatedAt(),
                link.getUpdatedAt(),
                link.getVersion()
        );
    }

    private void validateRelation(EntityRefData source, EntityRefData target, String relationType) {
        if (source.type().equals(target.type()) && source.id().equals(target.id())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "An entity cannot link to itself.");
        }
        if (RELATION_DEPENDENCY.equals(relationType) && (!TYPE_TASK.equals(source.type()) || !TYPE_TASK.equals(target.type()))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Dependencies are allowed only between tasks.");
        }
    }

    private void ensureNoDuplicate(EntityRefData source, EntityRefData target, String relationType) {
        boolean exact = entityLinkRepository
                .findBySourceTypeAndSourceIdAndTargetTypeAndTargetIdAndRelationTypeAndArchivedFalse(
                        source.type(),
                        source.id(),
                        target.type(),
                        target.id(),
                        relationType
                )
                .isPresent();
        boolean reverseRelated = RELATION_RELATED.equals(relationType) && entityLinkRepository
                .findBySourceTypeAndSourceIdAndTargetTypeAndTargetIdAndRelationTypeAndArchivedFalse(
                        target.type(),
                        target.id(),
                        source.type(),
                        source.id(),
                        relationType
                )
                .isPresent();
        if (exact || reverseRelated) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "This link already exists.");
        }
    }

    private void ensureNoDependencyCycle(UUID sourceTaskId, UUID targetTaskId) {
        if (pathExists(targetTaskId, sourceTaskId, new HashSet<>())) {
            throw new ApiException(HttpStatus.CONFLICT, "dependency_cycle", "Task dependency would create a cycle.");
        }
    }

    private boolean pathExists(UUID currentTaskId, UUID targetTaskId, Set<UUID> visited) {
        if (!visited.add(currentTaskId)) {
            return false;
        }
        if (currentTaskId.equals(targetTaskId)) {
            return true;
        }
        for (EntityLink link : entityLinkRepository.findByRelationTypeAndSourceTypeAndSourceIdAndArchivedFalse(
                RELATION_DEPENDENCY,
                TYPE_TASK,
                currentTaskId
        )) {
            if (pathExists(link.getTargetId(), targetTaskId, visited)) {
                return true;
            }
        }
        return false;
    }

    private EntityRefData resolveFullAccess(String entityType, UUID entityId, UUID actorUserId) {
        return switch (entityType) {
            case TYPE_GOAL -> fromGoal(sharingAccessService.requireGoalFullAccess(entityId, actorUserId).goal());
            case TYPE_TASK -> fromTask(sharingAccessService.requireTaskFullAccess(entityId, actorUserId).task());
            case TYPE_IDEA -> fromIdea(ideaService.requireIdeaFullAccess(entityId, actorUserId).idea());
            case TYPE_NOTE -> fromNote(noteService.requireNoteFullAccess(entityId, actorUserId).note());
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Unsupported entity type.");
        };
    }

    private EntityRefData resolveAccess(String entityType, UUID entityId, UUID actorUserId) {
        return switch (entityType) {
            case TYPE_GOAL -> fromGoal(sharingAccessService.requireGoalAccess(entityId, actorUserId).goal());
            case TYPE_TASK -> fromTask(sharingAccessService.requireTaskAccess(entityId, actorUserId).task());
            case TYPE_IDEA -> fromIdea(ideaService.requireIdeaAccess(entityId, actorUserId).idea());
            case TYPE_NOTE -> fromNote(noteService.requireNoteAccess(entityId, actorUserId).note());
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Unsupported entity type.");
        };
    }

    private EntityRefData fromGoal(Goal goal) {
        Folder folder = folderRepository.findById(goal.getFolderId()).orElse(null);
        String path = folder == null ? goal.getName() : folder.getName() + " / " + goal.getName();
        return new EntityRefData(
                TYPE_GOAL,
                goal.getId(),
                goal.getOwnerUserId(),
                new EntityRefDto(TYPE_GOAL, goal.getId(), goal.getName(), goal.getDescription(), goal.getStatus(), path, goal.isArchived())
        );
    }

    private EntityRefData fromTask(Task task) {
        Goal goal = goalRepository.findById(task.getGoalId()).orElse(null);
        Folder folder = goal == null ? null : folderRepository.findById(goal.getFolderId()).orElse(null);
        String path = goal == null
                ? task.getTitle()
                : (folder == null ? goal.getName() : folder.getName() + " / " + goal.getName());
        return new EntityRefData(
                TYPE_TASK,
                task.getId(),
                task.getOwnerUserId(),
                new EntityRefDto(TYPE_TASK, task.getId(), task.getTitle(), task.getDescription(), task.getStatus(), path, task.isArchived())
        );
    }

    private EntityRefData fromIdea(Idea idea) {
        Folder folder = folderRepository.findById(idea.getFolderId()).orElse(null);
        String path = folder == null ? idea.getTitle() : folder.getName() + " / " + idea.getTitle();
        return new EntityRefData(
                TYPE_IDEA,
                idea.getId(),
                idea.getOwnerUserId(),
                new EntityRefDto(TYPE_IDEA, idea.getId(), idea.getTitle(), idea.getBody(), idea.getStatus(), path, idea.isArchived())
        );
    }

    private EntityRefData fromNote(Note note) {
        Folder folder = folderRepository.findById(note.getFolderId()).orElse(null);
        String path = folder == null ? note.getTitle() : folder.getName() + " / " + note.getTitle();
        return new EntityRefData(
                TYPE_NOTE,
                note.getId(),
                note.getOwnerUserId(),
                new EntityRefDto(TYPE_NOTE, note.getId(), note.getTitle(), note.getBody(), null, path, note.isArchived())
        );
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }

    private record EntityRefData(String type, UUID id, UUID ownerUserId, EntityRefDto ref) {
    }
}
