package com.rocketflow.sharing;

import static com.rocketflow.sharing.SharingValues.*;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.folders.Folder;
import com.rocketflow.folders.FolderRepository;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class SharingAccessService {

    private final GoalRepository goalRepository;
    private final TaskRepository taskRepository;
    private final FolderRepository folderRepository;
    private final FolderShareRepository folderShareRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;

    public SharingAccessService(
            GoalRepository goalRepository,
            TaskRepository taskRepository,
            FolderRepository folderRepository,
            FolderShareRepository folderShareRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository
    ) {
        this.goalRepository = goalRepository;
        this.taskRepository = taskRepository;
        this.folderRepository = folderRepository;
        this.folderShareRepository = folderShareRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderAccess(UUID folderId, UUID actorUserId) {
        Folder folder = folderRepository.findById(folderId)
                .orElseThrow(() -> notFound("Folder"));
        if (folder.getOwnerUserId().equals(actorUserId)) {
            return new FolderAccess(folder, true, hasActiveFolderShares(folderId), true);
        }
        Optional<FolderShare> inheritedShare = findInheritedFolderShare(folder, actorUserId);
        if (inheritedShare.isPresent()) {
            return new FolderAccess(folder, false, true, inheritedShare.get().isFullAccess());
        }
        throw notFound("Folder");
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderContentAccess(UUID folderId, UUID actorUserId) {
        return requireFolderAccess(folderId, actorUserId);
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderOwner(UUID folderId, UUID actorUserId) {
        Folder folder = folderRepository.findById(folderId)
                .orElseThrow(() -> notFound("Folder"));
        if (!folder.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Folder");
        }
        return new FolderAccess(folder, true, hasActiveFolderShares(folderId), true);
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderContentOwner(UUID folderId, UUID actorUserId) {
        return requireFolderOwner(folderId, actorUserId);
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderFullAccess(UUID folderId, UUID actorUserId) {
        FolderAccess access = requireFolderAccess(folderId, actorUserId);
        if (!access.fullAccess()) {
            throw notFound("Folder");
        }
        return access;
    }

    @Transactional(readOnly = true)
    public GoalAccess requireGoalAccess(UUID goalId, UUID actorUserId) {
        Goal goal = goalRepository.findById(goalId)
                .orElseThrow(() -> notFound("Goal"));
        if (goal.getOwnerUserId().equals(actorUserId)) {
            return new GoalAccess(goal, true, hasActiveFolderShares(goal.getFolderId()) || hasActiveGoalShares(goalId), true);
        }

        Optional<FolderShare> folderShare = findInheritedFolderShare(goal.getFolderId(), actorUserId);
        if (folderShare.isPresent()) {
            return new GoalAccess(goal, false, true, folderShare.get().isFullAccess());
        }
        Optional<GoalShare> goalShare = goalShareRepository.findByGoalIdAndCollaboratorUserIdAndStatus(goalId, actorUserId, SHARE_ACTIVE);
        if (goalShare.isPresent()) {
            return new GoalAccess(goal, false, true, goalShare.get().isFullAccess());
        }
        throw notFound("Goal");
    }

    @Transactional(readOnly = true)
    public GoalAccess requireGoalOwner(UUID goalId, UUID actorUserId) {
        Goal goal = goalRepository.findById(goalId)
                .orElseThrow(() -> notFound("Goal"));
        if (!goal.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Goal");
        }
        return new GoalAccess(goal, true, hasActiveFolderShares(goal.getFolderId()) || hasActiveGoalShares(goalId), true);
    }

    @Transactional(readOnly = true)
    public GoalAccess requireGoalFullAccess(UUID goalId, UUID actorUserId) {
        GoalAccess access = requireGoalAccess(goalId, actorUserId);
        if (!access.fullAccess()) {
            throw notFound("Goal");
        }
        return access;
    }

    @Transactional(readOnly = true)
    public GoalAccess requireGoalTaskCreateAccess(UUID goalId, UUID actorUserId) {
        Goal goal = goalRepository.findById(goalId)
                .orElseThrow(() -> notFound("Goal"));
        if (goal.getOwnerUserId().equals(actorUserId)) {
            return new GoalAccess(goal, true, hasActiveFolderShares(goal.getFolderId()) || hasActiveGoalShares(goalId), true);
        }
        Optional<FolderShare> folderShare = findInheritedFolderShare(goal.getFolderId(), actorUserId);
        if (folderShare.isPresent()) {
            return new GoalAccess(goal, false, true, folderShare.get().isFullAccess());
        }
        Optional<GoalShare> goalShare = goalShareRepository.findByGoalIdAndCollaboratorUserIdAndStatus(goalId, actorUserId, SHARE_ACTIVE);
        if (goalShare.isPresent()) {
            return new GoalAccess(goal, false, true, goalShare.get().isFullAccess());
        }
        throw notFound("Goal");
    }

    @Transactional(readOnly = true)
    public TaskAccess requireTaskAccess(UUID taskId, UUID actorUserId) {
        Task task = taskRepository.findById(taskId)
                .orElseThrow(() -> notFound("Task"));
        Goal goal = goalRepository.findById(task.getGoalId())
                .orElseThrow(() -> notFound("Goal"));
        if (task.getOwnerUserId().equals(actorUserId)) {
            return new TaskAccess(
                    task,
                    true,
                    hasActiveFolderShares(goal.getFolderId()) || hasActiveGoalShares(task.getGoalId()) || hasActiveTaskShares(taskId),
                    true
            );
        }

        Optional<FolderShare> folderShare = findInheritedFolderShare(goal.getFolderId(), actorUserId);
        if (folderShare.isPresent()) {
            return new TaskAccess(task, false, true, folderShare.get().isFullAccess());
        }
        Optional<GoalShare> goalShare = goalShareRepository.findByGoalIdAndCollaboratorUserIdAndStatus(task.getGoalId(), actorUserId, SHARE_ACTIVE);
        if (goalShare.isPresent()) {
            return new TaskAccess(task, false, true, goalShare.get().isFullAccess());
        }
        Optional<TaskShare> taskShare = taskShareRepository.findByTaskIdAndCollaboratorUserIdAndStatus(taskId, actorUserId, SHARE_ACTIVE);
        if (taskShare.isPresent()) {
            return new TaskAccess(task, false, true, taskShare.get().isFullAccess());
        }
        throw notFound("Task");
    }

    @Transactional(readOnly = true)
    public TaskAccess requireTaskOwner(UUID taskId, UUID actorUserId) {
        Task task = taskRepository.findById(taskId)
                .orElseThrow(() -> notFound("Task"));
        if (!task.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Task");
        }
        Goal goal = goalRepository.findById(task.getGoalId())
                .orElseThrow(() -> notFound("Goal"));
        return new TaskAccess(
                task,
                true,
                hasActiveFolderShares(goal.getFolderId()) || hasActiveGoalShares(task.getGoalId()) || hasActiveTaskShares(taskId),
                true
        );
    }

    @Transactional(readOnly = true)
    public TaskAccess requireTaskFullAccess(UUID taskId, UUID actorUserId) {
        TaskAccess access = requireTaskAccess(taskId, actorUserId);
        if (!access.fullAccess()) {
            throw notFound("Task");
        }
        return access;
    }

    @Transactional(readOnly = true)
    public List<FolderAccess> accessibleSharedFolders(UUID actorUserId) {
        Map<UUID, FolderAccess> result = new LinkedHashMap<>();
        for (FolderShare share : folderShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE)) {
            Folder root = folderRepository.findById(share.getFolderId()).orElse(null);
            if (root == null) {
                continue;
            }
            for (Folder folder : folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(root.getOwnerUserId())) {
                if (isSameOrDescendant(folder, root.getId())) {
                    result.putIfAbsent(folder.getId(), new FolderAccess(folder, false, true, share.isFullAccess()));
                }
            }
        }
        return new ArrayList<>(result.values());
    }

    @Transactional(readOnly = true)
    public Set<UUID> findSharedFolderIds(Collection<UUID> folderIds) {
        if (folderIds == null || folderIds.isEmpty()) {
            return Set.of();
        }
        return new LinkedHashSet<>(folderShareRepository.findFolderIdsByFolderIdInAndStatus(folderIds, SHARE_ACTIVE));
    }

    @Transactional(readOnly = true)
    public Set<UUID> findSharedGoalIds(Collection<UUID> goalIds) {
        if (goalIds == null || goalIds.isEmpty()) {
            return Set.of();
        }
        return new LinkedHashSet<>(goalShareRepository.findGoalIdsByGoalIdInAndStatus(goalIds, SHARE_ACTIVE));
    }

    @Transactional(readOnly = true)
    public Set<UUID> findSharedTaskIds(Collection<UUID> taskIds) {
        if (taskIds == null || taskIds.isEmpty()) {
            return Set.of();
        }
        return new LinkedHashSet<>(taskShareRepository.findTaskIdsByTaskIdInAndStatus(taskIds, SHARE_ACTIVE));
    }

    @Transactional(readOnly = true)
    public boolean hasActiveGoalShares(UUID goalId) {
        return goalShareRepository.countByGoalIdAndStatus(goalId, SHARE_ACTIVE) > 0;
    }

    @Transactional(readOnly = true)
    public boolean hasActiveFolderShares(UUID folderId) {
        return folderShareRepository.countByFolderIdAndStatus(folderId, SHARE_ACTIVE) > 0;
    }

    @Transactional(readOnly = true)
    public boolean hasActiveTaskShares(UUID taskId) {
        return taskShareRepository.countByTaskIdAndStatus(taskId, SHARE_ACTIVE) > 0;
    }

    private Optional<FolderShare> findInheritedFolderShare(UUID folderId, UUID actorUserId) {
        Folder folder = folderRepository.findById(folderId).orElse(null);
        if (folder == null) {
            return Optional.empty();
        }
        return findInheritedFolderShare(folder, actorUserId);
    }

    private Optional<FolderShare> findInheritedFolderShare(Folder folder, UUID actorUserId) {
        UUID currentId = folder.getId();
        while (currentId != null) {
            Optional<FolderShare> share = folderShareRepository.findByFolderIdAndCollaboratorUserIdAndStatus(
                    currentId,
                    actorUserId,
                    SHARE_ACTIVE
            );
            if (share.isPresent()) {
                return share;
            }
            currentId = folderRepository.findById(currentId)
                    .map(Folder::getParentFolderId)
                    .orElse(null);
        }
        return Optional.empty();
    }

    private boolean isSameOrDescendant(Folder folder, UUID ancestorFolderId) {
        UUID currentId = folder.getId();
        while (currentId != null) {
            if (currentId.equals(ancestorFolderId)) {
                return true;
            }
            currentId = folderRepository.findById(currentId)
                    .map(Folder::getParentFolderId)
                    .orElse(null);
        }
        return false;
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }

    public record GoalAccess(Goal goal, boolean owner, boolean shared, boolean fullAccess) {
    }

    public record TaskAccess(Task task, boolean owner, boolean shared, boolean fullAccess) {
    }

    public record FolderAccess(Folder folder, boolean owner, boolean shared, boolean fullAccess) {
    }
}
