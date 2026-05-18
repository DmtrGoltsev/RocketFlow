package com.rocketflow.goals;

import static com.rocketflow.goals.GoalsApi.*;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.folders.FolderService;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;
import com.rocketflow.sharing.SharingAccessService.GoalAccess;

@Service
public class GoalService {

    private static final String DEFAULT_GOAL_STATUS = "todo";

    private final GoalRepository goalRepository;
    private final FolderService folderService;
    private final SharingAccessService sharingAccessService;

    public GoalService(GoalRepository goalRepository, FolderService folderService, SharingAccessService sharingAccessService) {
        this.goalRepository = goalRepository;
        this.folderService = folderService;
        this.sharingAccessService = sharingAccessService;
    }

    @Transactional(readOnly = true)
    public GoalListResponse list(UUID actorUserId, UUID folderId) {
        FolderAccess folderAccess = folderService.requireFolderAccess(folderId, actorUserId);
        List<Goal> goals = goalRepository.findByFolderIdAndOwnerUserIdOrderByCreatedAtAsc(
                folderId,
                folderAccess.folder().getOwnerUserId()
        );
        Set<UUID> sharedGoalIds = sharingAccessService.findSharedGoalIds(goals.stream().map(Goal::getId).toList());
        return new GoalListResponse(goals
                .stream()
                .map(goal -> toDto(goal, folderAccess.shared() || sharedGoalIds.contains(goal.getId()), folderAccess.fullAccess()))
                .toList());
    }

    @Transactional
    public GoalDto create(UUID actorUserId, UUID folderId, CreateGoalRequest request) {
        FolderAccess folderAccess = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Instant now = Instant.now();
        Goal goal = new Goal();
        goal.setId(UUID.randomUUID());
        goal.setFolderId(folderAccess.folder().getId());
        goal.setOwnerUserId(folderAccess.folder().getOwnerUserId());
        goal.setName(request.name().trim());
        goal.setDescription(request.description());
        goal.setStatus(resolveStatus(request.status(), DEFAULT_GOAL_STATUS));
        goal.setArchived(false);
        goal.setCreatedAt(now);
        goal.setUpdatedAt(now);
        return toDto(goalRepository.save(goal), folderAccess.shared(), folderAccess.fullAccess());
    }

    @Transactional(readOnly = true)
    public GoalDto get(UUID actorUserId, UUID goalId) {
        GoalAccess access = sharingAccessService.requireGoalAccess(goalId, actorUserId);
        return toDto(access.goal(), access.shared(), access.fullAccess());
    }

    @Transactional
    public GoalDto update(UUID actorUserId, UUID goalId, UpdateGoalRequest request) {
        GoalAccess access = sharingAccessService.requireGoalFullAccess(goalId, actorUserId);
        Goal goal = access.goal();
        ensureVersion(goal.getVersion(), request.version(), "Goal");
        goal.setName(request.name().trim());
        goal.setDescription(request.description());
        goal.setStatus(resolveStatus(request.status(), goal.getStatus()));
        goal.setArchived(request.archived());
        goal.setUpdatedAt(Instant.now());
        return toDto(goalRepository.save(goal), access.shared(), access.fullAccess());
    }

    @Transactional
    public GoalDto move(UUID actorUserId, UUID goalId, MoveGoalRequest request) {
        GoalAccess access = sharingAccessService.requireGoalFullAccess(goalId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Goal goal = access.goal();
        ensureVersion(goal.getVersion(), request.version(), "Goal");
        if (!goal.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Goal cannot be moved across owners.");
        }
        goal.setFolderId(targetAccess.folder().getId());
        goal.setUpdatedAt(Instant.now());
        return toDto(goalRepository.save(goal), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional
    public GoalDto clone(UUID actorUserId, UUID goalId, CloneGoalRequest request) {
        GoalAccess sourceAccess = sharingAccessService.requireGoalAccess(goalId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Goal source = sourceAccess.goal();
        if (!source.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Goal cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Goal clone = new Goal();
        clone.setId(UUID.randomUUID());
        clone.setFolderId(targetAccess.folder().getId());
        clone.setOwnerUserId(source.getOwnerUserId());
        clone.setName(request.name() == null || request.name().isBlank() ? source.getName() : request.name().trim());
        clone.setDescription(source.getDescription());
        clone.setStatus(source.getStatus());
        clone.setArchived(false);
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        return toDto(goalRepository.save(clone), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID goalId) {
        Goal goal = sharingAccessService.requireGoalFullAccess(goalId, actorUserId).goal();
        goal.setArchived(true);
        goal.setUpdatedAt(Instant.now());
        goalRepository.save(goal);
    }

    @Transactional(readOnly = true)
    public Goal requireGoalOwner(UUID goalId, UUID ownerUserId) {
        return goalRepository.findByIdAndOwnerUserId(goalId, ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Goal was not found."));
    }

    GoalDto toDto(Goal goal, boolean shared, boolean fullAccess) {
        return new GoalDto(
                goal.getId(),
                goal.getFolderId(),
                goal.getName(),
                goal.getDescription(),
                goal.getStatus(),
                goal.isArchived(),
                shared,
                fullAccess,
                goal.getVersion(),
                goal.getCreatedAt(),
                goal.getUpdatedAt()
        );
    }

    private String resolveStatus(String requestedStatus, String fallback) {
        if (requestedStatus == null || requestedStatus.isBlank()) {
            return fallback;
        }
        return requestedStatus.trim();
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }
}
