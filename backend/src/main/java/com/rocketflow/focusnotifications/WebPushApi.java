package com.rocketflow.focusnotifications;

import java.time.Instant;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

final class WebPushApi {
    private WebPushApi() {
    }

    record ConfigResponse(boolean enabled, String publicKey) {
    }

    record KeysRequest(
            @NotBlank @Size(max = 256) String p256dh,
            @NotBlank @Size(max = 256) String auth
    ) {
    }

    record RegisterSubscriptionRequest(
            @NotBlank @Size(max = 4096) String endpoint,
            Instant expirationTime,
            @NotNull @Valid KeysRequest keys,
            @NotBlank @Size(max = 120) String installationId
    ) {
    }

    record SubscriptionResponse(UUID id, boolean active) {
    }
}
