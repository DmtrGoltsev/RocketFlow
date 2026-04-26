package com.rocketflow.auth;

import java.time.Instant;

public record AuthTokenPair(String accessToken, String refreshToken, Instant expiresAt) {
}
