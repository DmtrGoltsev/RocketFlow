package com.rocketflow.notifications;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;

class ReminderNotificationSchedulerTest {

    @Test
    void skipsWhenSchedulerDisabled() {
        NotificationDeliveryService deliveryService = org.mockito.Mockito.mock(NotificationDeliveryService.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<JdbcTemplate> jdbcTemplateProvider = org.mockito.Mockito.mock(ObjectProvider.class);
        NotificationProperties properties = new NotificationProperties();
        ReminderNotificationScheduler scheduler = new ReminderNotificationScheduler(
                deliveryService,
                properties,
                jdbcTemplateProvider
        );

        scheduler.pollDueReminders();

        verify(deliveryService, never()).processDueReminders(any());
    }

    @Test
    void skipsWhenJdbcTemplateIsUnavailable() {
        NotificationDeliveryService deliveryService = org.mockito.Mockito.mock(NotificationDeliveryService.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<JdbcTemplate> jdbcTemplateProvider = org.mockito.Mockito.mock(ObjectProvider.class);
        NotificationProperties properties = new NotificationProperties();
        properties.getScheduler().setEnabled(true);
        when(jdbcTemplateProvider.getIfAvailable()).thenReturn(null);
        ReminderNotificationScheduler scheduler = new ReminderNotificationScheduler(
                deliveryService,
                properties,
                jdbcTemplateProvider
        );

        scheduler.pollDueReminders();

        verify(deliveryService, never()).processDueReminders(any());
    }

    @Test
    void skipsWhenAdvisoryLockIsNotAcquired() {
        NotificationDeliveryService deliveryService = org.mockito.Mockito.mock(NotificationDeliveryService.class);
        JdbcTemplate jdbcTemplate = org.mockito.Mockito.mock(JdbcTemplate.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<JdbcTemplate> jdbcTemplateProvider = org.mockito.Mockito.mock(ObjectProvider.class);
        NotificationProperties properties = new NotificationProperties();
        properties.getScheduler().setEnabled(true);
        when(jdbcTemplateProvider.getIfAvailable()).thenReturn(jdbcTemplate);
        when(jdbcTemplate.queryForObject(
                "select pg_try_advisory_xact_lock(?)",
                Boolean.class,
                properties.getScheduler().getAdvisoryLockKey()
        )).thenReturn(Boolean.FALSE);
        ReminderNotificationScheduler scheduler = new ReminderNotificationScheduler(
                deliveryService,
                properties,
                jdbcTemplateProvider
        );

        scheduler.pollDueReminders();

        verify(deliveryService, never()).processDueReminders(any());
    }

    @Test
    void processesWhenAdvisoryLockIsAcquired() {
        NotificationDeliveryService deliveryService = org.mockito.Mockito.mock(NotificationDeliveryService.class);
        JdbcTemplate jdbcTemplate = org.mockito.Mockito.mock(JdbcTemplate.class);
        @SuppressWarnings("unchecked")
        ObjectProvider<JdbcTemplate> jdbcTemplateProvider = org.mockito.Mockito.mock(ObjectProvider.class);
        NotificationProperties properties = new NotificationProperties();
        properties.getScheduler().setEnabled(true);
        when(jdbcTemplateProvider.getIfAvailable()).thenReturn(jdbcTemplate);
        when(jdbcTemplate.queryForObject(
                "select pg_try_advisory_xact_lock(?)",
                Boolean.class,
                properties.getScheduler().getAdvisoryLockKey()
        )).thenReturn(Boolean.TRUE);
        ReminderNotificationScheduler scheduler = new ReminderNotificationScheduler(
                deliveryService,
                properties,
                jdbcTemplateProvider
        );

        scheduler.pollDueReminders();

        verify(deliveryService).processDueReminders(any());
    }
}
