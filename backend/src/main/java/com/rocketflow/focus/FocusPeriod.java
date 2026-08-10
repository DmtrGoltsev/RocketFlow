package com.rocketflow.focus;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "weekly_focus_periods")
class FocusPeriod {
    @Id private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Column(name = "week_start", nullable = false) private LocalDate weekStart;
    @Column(name = "week_end_exclusive", nullable = false) private LocalDate weekEndExclusive;
    @Column(name = "starts_at", nullable = false) private Instant startsAt;
    @Column(name = "ends_at", nullable = false) private Instant endsAt;
    @Column(name = "timezone_snapshot", nullable = false, length = 64) private String timezoneSnapshot;
    @Column(nullable = false, length = 16) private String status;
    @Column(name = "previous_period_id") private UUID previousPeriodId;
    @Column(name = "rollover_resolved_at") private Instant rolloverResolvedAt;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;
    @Version private long version;

    UUID getId() { return id; }
    void setId(UUID id) { this.id = id; }
    UUID getUserId() { return userId; }
    void setUserId(UUID userId) { this.userId = userId; }
    LocalDate getWeekStart() { return weekStart; }
    void setWeekStart(LocalDate weekStart) { this.weekStart = weekStart; }
    LocalDate getWeekEndExclusive() { return weekEndExclusive; }
    void setWeekEndExclusive(LocalDate value) { this.weekEndExclusive = value; }
    Instant getStartsAt() { return startsAt; }
    void setStartsAt(Instant startsAt) { this.startsAt = startsAt; }
    Instant getEndsAt() { return endsAt; }
    void setEndsAt(Instant endsAt) { this.endsAt = endsAt; }
    String getTimezoneSnapshot() { return timezoneSnapshot; }
    void setTimezoneSnapshot(String timezoneSnapshot) { this.timezoneSnapshot = timezoneSnapshot; }
    String getStatus() { return status; }
    void setStatus(String status) { this.status = status; }
    UUID getPreviousPeriodId() { return previousPeriodId; }
    void setPreviousPeriodId(UUID previousPeriodId) { this.previousPeriodId = previousPeriodId; }
    Instant getRolloverResolvedAt() { return rolloverResolvedAt; }
    void setRolloverResolvedAt(Instant rolloverResolvedAt) { this.rolloverResolvedAt = rolloverResolvedAt; }
    Instant getCreatedAt() { return createdAt; }
    void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    long getVersion() { return version; }
}
