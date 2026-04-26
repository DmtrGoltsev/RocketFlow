package com.rocketflow.notifications;

import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ReminderNotificationScheduler {

    private final NotificationDeliveryService notificationDeliveryService;
    private final boolean schedulerEnabled;

    public ReminderNotificationScheduler(
            NotificationDeliveryService notificationDeliveryService,
            @Value("${rocketflow.notifications.scheduler.enabled:false}") boolean schedulerEnabled
    ) {
        this.notificationDeliveryService = notificationDeliveryService;
        this.schedulerEnabled = schedulerEnabled;
    }

    @Scheduled(
            fixedDelayString = "${rocketflow.notifications.scheduler.fixed-delay:PT1M}",
            initialDelayString = "${rocketflow.notifications.scheduler.initial-delay:PT15S}"
    )
    public void pollDueReminders() {
        if (!schedulerEnabled) {
            return;
        }
        notificationDeliveryService.processDueReminders(Instant.now());
    }
}
