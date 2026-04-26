package com.rocketflow.goals;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface GoalRepository extends JpaRepository<Goal, UUID> {

    List<Goal> findByFolderIdAndOwnerUserIdOrderByCreatedAtAsc(UUID folderId, UUID ownerUserId);

    Optional<Goal> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);
}
