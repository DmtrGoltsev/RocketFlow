package com.rocketflow.reminders;

import java.time.Instant;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.rocketflow.common.ApiException;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TasksApi.UpsertReminderRequest;

@Service
public class ReminderEligibilityService {

    public void validate(Task task, List<UpsertReminderRequest> reminders) {
        Set<String> seenKeys = new HashSet<>();
        for (UpsertReminderRequest reminder : reminders) {
            if (!List.of("before_planned_time", "before_due_time").contains(reminder.mode())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Reminder mode is not supported.");
            }
            if ("before_planned_time".equals(reminder.mode()) && task.getPlannedTime() == null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                        "Reminder mode before_planned_time requires plannedTime.");
            }
            if ("before_due_time".equals(reminder.mode()) && task.getDueTime() == null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                        "Reminder mode before_due_time requires dueTime.");
            }
            String key = reminder.mode() + ":" + reminder.offsetMinutes();
            if (!seenKeys.add(key)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                        "Duplicate reminders are not allowed for the same mode and offset.");
            }
        }
    }

    public Optional<Instant> calculateEligibleAt(Task task, TaskReminderRule reminder, ZoneId ownerZone) {
        Instant anchor = switch (reminder.getMode()) {
            case "before_planned_time" -> task.getPlannedTime();
            case "before_due_time" -> task.getDueTime();
            default -> null;
        };
        if (anchor == null) {
            return Optional.empty();
        }
        return Optional.of(anchor.atZone(ownerZone).minusMinutes(reminder.getOffsetMinutes()).toInstant());
    }
}
