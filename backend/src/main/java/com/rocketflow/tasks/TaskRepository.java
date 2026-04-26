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

    List<Task> findByGoalIdAndOwnerUserIdOrderByCreatedAtAsc(UUID goalId, UUID ownerUserId);

    Optional<Task> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

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
