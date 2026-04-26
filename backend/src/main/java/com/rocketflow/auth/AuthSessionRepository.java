package com.rocketflow.auth;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface AuthSessionRepository extends JpaRepository<AuthSession, UUID> {

    Optional<AuthSession> findByAccessTokenHashAndRevokedAtIsNull(String accessTokenHash);

    Optional<AuthSession> findByRefreshTokenHashAndRevokedAtIsNull(String refreshTokenHash);

    long deleteByRevokedAtIsNotNullOrRefreshExpiresAtBefore(Instant expiresAt);
}
