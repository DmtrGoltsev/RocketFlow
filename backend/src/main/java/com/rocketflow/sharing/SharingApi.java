package com.rocketflow.sharing;

import static com.rocketflow.goals.GoalsApi.*;
import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Size;

public final class SharingApi {

    private SharingApi() {
    }

    public record ShareRequest(
            @Email @Size(max = 320) String email,
            UUID userId
    ) {
    }

    public record ShareInvitationDto(
            UUID id,
            String targetType,
            UUID targetId,
            String targetEmail,
            UUID targetUserId,
            String status,
            Instant createdAt,
            Instant expiresAt
    ) {
    }

    public record ShareInvitationListResponse(List<ShareInvitationDto> items) {
    }

    public record ShareInvitationActionResponse(UUID id, String status) {
    }

    public record ShareLinkRequest(Instant expiresAt) {
    }

    public record ShareLinkDto(
            UUID id,
            String targetType,
            UUID targetId,
            String status,
            Instant createdAt,
            Instant expiresAt,
            Instant revokedAt
    ) {
    }

    public record ShareLinkCreateResponse(
            UUID id,
            String targetType,
            UUID targetId,
            String token,
            String status,
            Instant createdAt,
            Instant expiresAt
    ) {
    }

    public record ShareLinkListResponse(List<ShareLinkDto> items) {
    }

    public record ShareLinkActionResponse(UUID id, String status) {
    }

    public record ShareLinkResolveResponse(UUID id, String targetType, UUID targetId, String status, Instant expiresAt) {
    }

    public record ShareLinkAcceptResponse(UUID shareId, String targetType, UUID targetId, String status) {
    }

    public record SharedFolderResourceDto(
            UUID id,
            String name,
            String description,
            int displayOrder,
            boolean archived,
            boolean shared,
            boolean canAccessFolderContent,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record SharedResourcesResponse(
            List<SharedFolderResourceDto> folders,
            List<GoalDto> goals,
            List<TaskDto> tasks,
            List<UUID> createTaskGoalIds
    ) {
    }
}
