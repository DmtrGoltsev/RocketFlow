package com.rocketflow.tasks;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TaskRepository extends JpaRepository<Task, UUID> {

    List<Task> findByGoalIdAndOwnerUserIdOrderByPriorityDescCreatedAtAscIdAsc(UUID goalId, UUID ownerUserId);

    List<Task> findByGoalIdAndOwnerUserIdAndArchivedFalseOrderByPriorityDescCreatedAtAscIdAsc(UUID goalId, UUID ownerUserId);

    List<Task> findByGoalIdIn(Collection<UUID> goalIds);

    List<Task> findByGoalIdInAndArchivedFalse(Collection<UUID> goalIds);

    Optional<Task> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<Task> findByIdAndOwnerUserIdAndArchivedFalse(UUID id, UUID ownerUserId);

    @Query(value = """
            select task.*
            from tasks task
            where task.owner_user_id = :ownerUserId
              and task.archived = false
              and task.deleted_at is null
              and (task.planned_time is not null or task.due_time is not null)
            """, nativeQuery = true)
    List<Task> findCalendarCandidatesForOwner(@Param("ownerUserId") UUID ownerUserId);

    @Query(value = """
            select task.*
            from tasks task
            where task.goal_id in (:goalIds)
              and task.archived = false
              and task.deleted_at is null
              and (task.planned_time is not null or task.due_time is not null)
            """, nativeQuery = true)
    List<Task> findCalendarCandidatesByGoalIds(@Param("goalIds") Collection<UUID> goalIds);

    @Query(value = """
            select task.*
            from tasks task
            where task.id in (:taskIds)
              and task.archived = false
              and task.deleted_at is null
              and (task.planned_time is not null or task.due_time is not null)
            """, nativeQuery = true)
    List<Task> findCalendarCandidatesByIds(@Param("taskIds") Collection<UUID> taskIds);

    @Query("""
            select task
            from Task task
            where task.ownerUserId = :ownerUserId
              and task.archived = false
              and task.plannedTime is not null
              and task.plannedTime >= :from
              and task.plannedTime <= :to
            order by task.plannedTime asc, task.priority desc, task.createdAt asc
            """)
    List<Task> findCalendarTasksForOwner(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("from") Instant from,
            @Param("to") Instant to
    );

    @Query("""
            select task
            from Task task
            where task.goalId in :goalIds
              and task.archived = false
              and task.plannedTime is not null
              and task.plannedTime >= :from
              and task.plannedTime <= :to
            order by task.plannedTime asc, task.priority desc, task.createdAt asc
            """)
    List<Task> findCalendarTasksByGoalIds(
            @Param("goalIds") Collection<UUID> goalIds,
            @Param("from") Instant from,
            @Param("to") Instant to
    );

    @Query("""
            select task
            from Task task
            where task.id in :taskIds
              and task.archived = false
              and task.plannedTime is not null
              and task.plannedTime >= :from
              and task.plannedTime <= :to
            order by task.plannedTime asc, task.priority desc, task.createdAt asc
            """)
    List<Task> findCalendarTasksByIds(
            @Param("taskIds") Collection<UUID> taskIds,
            @Param("from") Instant from,
            @Param("to") Instant to
    );
}
