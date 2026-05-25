package com.rocketflow.links;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EntityLinkCleanupService {

    private final EntityLinkRepository entityLinkRepository;

    public EntityLinkCleanupService(EntityLinkRepository entityLinkRepository) {
        this.entityLinkRepository = entityLinkRepository;
    }

    @Transactional
    public void archiveLinksForEntity(String entityType, UUID entityId) {
        entityLinkRepository.archiveActiveForEntity(entityType, entityId);
    }

    @Transactional
    public void archiveLinksForEntities(Map<String, ? extends Collection<UUID>> entitiesByType) {
        entitiesByType.forEach((entityType, entityIds) -> {
            if (entityIds != null && !entityIds.isEmpty()) {
                entityLinkRepository.archiveActiveForEntities(entityType, entityIds);
            }
        });
    }
}
