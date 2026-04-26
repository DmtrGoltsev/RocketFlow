package com.rocketflow.notifications;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationDeliveryRepository extends JpaRepository<NotificationDelivery, UUID> {

    boolean existsByTaskIdAndReminderRuleIdAndScheduledAt(
            UUID taskId,
            UUID reminderRuleId,
            Instant scheduledAt
    );

    boolean existsByTaskIdAndReminderRuleIdAndScheduledAtAndDeviceRegistrationId(
            UUID taskId,
            UUID reminderRuleId,
            Instant scheduledAt,
            UUID deviceRegistrationId
    );

    boolean existsByTaskIdAndReminderRuleIdAndScheduledAtAndDeviceRegistrationIdIsNull(
            UUID taskId,
            UUID reminderRuleId,
            Instant scheduledAt
    );

    List<NotificationDelivery> findAllByOrderByCreatedAtAsc();
}
