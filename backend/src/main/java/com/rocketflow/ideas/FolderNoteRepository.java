package com.rocketflow.ideas;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface FolderNoteRepository extends JpaRepository<FolderNote, UUID> {

    List<FolderNote> findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(UUID folderId, UUID ownerUserId);

    long countByFolderIdAndOwnerUserId(UUID folderId, UUID ownerUserId);
}
