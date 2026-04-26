package com.rocketflow.auth;

import java.time.Instant;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class AuthDtos {

    private AuthDtos() {
    }

    public record RegisterRequest(
            @Email @NotBlank String email,
            @NotBlank @Size(min = 8, max = 200) String password,
            @NotBlank @Size(max = 120) String displayName,
            @NotBlank @Size(max = 64) String timezone,
            @NotBlank @Pattern(regexp = "ru|en") String language
    ) {
    }

    public record LoginRequest(
            @Email @NotBlank String email,
            @NotBlank String password
    ) {
    }

    public record RefreshRequest(@NotBlank String refreshToken) {
    }

    public record LogoutRequest(@NotBlank String refreshToken) {
    }

    public record UserResponse(
            UUID id,
            String email,
            String displayName,
            String timezone,
            String language,
            Instant createdAt
    ) {
    }

    public record TokensResponse(String accessToken, String refreshToken, Instant expiresAt) {
    }

    public record AuthResponse(UserResponse user, TokensResponse tokens) {
    }

    public record RefreshResponse(TokensResponse tokens) {
    }

    public record PriorityDecayPolicyDto(
            String taskType,
            boolean enabled,
            String thresholdPreset,
            int decayAmount
    ) {
    }

    public record UserSettingsResponse(
            String language,
            PriorityDecayPolicyDto greenPriorityDecayPolicy,
            PriorityDecayPolicyDto redPriorityDecayPolicy,
            boolean notificationsEnabled,
            long version
    ) {
    }

    public record UpdatePriorityDecayPolicyRequest(
            @NotNull Boolean enabled,
            @NotBlank @Pattern(regexp = "day|week|month") String thresholdPreset,
            @NotNull Integer decayAmount
    ) {
    }

    public record UpdateSettingsRequest(
            @NotBlank @Pattern(regexp = "ru|en") String language,
            @NotNull @Valid UpdatePriorityDecayPolicyRequest greenPriorityDecayPolicy,
            @NotNull @Valid UpdatePriorityDecayPolicyRequest redPriorityDecayPolicy,
            @NotNull Boolean notificationsEnabled,
            @NotNull Long version
    ) {
    }
}
