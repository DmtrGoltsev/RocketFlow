package com.rocketflow.notifications;

import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@ConditionalOnProperty(prefix = "rocketflow.notifications.scheduler", name = "enabled", havingValue = "true")
public class ReminderNotificationScheduler {

    private static final Logger log = LoggerFactory.getLogger(ReminderNotificationScheduler.class);

    private final NotificationDeliveryService notificationDeliveryService;
    private final NotificationProperties properties;
    private final ObjectProvider<JdbcTemplate> jdbcTemplateProvider;

    public ReminderNotificationScheduler(
            NotificationDeliveryService notificationDeliveryService,
            NotificationProperties properties,
            ObjectProvider<JdbcTemplate> jdbcTemplateProvider
    ) {
        this.notificationDeliveryService = notificationDeliveryService;
        this.properties = properties;
        this.jdbcTemplateProvider = jdbcTemplateProvider;
    }

    @Transactional
    @Scheduled(
            fixedDelayString = "${rocketflow.notifications.scheduler.fixed-delay:PT1M}",
            initialDelayString = "${rocketflow.notifications.scheduler.initial-delay:PT15S}"
    )
    public void pollDueReminders() {
        if (!properties.getScheduler().isEnabled()) {
            return;
        }

        if (!tryAcquireDeliveryLock()) {
            log.debug("Skipping reminder delivery poll because another scheduler run holds the advisory lock.");
            return;
        }
        notificationDeliveryService.processDueReminders(Instant.now());
    }

    private boolean tryAcquireDeliveryLock() {
        JdbcTemplate jdbcTemplate = jdbcTemplateProvider.getIfAvailable();
        if (jdbcTemplate == null) {
            log.debug("Skipping reminder delivery poll because JdbcTemplate is not available in this context.");
            return false;
        }
        Boolean acquired = jdbcTemplate.queryForObject(
                "select pg_try_advisory_xact_lock(?)",
                Boolean.class,
                properties.getScheduler().getAdvisoryLockKey()
        );
        return Boolean.TRUE.equals(acquired);
    }
}
