package com.rocketflow.calendar;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "task_reschedule_events")
public class TaskRescheduleEvent {

    @Id
    private UUID id;

    @Column(name = "task_id", nullable = false)
    private UUID taskId;

    @Column(name = "rescheduled_by_user_id", nullable = false)
    private UUID rescheduledByUserId;

    @Column(name = "previous_planned_time", nullable = false)
    private Instant previousPlannedTime;

    @Column(name = "new_planned_time", nullable = false)
    private Instant newPlannedTime;

    @Column(length = 500)
    private String reason;

    @Column(name = "priority_before", nullable = false)
    private int priorityBefore;

    @Column(name = "priority_after", nullable = false)
    private int priorityAfter;

    @Column(name = "priority_decay_applied", nullable = false)
    private boolean priorityDecayApplied;

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

    public UUID getRescheduledByUserId() {
        return rescheduledByUserId;
    }

    public void setRescheduledByUserId(UUID rescheduledByUserId) {
        this.rescheduledByUserId = rescheduledByUserId;
    }

    public Instant getPreviousPlannedTime() {
        return previousPlannedTime;
    }

    public void setPreviousPlannedTime(Instant previousPlannedTime) {
        this.previousPlannedTime = previousPlannedTime;
    }

    public Instant getNewPlannedTime() {
        return newPlannedTime;
    }

    public void setNewPlannedTime(Instant newPlannedTime) {
        this.newPlannedTime = newPlannedTime;
    }

    public String getReason() {
        return reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    public int getPriorityBefore() {
        return priorityBefore;
    }

    public void setPriorityBefore(int priorityBefore) {
        this.priorityBefore = priorityBefore;
    }

    public int getPriorityAfter() {
        return priorityAfter;
    }

    public void setPriorityAfter(int priorityAfter) {
        this.priorityAfter = priorityAfter;
    }

    public boolean isPriorityDecayApplied() {
        return priorityDecayApplied;
    }

    public void setPriorityDecayApplied(boolean priorityDecayApplied) {
        this.priorityDecayApplied = priorityDecayApplied;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
