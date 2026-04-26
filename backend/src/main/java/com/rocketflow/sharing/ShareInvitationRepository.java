package com.rocketflow.sharing;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ShareInvitationRepository extends JpaRepository<ShareInvitation, UUID> {

    boolean existsByTargetTypeAndTargetIdAndStatusAndTargetEmailIgnoreCase(
            String targetType,
            UUID targetId,
            String status,
            String targetEmail
    );

    List<ShareInvitation> findByStatusAndExpiresAtBefore(String status, Instant expiresAt);

    @Query("""
            select invitation
            from ShareInvitation invitation
            where invitation.inviterUserId = :userId
               or lower(invitation.targetEmail) = lower(:email)
            order by invitation.createdAt desc
            """)
    List<ShareInvitation> findVisibleToUser(@Param("userId") UUID userId, @Param("email") String email);
}
