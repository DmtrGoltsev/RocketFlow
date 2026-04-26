package com.rocketflow.notifications;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.rocketflow.reminders.TaskReminderRule;
import com.rocketflow.tasks.Task;

@Component
public class NotificationPayloadFactory {

    public NotificationPayload createTaskReminderPayload(Task task, TaskReminderRule reminderRule, Instant scheduledAt) {
        Map<String, String> data = new LinkedHashMap<>();
        data.put("type", "task_reminder");
        data.put("taskId", task.getId().toString());
        data.put("reminderRuleId", reminderRule.getId().toString());
        data.put("scheduledAt", scheduledAt.toString());

        return new NotificationPayload(
                "RocketFlow reminder",
                task.getTitle(),
                Map.copyOf(data)
        );
    }
}
