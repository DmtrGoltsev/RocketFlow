package com.rocketflow.tasks;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

@Entity
@Table(name = "task_tag_links")
@IdClass(TaskTagLinkId.class)
public class TaskTagLink {

    @Id
    @Column(name = "task_id")
    private UUID taskId;

    @Id
    @Column(name = "tag_id")
    private UUID tagId;

    public UUID getTaskId() { return taskId; }
    public void setTaskId(UUID taskId) { this.taskId = taskId; }
    public UUID getTagId() { return tagId; }
    public void setTagId(UUID tagId) { this.tagId = tagId; }
}
