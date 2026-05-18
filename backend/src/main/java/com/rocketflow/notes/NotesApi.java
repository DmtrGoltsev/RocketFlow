package com.rocketflow.notes;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class NotesApi {

    private NotesApi() {
    }

    public record NoteDto(
            UUID id,
            UUID folderId,
            String title,
            String body,
            int displayOrder,
            boolean archived,
            boolean shared,
            boolean fullAccess,
            UUID authorUserId,
            String authorEmail,
            String authorName,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record NoteListResponse(List<NoteDto> items) {
    }

    public record CreateNoteRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body
    ) {
    }

    public record UpdateNoteRequest(
            @NotBlank @Size(max = 200) String title,
            @Size(max = 4000) String body,
            @NotNull Integer displayOrder,
            @NotNull Boolean archived,
            @NotNull Long version
    ) {
    }

    public record MoveNoteRequest(@NotNull UUID targetFolderId, @NotNull Long version) {
    }

    public record CloneNoteRequest(@NotNull UUID targetFolderId, @Size(max = 200) String title) {
    }
}
