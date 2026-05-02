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
                .map(goal -> toDto(goal, folderAccess.shared() || sharedGoalIds.contains(goal.getId())))
                .toList());
    }

    @Transactional
    public GoalDto create(UUID ownerUserId, UUID folderId, CreateGoalRequest request) {
        folderService.requireFolder(folderId, ownerUserId);
        Instant now = Instant.now();
        Goal goal = new Goal();
        goal.setId(UUID.randomUUID());
        goal.setFolderId(folderId);
        goal.setOwnerUserId(ownerUserId);
        goal.setName(request.name().trim());
        goal.setDescription(request.description());
        goal.setArchived(false);
        goal.setCreatedAt(now);
        goal.setUpdatedAt(now);
        return toDto(goalRepository.save(goal), false);
    }

    @Transactional(readOnly = true)
    public GoalDto get(UUID actorUserId, UUID goalId) {
        GoalAccess access = sharingAccessService.requireGoalAccess(goalId, actorUserId);
        return toDto(access.goal(), access.shared());
    }

    @Transactional
    public GoalDto update(UUID actorUserId, UUID goalId, UpdateGoalRequest request) {
        GoalAccess access = sharingAccessService.requireGoalOwner(goalId, actorUserId);
        Goal goal = access.goal();
        ensureVersion(goal.getVersion(), request.version(), "Goal");
        goal.setName(request.name().trim());
        goal.setDescription(request.description());
        goal.setArchived(request.archived());
        goal.setUpdatedAt(Instant.now());
        return toDto(goalRepository.save(goal), access.shared());
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID goalId) {
        Goal goal = sharingAccessService.requireGoalOwner(goalId, actorUserId).goal();
        goal.setArchived(true);
        goal.setUpdatedAt(Instant.now());
        goalRepository.save(goal);
    }

    @Transactional(readOnly = true)
    public Goal requireGoalOwner(UUID goalId, UUID ownerUserId) {
        return goalRepository.findByIdAndOwnerUserId(goalId, ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Goal was not found."));
    }

    GoalDto toDto(Goal goal, boolean shared) {
        return new GoalDto(
                goal.getId(),
                goal.getFolderId(),
                goal.getName(),
                goal.getDescription(),
                goal.isArchived(),
                shared,
                goal.getVersion(),
                goal.getCreatedAt(),
                goal.getUpdatedAt()
        );
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }
}
