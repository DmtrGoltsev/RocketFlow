package com.rocketflow.auth;

import java.time.Instant;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.rocketflow.accounts.User;
import com.rocketflow.config.AuthProperties;

@Component
public class AuthSessionFactory {

    private final AuthProperties authProperties;
    private final TokenHasher tokenHasher;

    public AuthSessionFactory(AuthProperties authProperties, TokenHasher tokenHasher) {
        this.authProperties = authProperties;
        this.tokenHasher = tokenHasher;
    }

    public CreatedSession create(User user, Instant now) {
        String accessToken = UUID.randomUUID() + "-" + UUID.randomUUID();
        String refreshToken = UUID.randomUUID() + "-" + UUID.randomUUID();

        AuthSession session = new AuthSession();
        session.setId(UUID.randomUUID());
        session.setUserId(user.getId());
        session.setAccessTokenHash(tokenHasher.hash(accessToken));
        session.setRefreshTokenHash(tokenHasher.hash(refreshToken));
        session.setAccessExpiresAt(now.plus(authProperties.getAccessTokenTtl()));
        session.setRefreshExpiresAt(now.plus(authProperties.getRefreshTokenTtl()));
        session.setCreatedAt(now);
        session.setUpdatedAt(now);

        return new CreatedSession(session, new AuthTokenPair(accessToken, refreshToken, session.getAccessExpiresAt()));
    }

    public record CreatedSession(AuthSession session, AuthTokenPair tokenPair) {
    }
}
