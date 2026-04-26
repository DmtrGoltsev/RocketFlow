package com.rocketflow.tasks;

import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

public class TaskTagLinkId implements Serializable {

    private UUID taskId;
    private UUID tagId;

    public TaskTagLinkId() {
    }

    public TaskTagLinkId(UUID taskId, UUID tagId) {
        this.taskId = taskId;
        this.tagId = tagId;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof TaskTagLinkId that)) {
            return false;
        }
        return Objects.equals(taskId, that.taskId) && Objects.equals(tagId, that.tagId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(taskId, tagId);
    }
}
