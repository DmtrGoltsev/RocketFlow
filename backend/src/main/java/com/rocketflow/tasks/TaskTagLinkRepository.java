package com.rocketflow.tasks;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskTagLinkRepository extends JpaRepository<TaskTagLink, TaskTagLinkId> {

    List<TaskTagLink> findByTaskId(UUID taskId);

    List<TaskTagLink> findByTaskIdIn(List<UUID> taskIds);

    void deleteByTaskId(UUID taskId);
}
