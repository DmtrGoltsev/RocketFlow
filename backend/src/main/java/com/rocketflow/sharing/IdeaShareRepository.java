package com.rocketflow.sharing;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface IdeaShareRepository extends JpaRepository<IdeaShare, UUID> {

    boolean existsByIdeaIdAndCollaboratorUserIdAndStatus(UUID ideaId, UUID collaboratorUserId, String status);

    Optional<IdeaShare> findByIdeaIdAndCollaboratorUserIdAndStatus(UUID ideaId, UUID collaboratorUserId, String status);

    long countByIdeaIdAndStatus(UUID ideaId, String status);

    Optional<IdeaShare> findByInvitationId(UUID invitationId);

    Optional<IdeaShare> findByLinkIdAndCollaboratorUserIdAndStatus(UUID linkId, UUID collaboratorUserId, String status);

    List<IdeaShare> findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(UUID collaboratorUserId, String status);

    @Query("""
            select distinct share.ideaId
            from IdeaShare share
            where share.ideaId in :ideaIds
              and share.status = :status
            """)
    List<UUID> findIdeaIdsByIdeaIdInAndStatus(@Param("ideaIds") Collection<UUID> ideaIds, @Param("status") String status);
}
