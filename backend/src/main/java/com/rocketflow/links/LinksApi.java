package com.rocketflow.links;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

public final class LinksApi {

    private LinksApi() {
    }

    public record EntityRefDto(
            String type,
            UUID id,
            String title,
            String subtitle,
            String status,
            String path,
            Boolean archived,
            boolean accessible,
            boolean redacted
    ) {
    }

    public record EntityLinkDto(
            UUID id,
            EntityRefDto source,
            EntityRefDto target,
            String relationType,
            UUID createdByUserId,
            String createdByName,
            Instant createdAt,
            Instant updatedAt,
            long version
    ) {
    }

    public record EntityLinkListResponse(List<EntityLinkDto> items) {
    }

    public record CreateEntityLinkRequest(
            @NotBlank @Pattern(regexp = "goal|task|idea|note") String sourceType,
            @NotNull UUID sourceId,
            @NotBlank @Pattern(regexp = "goal|task|idea|note") String targetType,
            @NotNull UUID targetId,
            @NotBlank @Pattern(regexp = "related|dependency") String relationType
    ) {
    }

    public record UpdateEntityLinkRequest(
            @NotBlank @Pattern(regexp = "related|dependency") String relationType,
            @NotNull Long version
    ) {
    }
}
