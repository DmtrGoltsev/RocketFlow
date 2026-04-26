package com.rocketflow.reminders;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskReminderRuleRepository extends JpaRepository<TaskReminderRule, UUID> {

    List<TaskReminderRule> findByTaskIdOrderBySortOrderAsc(UUID taskId);

    List<TaskReminderRule> findByTaskIdInOrderByTaskIdAscSortOrderAsc(List<UUID> taskIds);

    void deleteByTaskId(UUID taskId);
}
