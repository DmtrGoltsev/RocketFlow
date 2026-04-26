package com.rocketflow.tasks;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskTagRepository extends JpaRepository<TaskTag, UUID> {

    List<TaskTag> findByOwnerUserIdOrderByNameAsc(UUID ownerUserId);

    List<TaskTag> findByOwnerUserIdAndIdIn(UUID ownerUserId, List<UUID> ids);

    Optional<TaskTag> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);
}
