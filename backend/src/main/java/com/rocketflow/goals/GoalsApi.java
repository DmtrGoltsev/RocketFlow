package com.rocketflow.goals;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class GoalsApi {

    private GoalsApi() {
    }

    public record GoalDto(
            UUID id,
            UUID folderId,
            String name,
            String description,
            String status,
            boolean archived,
            boolean shared,
            boolean fullAccess,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record GoalListResponse(List<GoalDto> items) {
    }

    public record CreateGoalRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 1000) String description,
            @Pattern(regexp = "todo|in_progress|done|cancelled") String status
    ) {
    }

    public record UpdateGoalRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 1000) String description,
            @Pattern(regexp = "todo|in_progress|done|cancelled") String status,
            @NotNull Boolean archived,
            @NotNull Long version
    ) {
    }

    public record MoveGoalRequest(@NotNull UUID targetFolderId, @NotNull Long version) {
    }

    public record CloneGoalRequest(@NotNull UUID targetFolderId, @Size(max = 160) String name) {
    }
}
