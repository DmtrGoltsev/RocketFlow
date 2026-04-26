package com.rocketflow.notifications;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.rocketflow.reminders.TaskReminderRule;

public interface ReminderNotificationRuleRepository extends JpaRepository<TaskReminderRule, UUID> {

    List<TaskReminderRule> findByActiveTrueOrderByTaskIdAscSortOrderAsc();
}
