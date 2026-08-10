package com.rocketflow.focus;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

final class FocusApi {
    private FocusApi() {
    }

    record ProgressDto(int completedWeight, int totalWeight, int percent, int completedCount, int totalCount) {
    }

    record ItemDto(
            UUID id,
            UUID taskId,
            String title,
            String status,
            Integer effort,
            int effectiveWeight,
            Instant plannedTime,
            Instant dueTime,
            int position,
            boolean historyOnly,
            UUID folderId,
            String folderTitle,
            UUID goalId,
            String goalTitle,
            boolean shared,
            boolean canWrite
    ) {
    }

    record RolloverOfferDto(UUID sourcePeriodId, List<ItemDto> items) {
    }

    record PeriodDto(
            UUID id,
            LocalDate weekStart,
            LocalDate weekEndExclusive,
            Instant startsAt,
            Instant endsAt,
            String timezone,
            String status,
            long version,
            ProgressDto progress,
            List<ItemDto> items,
            RolloverOfferDto rolloverOffer
    ) {
    }

    record CandidateDto(
            UUID taskId,
            String title,
            String status,
            Integer effort,
            int effectiveWeight,
            Instant plannedTime,
            Instant dueTime,
            UUID folderId,
            String folderTitle,
            UUID goalId,
            String goalTitle,
            boolean shared,
            boolean canWrite,
            boolean inFocus
    ) {
    }

    record CandidateListResponse(List<CandidateDto> items, String nextCursor) {
    }

    record HistorySummaryDto(
            UUID id,
            LocalDate weekStart,
            LocalDate weekEndExclusive,
            Instant startsAt,
            Instant endsAt,
            String timezone,
            String status,
            long version,
            ProgressDto progress
    ) {
    }

    record HistoryResponse(List<HistorySummaryDto> items) {
    }

    record MutationRequest(Long periodVersion, @Size(max = 128) String idempotencyKey) {
    }

    record ReorderRequest(
            @NotNull List<UUID> taskIds,
            Long periodVersion,
            @Size(max = 128) String idempotencyKey
    ) {
    }

    record ResolveRolloverRequest(
            @NotNull List<UUID> taskIds,
            Long periodVersion,
            @Size(max = 128) String idempotencyKey
    ) {
    }

    record NotificationSettingsDto(
            Integer intervalMinutes,
            String quietHoursStart,
            String quietHoursEnd,
            long version
    ) {
    }

    record UpdateNotificationSettingsRequest(
            @Min(30) @Max(240) Integer intervalMinutes,
            @Pattern(regexp = "(?:[01]\\d|2[0-3]):[0-5]\\d") String quietHoursStart,
            @Pattern(regexp = "(?:[01]\\d|2[0-3]):[0-5]\\d") String quietHoursEnd,
            @NotNull Long version
    ) {
    }
}
