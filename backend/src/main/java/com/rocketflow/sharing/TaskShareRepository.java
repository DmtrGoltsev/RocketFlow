package com.rocketflow.sharing;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TaskShareRepository extends JpaRepository<TaskShare, UUID> {

    boolean existsByTaskIdAndCollaboratorUserIdAndStatus(UUID taskId, UUID collaboratorUserId, String status);

    long countByTaskIdAndStatus(UUID taskId, String status);

    Optional<TaskShare> findByInvitationId(UUID invitationId);

    List<TaskShare> findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(UUID collaboratorUserId, String status);

    @Query("""
            select distinct share.taskId
            from TaskShare share
            where share.taskId in :taskIds
              and share.status = :status
            """)
    List<UUID> findTaskIdsByTaskIdInAndStatus(@Param("taskIds") Collection<UUID> taskIds, @Param("status") String status);
}
