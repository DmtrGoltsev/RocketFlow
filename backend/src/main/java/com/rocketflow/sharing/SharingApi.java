package com.rocketflow.sharing;

import static com.rocketflow.goals.GoalsApi.*;
import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public final class SharingApi {

    private SharingApi() {
    }

    public record ShareRequest(
            @NotBlank @Email @Size(max = 320) String email
    ) {
    }

    public record ShareInvitationDto(
            UUID id,
            String targetType,
            UUID targetId,
            String targetEmail,
            String status,
            Instant createdAt,
            Instant expiresAt
    ) {
    }

    public record ShareInvitationListResponse(List<ShareInvitationDto> items) {
    }

    public record ShareInvitationActionResponse(UUID id, String status) {
    }

    public record SharedResourcesResponse(List<GoalDto> goals, List<TaskDto> tasks) {
    }
}
