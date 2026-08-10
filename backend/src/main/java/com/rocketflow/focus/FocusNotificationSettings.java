package com.rocketflow.focus;

import java.time.Instant;
import java.time.LocalTime;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "focus_notification_settings")
class FocusNotificationSettings {
    @Id @Column(name = "user_id") private UUID userId;
    @Column(name = "interval_minutes") private Integer intervalMinutes;
    @Column(name = "quiet_hours_start") private LocalTime quietHoursStart;
    @Column(name = "quiet_hours_end") private LocalTime quietHoursEnd;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;
    @Version private long version;

    UUID getUserId() { return userId; }
    void setUserId(UUID userId) { this.userId = userId; }
    Integer getIntervalMinutes() { return intervalMinutes; }
    void setIntervalMinutes(Integer intervalMinutes) { this.intervalMinutes = intervalMinutes; }
    LocalTime getQuietHoursStart() { return quietHoursStart; }
    void setQuietHoursStart(LocalTime quietHoursStart) { this.quietHoursStart = quietHoursStart; }
    LocalTime getQuietHoursEnd() { return quietHoursEnd; }
    void setQuietHoursEnd(LocalTime quietHoursEnd) { this.quietHoursEnd = quietHoursEnd; }
    void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    long getVersion() { return version; }
}
