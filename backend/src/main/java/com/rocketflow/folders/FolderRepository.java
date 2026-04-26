package com.rocketflow.folders;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface FolderRepository extends JpaRepository<Folder, UUID> {

    List<Folder> findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(UUID ownerUserId);

    Optional<Folder> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    long countByOwnerUserId(UUID ownerUserId);
}
