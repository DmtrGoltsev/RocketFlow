package com.rocketflow.notifications;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "notification_deliveries")
public class NotificationDelivery {

    @Id
    private UUID id;

    @Column(name = "task_id", nullable = false)
    private UUID taskId;

    @Column(name = "reminder_rule_id", nullable = false)
    private UUID reminderRuleId;

    @Column(name = "device_registration_id")
    private UUID deviceRegistrationId;

    @Column(name = "scheduled_at", nullable = false)
    private Instant scheduledAt;

    @Column(name = "attempted_at")
    private Instant attemptedAt;

    @Column(nullable = false, length = 48)
    private String status;

    @Column(name = "provider_response", length = 2000)
    private String providerResponse;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public UUID getTaskId() {
        return taskId;
    }

    public void setTaskId(UUID taskId) {
        this.taskId = taskId;
    }

    public UUID getReminderRuleId() {
        return reminderRuleId;
    }

    public void setReminderRuleId(UUID reminderRuleId) {
        this.reminderRuleId = reminderRuleId;
    }

    public UUID getDeviceRegistrationId() {
        return deviceRegistrationId;
    }

    public void setDeviceRegistrationId(UUID deviceRegistrationId) {
        this.deviceRegistrationId = deviceRegistrationId;
    }

    public Instant getScheduledAt() {
        return scheduledAt;
    }

    public void setScheduledAt(Instant scheduledAt) {
        this.scheduledAt = scheduledAt;
    }

    public Instant getAttemptedAt() {
        return attemptedAt;
    }

    public void setAttemptedAt(Instant attemptedAt) {
        this.attemptedAt = attemptedAt;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getProviderResponse() {
        return providerResponse;
    }

    public void setProviderResponse(String providerResponse) {
        this.providerResponse = providerResponse;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
