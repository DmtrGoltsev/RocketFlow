package com.rocketflow.sharing;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FolderShareRepository extends JpaRepository<FolderShare, UUID> {

    boolean existsByFolderIdAndCollaboratorUserIdAndStatus(UUID folderId, UUID collaboratorUserId, String status);

    Optional<FolderShare> findByFolderIdAndCollaboratorUserIdAndStatus(UUID folderId, UUID collaboratorUserId, String status);

    long countByFolderIdAndStatus(UUID folderId, String status);

    Optional<FolderShare> findByInvitationId(UUID invitationId);

    Optional<FolderShare> findByLinkIdAndCollaboratorUserIdAndStatus(UUID linkId, UUID collaboratorUserId, String status);

    List<FolderShare> findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(UUID collaboratorUserId, String status);

    @Query("""
            select distinct share.folderId
            from FolderShare share
            where share.folderId in :folderIds
              and share.status = :status
            """)
    List<UUID> findFolderIdsByFolderIdInAndStatus(@Param("folderIds") Collection<UUID> folderIds, @Param("status") String status);
}
