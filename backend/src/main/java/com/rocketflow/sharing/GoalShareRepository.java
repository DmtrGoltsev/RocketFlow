package com.rocketflow.sharing;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface GoalShareRepository extends JpaRepository<GoalShare, UUID> {

    boolean existsByGoalIdAndCollaboratorUserIdAndStatus(UUID goalId, UUID collaboratorUserId, String status);

    long countByGoalIdAndStatus(UUID goalId, String status);

    Optional<GoalShare> findByInvitationId(UUID invitationId);

    List<GoalShare> findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(UUID collaboratorUserId, String status);

    @Query("""
            select distinct share.goalId
            from GoalShare share
            where share.goalId in :goalIds
              and share.status = :status
            """)
    List<UUID> findGoalIdsByGoalIdInAndStatus(@Param("goalIds") Collection<UUID> goalIds, @Param("status") String status);
}
