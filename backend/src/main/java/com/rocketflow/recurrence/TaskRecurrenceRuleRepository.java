package com.rocketflow.recurrence;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskRecurrenceRuleRepository extends JpaRepository<TaskRecurrenceRule, UUID> {

    Optional<TaskRecurrenceRule> findByTaskId(UUID taskId);

    List<TaskRecurrenceRule> findByTaskIdIn(List<UUID> taskIds);
}
