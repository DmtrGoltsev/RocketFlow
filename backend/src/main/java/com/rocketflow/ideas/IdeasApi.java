package com.rocketflow.ideas;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class IdeasApi {

    private IdeasApi() {
    }

    public record IdeaDto(
            UUID id,
            UUID folderId,
            String title,
            String body,
            String status,
            int displayOrder,
            boolean archived,
            boolean allowAuthorNoteEdits,
            boolean shared,
            UUID creatorUserId,
            String creatorEmail,
            String creatorName,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record IdeaListResponse(List<IdeaDto> items) {
    }

    public record CreateIdeaRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body,
            @Size(max = 32) String status,
            Boolean allowAuthorNoteEdits
    ) {
    }

    public record UpdateIdeaRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body,
            @NotBlank @Size(max = 32) String status,
            @NotNull Integer displayOrder,
            @NotNull Boolean archived,
            Boolean allowAuthorNoteEdits,
            @NotNull Long version
    ) {
    }

    public record IdeaNoteDto(
            UUID id,
            UUID ideaId,
            String eventType,
            String body,
            Map<String, Object> metadata,
            UUID authorUserId,
            String authorEmail,
            String authorName,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record IdeaNoteListResponse(List<IdeaNoteDto> items) {
    }

    public record CreateIdeaNoteRequest(
            @NotBlank @Size(max = 32) String eventType,
            @Size(max = 4000) String body,
            Map<String, Object> metadata
    ) {
    }

    public record UpdateIdeaNoteRequest(
            @NotBlank @Size(max = 32) String eventType,
            @Size(max = 4000) String body,
            Map<String, Object> metadata,
            @NotNull Long version
    ) {
    }

    public record MoveIdeaRequest(@NotNull UUID targetFolderId, @NotNull Long version) {
    }

    public record CloneIdeaRequest(@NotNull UUID targetFolderId, @Size(max = 200) String title) {
    }
}
