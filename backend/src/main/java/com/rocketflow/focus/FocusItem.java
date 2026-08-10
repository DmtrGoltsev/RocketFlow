package com.rocketflow.focus;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "weekly_focus_items")
class FocusItem {
    @Id private UUID id;
    @Column(name = "period_id", nullable = false) private UUID periodId;
    @Column(name = "task_id", nullable = false) private UUID taskId;
    @Column(nullable = false) private int position;
    @Column(name = "history_only", nullable = false) private boolean historyOnly;
    @Column(name = "snapshot_title", nullable = false) private String title;
    @Column(name = "snapshot_status", nullable = false) private String status;
    @Column(name = "snapshot_effort") private Integer effort;
    @Column(name = "snapshot_effective_weight", nullable = false) private int effectiveWeight;
    @Column(name = "snapshot_planned_time") private Instant plannedTime;
    @Column(name = "snapshot_due_time") private Instant dueTime;
    @Column(name = "snapshot_folder_id") private UUID folderId;
    @Column(name = "snapshot_folder_title") private String folderTitle;
    @Column(name = "snapshot_goal_id") private UUID goalId;
    @Column(name = "snapshot_goal_title") private String goalTitle;
    @Column(name = "snapshot_shared", nullable = false) private boolean shared;
    @Column(name = "snapshot_can_write", nullable = false) private boolean canWrite;
    @Column(name = "snapshot_at", nullable = false) private Instant snapshotAt;
    @Column(name = "added_at", nullable = false) private Instant addedAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;
    @Version private long version;

    UUID getId() { return id; }
    void setId(UUID id) { this.id = id; }
    UUID getPeriodId() { return periodId; }
    void setPeriodId(UUID periodId) { this.periodId = periodId; }
    UUID getTaskId() { return taskId; }
    void setTaskId(UUID taskId) { this.taskId = taskId; }
    int getPosition() { return position; }
    void setPosition(int position) { this.position = position; }
    boolean isHistoryOnly() { return historyOnly; }
    void setHistoryOnly(boolean historyOnly) { this.historyOnly = historyOnly; }
    String getTitle() { return title; }
    void setTitle(String title) { this.title = title; }
    String getStatus() { return status; }
    void setStatus(String status) { this.status = status; }
    Integer getEffort() { return effort; }
    void setEffort(Integer effort) { this.effort = effort; }
    int getEffectiveWeight() { return effectiveWeight; }
    void setEffectiveWeight(int effectiveWeight) { this.effectiveWeight = effectiveWeight; }
    Instant getPlannedTime() { return plannedTime; }
    void setPlannedTime(Instant plannedTime) { this.plannedTime = plannedTime; }
    Instant getDueTime() { return dueTime; }
    void setDueTime(Instant dueTime) { this.dueTime = dueTime; }
    UUID getFolderId() { return folderId; }
    void setFolderId(UUID folderId) { this.folderId = folderId; }
    String getFolderTitle() { return folderTitle; }
    void setFolderTitle(String folderTitle) { this.folderTitle = folderTitle; }
    UUID getGoalId() { return goalId; }
    void setGoalId(UUID goalId) { this.goalId = goalId; }
    String getGoalTitle() { return goalTitle; }
    void setGoalTitle(String goalTitle) { this.goalTitle = goalTitle; }
    boolean isShared() { return shared; }
    void setShared(boolean shared) { this.shared = shared; }
    boolean isCanWrite() { return canWrite; }
    void setCanWrite(boolean canWrite) { this.canWrite = canWrite; }
    void setSnapshotAt(Instant snapshotAt) { this.snapshotAt = snapshotAt; }
    void setAddedAt(Instant addedAt) { this.addedAt = addedAt; }
    void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
