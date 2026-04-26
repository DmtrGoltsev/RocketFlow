package com.rocketflow.settings;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "user_settings")
public class UserSettings {

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(nullable = false, length = 8)
    private String language;

    @Column(name = "notifications_enabled", nullable = false)
    private boolean notificationsEnabled;

    @Column(name = "green_priority_decay_enabled", nullable = false)
    private boolean greenPriorityDecayEnabled;

    @Column(name = "green_priority_decay_threshold", nullable = false, length = 16)
    private String greenPriorityDecayThreshold;

    @Column(name = "green_priority_decay_amount", nullable = false)
    private int greenPriorityDecayAmount;

    @Column(name = "red_priority_decay_enabled", nullable = false)
    private boolean redPriorityDecayEnabled;

    @Column(name = "red_priority_decay_threshold", nullable = false, length = 16)
    private String redPriorityDecayThreshold;

    @Column(name = "red_priority_decay_amount", nullable = false)
    private int redPriorityDecayAmount;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    private long version;

    public UUID getUserId() {
        return userId;
    }

    public void setUserId(UUID userId) {
        this.userId = userId;
    }

    public String getLanguage() {
        return language;
    }

    public void setLanguage(String language) {
        this.language = language;
    }

    public boolean isNotificationsEnabled() {
        return notificationsEnabled;
    }

    public void setNotificationsEnabled(boolean notificationsEnabled) {
        this.notificationsEnabled = notificationsEnabled;
    }

    public boolean isGreenPriorityDecayEnabled() {
        return greenPriorityDecayEnabled;
    }

    public void setGreenPriorityDecayEnabled(boolean greenPriorityDecayEnabled) {
        this.greenPriorityDecayEnabled = greenPriorityDecayEnabled;
    }

    public String getGreenPriorityDecayThreshold() {
        return greenPriorityDecayThreshold;
    }

    public void setGreenPriorityDecayThreshold(String greenPriorityDecayThreshold) {
        this.greenPriorityDecayThreshold = greenPriorityDecayThreshold;
    }

    public int getGreenPriorityDecayAmount() {
        return greenPriorityDecayAmount;
    }

    public void setGreenPriorityDecayAmount(int greenPriorityDecayAmount) {
        this.greenPriorityDecayAmount = greenPriorityDecayAmount;
    }

    public boolean isRedPriorityDecayEnabled() {
        return redPriorityDecayEnabled;
    }

    public void setRedPriorityDecayEnabled(boolean redPriorityDecayEnabled) {
        this.redPriorityDecayEnabled = redPriorityDecayEnabled;
    }

    public String getRedPriorityDecayThreshold() {
        return redPriorityDecayThreshold;
    }

    public void setRedPriorityDecayThreshold(String redPriorityDecayThreshold) {
        this.redPriorityDecayThreshold = redPriorityDecayThreshold;
    }

    public int getRedPriorityDecayAmount() {
        return redPriorityDecayAmount;
    }

    public void setRedPriorityDecayAmount(int redPriorityDecayAmount) {
        this.redPriorityDecayAmount = redPriorityDecayAmount;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public long getVersion() {
        return version;
    }
}
