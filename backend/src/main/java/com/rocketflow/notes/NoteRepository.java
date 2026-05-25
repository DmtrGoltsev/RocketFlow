package com.rocketflow.notes;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface NoteRepository extends JpaRepository<Note, UUID> {

    List<Note> findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(UUID folderId, UUID ownerUserId);

    List<Note> findByFolderIdIn(Collection<UUID> folderIds);

    Optional<Note> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    long countByFolderIdAndOwnerUserId(UUID folderId, UUID ownerUserId);
}
