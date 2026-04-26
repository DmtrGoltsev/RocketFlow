package com.rocketflow.sharing;

import static com.rocketflow.sharing.SharingValues.*;

import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class SharingAccessService {

    private final GoalRepository goalRepository;
    private final TaskRepository taskRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;

    public SharingAccessService(
            GoalRepository goalRepository,
            TaskRepository taskRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository
    ) {
        this.goalRepository = goalRepository;
        this.taskRepository = taskRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
    }

    @Transactional(readOnly = true)
    public GoalAccess requireGoalAccess(UUID goalId, UUID actorUserId) {
        Goal goal = goalRepository.findById(goalId)
                .orElseThrow(() -> notFound("Goal"));
        if (goal.getOwnerUserId().equals(actorUserId)) {
            return new GoalAccess(goal, true, hasActiveGoalShares(goalId));
        }
        if (goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(goalId, actorUserId, SHARE_ACTIVE)) {
            return new GoalAccess(goal, false, true);
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
        return new GoalAccess(goal, true, hasActiveGoalShares(goalId));
    }

    @Transactional(readOnly = true)
    public TaskAccess requireTaskAccess(UUID taskId, UUID actorUserId) {
        Task task = taskRepository.findById(taskId)
                .orElseThrow(() -> notFound("Task"));
        if (task.getOwnerUserId().equals(actorUserId)) {
            return new TaskAccess(task, true, hasActiveGoalShares(task.getGoalId()) || hasActiveTaskShares(taskId));
        }

        boolean goalAccess = goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(
                task.getGoalId(),
                actorUserId,
                SHARE_ACTIVE
        );
        boolean taskAccess = taskShareRepository.existsByTaskIdAndCollaboratorUserIdAndStatus(
                taskId,
                actorUserId,
                SHARE_ACTIVE
        );
        if (goalAccess || taskAccess) {
            return new TaskAccess(task, false, true);
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
        return new TaskAccess(task, true, hasActiveGoalShares(task.getGoalId()) || hasActiveTaskShares(taskId));
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
    public boolean hasActiveTaskShares(UUID taskId) {
        return taskShareRepository.countByTaskIdAndStatus(taskId, SHARE_ACTIVE) > 0;
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }

    public record GoalAccess(Goal goal, boolean owner, boolean shared) {
    }

    public record TaskAccess(Task task, boolean owner, boolean shared) {
    }
}
