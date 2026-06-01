package com.rocketflow.goals;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface GoalRepository extends JpaRepository<Goal, UUID> {

    List<Goal> findByFolderIdAndOwnerUserIdOrderByCreatedAtAsc(UUID folderId, UUID ownerUserId);

    List<Goal> findByFolderIdAndOwnerUserIdAndArchivedFalseOrderByCreatedAtAsc(UUID folderId, UUID ownerUserId);

    List<Goal> findByFolderIdIn(Collection<UUID> folderIds);

    List<Goal> findByFolderIdInAndArchivedFalse(Collection<UUID> folderIds);

    Optional<Goal> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<Goal> findByIdAndOwnerUserIdAndArchivedFalse(UUID id, UUID ownerUserId);
}
