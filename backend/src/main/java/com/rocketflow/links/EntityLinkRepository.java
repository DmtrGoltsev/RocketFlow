package com.rocketflow.links;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface EntityLinkRepository extends JpaRepository<EntityLink, UUID> {

    @Query("""
            select link
            from EntityLink link
            where link.archived = false
              and (
                    (link.sourceType = :entityType and link.sourceId = :entityId)
                 or (link.targetType = :entityType and link.targetId = :entityId)
              )
            order by link.createdAt asc
            """)
    List<EntityLink> findActiveForEntity(@Param("entityType") String entityType, @Param("entityId") UUID entityId);

    Optional<EntityLink> findBySourceTypeAndSourceIdAndTargetTypeAndTargetIdAndRelationTypeAndArchivedFalse(
            String sourceType,
            UUID sourceId,
            String targetType,
            UUID targetId,
            String relationType
    );

    List<EntityLink> findByRelationTypeAndSourceTypeAndSourceIdAndArchivedFalse(String relationType, String sourceType, UUID sourceId);
}
