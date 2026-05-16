package com.rocketflow.ideas;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface FolderNoteItemRepository extends JpaRepository<FolderNoteItem, UUID> {

    List<FolderNoteItem> findByFolderNoteIdOrderByDisplayOrderAscCreatedAtAsc(UUID folderNoteId);

    List<FolderNoteItem> findByFolderNoteIdInOrderByDisplayOrderAscCreatedAtAsc(Collection<UUID> folderNoteIds);

    long countByFolderNoteId(UUID folderNoteId);
}
