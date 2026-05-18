package com.rocketflow.ideas;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
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

    public record FolderNoteItemDto(
            UUID id,
            UUID folderNoteId,
            String text,
            boolean checked,
            int displayOrder,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record FolderNoteDto(
            UUID id,
            UUID folderId,
            String kind,
            String title,
            String body,
            int displayOrder,
            boolean archived,
            boolean shared,
            UUID authorUserId,
            String authorEmail,
            String authorName,
            long version,
            List<FolderNoteItemDto> items,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record FolderNoteListResponse(List<FolderNoteDto> items) {
    }

    public record CreateFolderNoteRequest(
            @NotBlank @Pattern(regexp = "note|list") String kind,
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body
    ) {
    }

    public record UpdateFolderNoteRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body,
            @NotNull Integer displayOrder,
            @NotNull Boolean archived,
            @NotNull Long version
    ) {
    }

    public record CreateFolderNoteItemRequest(
            @NotBlank @Size(max = 1000) String text,
            Boolean checked
    ) {
    }

    public record UpdateFolderNoteItemRequest(
            @NotBlank @Size(max = 1000) String text,
            @NotNull Boolean checked,
            @NotNull Integer displayOrder,
            @NotNull Long version
    ) {
    }
}
