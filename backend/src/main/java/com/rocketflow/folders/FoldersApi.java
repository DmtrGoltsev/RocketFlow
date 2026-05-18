package com.rocketflow.folders;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class FoldersApi {

    private FoldersApi() {
    }

    public record FolderDto(
            UUID id,
            UUID parentFolderId,
            String name,
            String description,
            int displayOrder,
            boolean archived,
            boolean shared,
            boolean fullAccess,
            long version,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record FolderListResponse(List<FolderDto> items) {
    }

    public record CreateFolderRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 1000) String description,
            UUID parentFolderId
    ) {
    }

    public record UpdateFolderRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 1000) String description,
            @NotNull Integer displayOrder,
            @NotNull Boolean archived,
            @NotNull Long version
    ) {
    }

    public record MoveFolderRequest(UUID targetFolderId, @NotNull Long version) {
    }

    public record CloneFolderRequest(UUID targetFolderId, @Size(max = 160) String name, Boolean includeChildren) {
    }
}
