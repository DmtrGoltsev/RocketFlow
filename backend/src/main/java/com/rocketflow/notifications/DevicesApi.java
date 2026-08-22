package com.rocketflow.notifications;

import java.time.Instant;
import java.util.Locale;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class DevicesApi {

    private DevicesApi() {
    }

    public record RegisterDeviceRequest(
            @NotBlank @Pattern(regexp = "android|ios") String platform,
            @NotBlank @Size(max = 1024) String pushToken,
            @Size(max = 120) String installationId,
            @Size(max = 120) String deviceName
    ) {
        public RegisterDeviceRequest {
            if (platform != null) {
                platform = platform.trim().toLowerCase(Locale.ROOT);
            }
        }
    }

    public record DeviceRegistrationResponse(
            UUID id,
            String platform,
            String deviceName,
            boolean active,
            Instant createdAt
    ) {
    }
}
