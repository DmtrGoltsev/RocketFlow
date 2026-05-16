package com.rocketflow.ideas;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface IdeaRepository extends JpaRepository<Idea, UUID> {

    List<Idea> findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(UUID folderId, UUID ownerUserId);

    long countByFolderIdAndOwnerUserId(UUID folderId, UUID ownerUserId);
}
