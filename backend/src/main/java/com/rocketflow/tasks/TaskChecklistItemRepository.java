package com.rocketflow.tasks;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskChecklistItemRepository extends JpaRepository<TaskChecklistItem, UUID> {

    List<TaskChecklistItem> findByTaskIdOrderByDisplayOrderAscCreatedAtAscIdAsc(UUID taskId);

    List<TaskChecklistItem> findByTaskIdInOrderByDisplayOrderAscCreatedAtAscIdAsc(Collection<UUID> taskIds);

    void deleteByTaskId(UUID taskId);
}
