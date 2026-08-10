package com.rocketflow.focusnotifications;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface WebPushSubscriptionRepository extends JpaRepository<WebPushSubscription, UUID> {
    Optional<WebPushSubscription> findByEndpointHash(String endpointHash);
    Optional<WebPushSubscription> findByUserIdAndInstallationId(UUID userId, String installationId);
    Optional<WebPushSubscription> findByIdAndUserId(UUID id, UUID userId);
    @Query("""
            select count(subscription) from WebPushSubscription subscription
             where subscription.userId = :userId and subscription.active = true
               and (subscription.expirationTime is null or subscription.expirationTime > :now)
            """)
    long countActiveUnexpiredByUserId(
            @Param("userId") UUID userId,
            @Param("now") Instant now
    );
    @Query("""
            select subscription from WebPushSubscription subscription
             where subscription.userId in :userIds and subscription.active = true
               and (subscription.expirationTime is null or subscription.expirationTime > :now)
             order by subscription.userId asc, subscription.createdAt asc
            """)
    List<WebPushSubscription> findDeliverable(
            @Param("userIds") Collection<UUID> userIds,
            @Param("now") Instant now
    );
}
