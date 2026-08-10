package com.rocketflow.focusnotifications;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "web_push_subscriptions")
class WebPushSubscription {
    @Id private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Column(nullable = false, columnDefinition = "text") private String endpoint;
    @Column(name = "endpoint_hash", nullable = false, length = 64) private String endpointHash;
    @Column(nullable = false, length = 256) private String p256dh;
    @Column(nullable = false, length = 256) private String auth;
    @Column(name = "installation_id", nullable = false, length = 120) private String installationId;
    @Column(name = "expiration_time") private Instant expirationTime;
    @Column(nullable = false) private boolean active;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    UUID getId() { return id; }
    void setId(UUID id) { this.id = id; }
    UUID getUserId() { return userId; }
    void setUserId(UUID userId) { this.userId = userId; }
    String getEndpoint() { return endpoint; }
    void setEndpoint(String endpoint) { this.endpoint = endpoint; }
    String getEndpointHash() { return endpointHash; }
    void setEndpointHash(String endpointHash) { this.endpointHash = endpointHash; }
    String getP256dh() { return p256dh; }
    void setP256dh(String p256dh) { this.p256dh = p256dh; }
    String getAuth() { return auth; }
    void setAuth(String auth) { this.auth = auth; }
    String getInstallationId() { return installationId; }
    void setInstallationId(String installationId) { this.installationId = installationId; }
    Instant getExpirationTime() { return expirationTime; }
    void setExpirationTime(Instant expirationTime) { this.expirationTime = expirationTime; }
    boolean isActive() { return active; }
    void setActive(boolean active) { this.active = active; }
    Instant getCreatedAt() { return createdAt; }
    void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
