package com.rocketflow.focus;

import static com.rocketflow.focus.FocusApi.*;

import java.nio.charset.StandardCharsets;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.TaskAccess;

@Service
public class FocusService {
    private static final Set<Integer> ALLOWED_INTERVALS = Set.of(30, 60, 120, 240);

    private final FocusPeriodRepository periodRepository;
    private final FocusItemRepository itemRepository;
    private final FocusNotificationSettingsRepository settingsRepository;
    private final FocusCandidateRepository candidateRepository;
    private final UserRepository userRepository;
    private final SharingAccessService sharingAccessService;
    private final FocusAccessProbe accessProbe;
    private final JdbcTemplate jdbcTemplate;

    public FocusService(
            FocusPeriodRepository periodRepository,
            FocusItemRepository itemRepository,
            FocusNotificationSettingsRepository settingsRepository,
            FocusCandidateRepository candidateRepository,
            UserRepository userRepository,
            SharingAccessService sharingAccessService,
            FocusAccessProbe accessProbe,
            JdbcTemplate jdbcTemplate
    ) {
        this.periodRepository = periodRepository;
        this.itemRepository = itemRepository;
        this.settingsRepository = settingsRepository;
        this.candidateRepository = candidateRepository;
        this.userRepository = userRepository;
        this.sharingAccessService = sharingAccessService;
        this.accessProbe = accessProbe;
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public PeriodDto current(UUID userId) {
        FocusPeriod period = requireCurrentPeriod(userId);
        return toPeriodDto(period, true);
    }

    @Transactional
    public void removeInaccessibleSharedItems(UUID userId) {
        FocusPeriod period = periodRepository.findFirstByUserIdAndStatus(userId, "active").orElse(null);
        if (period == null) {
            return;
        }
        boolean changed = false;
        for (FocusItem item : itemRepository.findByPeriodIdOrderByPositionAsc(period.getId())) {
            if (item.isShared() && !sharingAccessService.canAccessTask(item.getTaskId(), userId)) {
                itemRepository.delete(item);
                changed = true;
            }
        }
        if (changed) {
            touch(period);
        }
    }

    @Transactional
    public CandidateListResponse candidates(
            UUID userId,
            String query,
            UUID folderId,
            UUID goalId,
            String cursor,
            int requestedLimit
    ) {
        FocusPeriod current = requireCurrentPeriod(userId);
        int offset = decodeCursor(cursor);
        int limit = Math.max(1, Math.min(requestedLimit, 100));
        String normalizedQuery = query == null ? "" : query.strip().toLowerCase();
        Set<UUID> inFocus = new HashSet<>();
        itemRepository.findByPeriodIdOrderByPositionAsc(current.getId()).stream()
                .filter(item -> !item.isHistoryOnly())
                .map(FocusItem::getTaskId)
                .forEach(inFocus::add);

        List<LiveTask> visible = candidateRepository.findVisibleCandidates(
                        userId, normalizedQuery, folderId, goalId, offset, limit + 1
                ).stream()
                .map(this::liveTask)
                .toList();

        if (visible.isEmpty()) {
            return new CandidateListResponse(List.of(), null);
        }
        boolean hasMore = visible.size() > limit;
        List<CandidateDto> result = visible.subList(0, Math.min(visible.size(), limit)).stream()
                .map(task -> toCandidate(task, userId, inFocus.contains(task.taskId())))
                .toList();
        return new CandidateListResponse(result, hasMore ? encodeCursor(offset + result.size()) : null);
    }

    @Transactional
    public PeriodDto add(UUID userId, UUID taskId, MutationRequest request) {
        FocusPeriod period = requireCurrentPeriod(userId);
        if (isRepeated(userId, request == null ? null : request.idempotencyKey(), "add:" + taskId)) {
            return toPeriodDto(period, true);
        }
        verifyVersion(period, request == null ? null : request.periodVersion());
        LiveTask task = requireVisibleTask(taskId, userId);
        FocusItem existing = itemRepository.findByPeriodIdAndTaskId(period.getId(), taskId).orElse(null);
        if (existing == null) {
            TaskAccess access = requireAccess(taskId, userId);
            FocusItem item = snapshot(period.getId(), task, access, nextPosition(period.getId()), Instant.now());
            itemRepository.saveAndFlush(item);
            touch(period);
        } else if (existing.isHistoryOnly()) {
            existing.setHistoryOnly(false);
            existing.setUpdatedAt(Instant.now());
            itemRepository.save(existing);
            touch(period);
        }
        return toPeriodDto(period, true);
    }

    @Transactional
    public PeriodDto remove(UUID userId, UUID taskId, MutationRequest request) {
        FocusPeriod period = requireCurrentPeriod(userId);
        if (isRepeated(userId, request == null ? null : request.idempotencyKey(), "remove:" + taskId)) {
            return toPeriodDto(period, true);
        }
        verifyVersion(period, request == null ? null : request.periodVersion());
        if (itemRepository.existsByPeriodIdAndTaskId(period.getId(), taskId)) {
            itemRepository.deleteByPeriodIdAndTaskId(period.getId(), taskId);
            itemRepository.flush();
            normalizePositions(period.getId());
            touch(period);
        }
        return toPeriodDto(period, true);
    }

    @Transactional
    public PeriodDto reorder(UUID userId, ReorderRequest request) {
        FocusPeriod period = requireCurrentPeriod(userId);
        if (isRepeated(userId, request.idempotencyKey(), "reorder")) {
            return toPeriodDto(period, true);
        }
        verifyVersion(period, request.periodVersion());
        projectItems(period, userId, true, false);
        List<FocusItem> allItems = itemRepository.findByPeriodIdOrderByPositionAsc(period.getId());
        List<FocusItem> items = allItems.stream()
                .filter(item -> !item.isHistoryOnly())
                .toList();
        Set<UUID> currentIds = items.stream().map(FocusItem::getTaskId).collect(java.util.stream.Collectors.toSet());
        if (request.taskIds().size() != currentIds.size()
                || request.taskIds().stream().distinct().count() != request.taskIds().size()
                || !currentIds.equals(new HashSet<>(request.taskIds()))) {
            throw badRequest("focus_order_invalid", "taskIds must contain every visible Focus task exactly once.");
        }
        Map<UUID, FocusItem> byTask = new LinkedHashMap<>();
        items.forEach(item -> byTask.put(item.getTaskId(), item));
        moveToTemporaryPositions(allItems);
        for (int position = 0; position < request.taskIds().size(); position++) {
            byTask.get(request.taskIds().get(position)).setPosition(position);
        }
        int hiddenPosition = request.taskIds().size();
        for (FocusItem item : allItems) {
            if (item.isHistoryOnly()) {
                item.setPosition(hiddenPosition++);
            }
        }
        itemRepository.saveAll(allItems);
        touch(period);
        return toPeriodDto(period, true);
    }

    @Transactional
    public PeriodDto resolveRollover(UUID userId, UUID sourcePeriodId, ResolveRolloverRequest request) {
        FocusPeriod current = requireCurrentPeriod(userId);
        if (isRepeated(userId, request.idempotencyKey(), "rollover:" + sourcePeriodId)) {
            return toPeriodDto(current, true);
        }
        verifyVersion(current, request.periodVersion());
        FocusPeriod source = periodRepository.findByIdAndUserId(sourcePeriodId, userId)
                .orElseThrow(() -> notFound("Focus period"));
        if (!"completed".equals(source.getStatus()) || !source.getId().equals(current.getPreviousPeriodId())) {
            throw badRequest("rollover_invalid", "The period is not the current rollover source.");
        }
        Set<UUID> requested = new HashSet<>(request.taskIds());
        if (requested.size() != request.taskIds().size()) {
            throw badRequest("rollover_invalid", "taskIds must not contain duplicates.");
        }
        Map<UUID, FocusItem> offered = rolloverItems(source, userId).stream()
                .collect(java.util.stream.Collectors.toMap(FocusItem::getTaskId, item -> item));
        if (!offered.keySet().containsAll(requested)) {
            throw badRequest("rollover_invalid", "Only tasks from the current rollover offer can be carried over.");
        }
        int position = nextPosition(current.getId());
        Instant now = Instant.now();
        for (UUID taskId : request.taskIds()) {
            if (itemRepository.existsByPeriodIdAndTaskId(current.getId(), taskId)) {
                continue;
            }
            LiveTask live = requireVisibleTask(taskId, userId);
            itemRepository.save(snapshot(current.getId(), live, requireAccess(taskId, userId), position++, now));
        }
        source.setRolloverResolvedAt(now);
        source.setUpdatedAt(now);
        periodRepository.save(source);
        touch(current);
        return toPeriodDto(current, true);
    }

    @Transactional
    public HistoryResponse history(UUID userId) {
        List<HistorySummaryDto> items = periodRepository.findByUserIdOrderByWeekStartDesc(userId).stream()
                .filter(period -> "completed".equals(period.getStatus()))
                .map(period -> {
                    List<ProjectedItem> projected = projectItems(period, userId, false, true);
                    return new HistorySummaryDto(
                            period.getId(), period.getWeekStart(), period.getWeekEndExclusive(),
                            period.getStartsAt(), period.getEndsAt(), period.getTimezoneSnapshot(),
                            period.getStatus(), period.getVersion(), progress(projected)
                    );
                })
                .toList();
        return new HistoryResponse(items);
    }

    @Transactional
    public PeriodDto historyPeriod(UUID userId, UUID periodId) {
        FocusPeriod period = periodRepository.findByIdAndUserId(periodId, userId)
                .orElseThrow(() -> notFound("Focus period"));
        if (!"completed".equals(period.getStatus())) {
            throw notFound("Focus period");
        }
        return toPeriodDto(period, false);
    }

    @Transactional
    public NotificationSettingsDto settings(UUID userId) {
        return toSettings(requireSettings(userId));
    }

    @Transactional
    public NotificationSettingsDto updateSettings(UUID userId, UpdateNotificationSettingsRequest request) {
        if (request.intervalMinutes() != null && !ALLOWED_INTERVALS.contains(request.intervalMinutes())) {
            throw badRequest("focus_interval_invalid", "intervalMinutes must be null, 30, 60, 120, or 240.");
        }
        boolean hasStart = request.quietHoursStart() != null;
        boolean hasEnd = request.quietHoursEnd() != null;
        if (hasStart != hasEnd) {
            throw badRequest("focus_quiet_hours_invalid", "Quiet hours start and end must both be set or both be null.");
        }
        FocusNotificationSettings settings = requireSettings(userId);
        if (request.version() != settings.getVersion()) {
            throw new ApiException(HttpStatus.CONFLICT, "focus_settings_version_conflict",
                    "Focus notification settings were changed by another client.");
        }
        settings.setIntervalMinutes(request.intervalMinutes());
        settings.setQuietHoursStart(parseTime(request.quietHoursStart()));
        settings.setQuietHoursEnd(parseTime(request.quietHoursEnd()));
        settings.setUpdatedAt(Instant.now());
        return toSettings(settingsRepository.saveAndFlush(settings));
    }

    private FocusPeriod requireCurrentPeriod(UUID userId) {
        User user = userRepository.findById(userId).orElseThrow(() -> notFound("User"));
        ZoneId zone;
        try {
            zone = ZoneId.of(user.getTimezone());
        } catch (DateTimeException exception) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "timezone_invalid", "The user timezone is invalid.");
        }
        Instant now = Instant.now();
        FocusWeek week = FocusWeek.containing(now, zone);
        jdbcTemplate.query("select pg_advisory_xact_lock(hashtext(?))", resultSet -> null, "focus:" + userId);
        FocusPeriod active = periodRepository.findFirstByUserIdAndStatus(userId, "active").orElse(null);
        if (active != null && active.getWeekStart().equals(week.start())) {
            return active;
        }

        FocusPeriod previous = active;
        if (previous != null) {
            freezePeriod(previous, userId, now);
            previous.setStatus("completed");
            previous.setUpdatedAt(now);
            periodRepository.saveAndFlush(previous);
        }
        FocusPeriod existing = periodRepository.findByUserIdAndWeekStart(userId, week.start()).orElse(null);
        if (existing != null) {
            if (!"active".equals(existing.getStatus())) {
                existing.setStatus("active");
                existing.setUpdatedAt(now);
            }
            return existing;
        }
        FocusPeriod created = new FocusPeriod();
        created.setId(UUID.randomUUID());
        created.setUserId(userId);
        created.setWeekStart(week.start());
        created.setWeekEndExclusive(week.endExclusive());
        created.setStartsAt(week.startsAt());
        created.setEndsAt(week.endsAt());
        created.setTimezoneSnapshot(week.timezone());
        created.setStatus("active");
        created.setPreviousPeriodId(previous == null ? null : previous.getId());
        created.setCreatedAt(now);
        created.setUpdatedAt(now);
        return periodRepository.save(created);
    }

    private void freezePeriod(FocusPeriod period, UUID userId, Instant now) {
        for (FocusItem item : itemRepository.findByPeriodIdOrderByPositionAsc(period.getId())) {
            LiveTask live = loadTask(item.getTaskId());
            if (live == null) {
                itemRepository.delete(item);
                continue;
            }
            TaskAccess access = accessFor(live, userId);
            if (access == null || live.archived()) {
                item.setHistoryOnly(true);
            } else {
                item.setStatus(live.status());
            }
            item.setUpdatedAt(now);
        }
    }

    private PeriodDto toPeriodDto(FocusPeriod period, boolean includeRollover) {
        boolean active = "active".equals(period.getStatus());
        List<ProjectedItem> projected = projectItems(period, period.getUserId(), active, !active);
        List<ItemDto> items = projected.stream().map(ProjectedItem::dto).toList();
        RolloverOfferDto offer = null;
        if (includeRollover && period.getPreviousPeriodId() != null) {
            FocusPeriod source = periodRepository.findByIdAndUserId(period.getPreviousPeriodId(), period.getUserId()).orElse(null);
            if (source != null && source.getRolloverResolvedAt() == null) {
                List<ItemDto> offered = rolloverItems(source, period.getUserId()).stream().map(this::toSnapshotDto).toList();
                if (!offered.isEmpty()) {
                    offer = new RolloverOfferDto(source.getId(), offered);
                }
            }
        }
        return new PeriodDto(
                period.getId(), period.getWeekStart(), period.getWeekEndExclusive(), period.getStartsAt(),
                period.getEndsAt(), period.getTimezoneSnapshot(), period.getStatus(), period.getVersion(),
                progress(projected), items, offer
        );
    }

    private List<ProjectedItem> projectItems(FocusPeriod period, UUID userId, boolean useLiveStatus, boolean includeHistoryOnly) {
        List<ProjectedItem> result = new ArrayList<>();
        boolean periodChanged = false;
        for (FocusItem item : itemRepository.findByPeriodIdOrderByPositionAsc(period.getId())) {
            if (item.isHistoryOnly() && !includeHistoryOnly) {
                continue;
            }
            if (!useLiveStatus && item.isShared() && accessFor(loadTask(item.getTaskId()), userId) == null) {
                if (activePeriod(period)) {
                    item.setHistoryOnly(true);
                    item.setUpdatedAt(Instant.now());
                    periodChanged = true;
                }
                continue;
            }
            String status = item.getStatus();
            boolean canWrite = item.isCanWrite();
            if (useLiveStatus) {
                LiveTask live = loadTask(item.getTaskId());
                TaskAccess access = accessFor(live, userId);
                if (live == null) {
                    itemRepository.delete(item);
                    periodChanged = true;
                    continue;
                }
                if (access == null || live.archived()) {
                    item.setHistoryOnly(true);
                    item.setUpdatedAt(Instant.now());
                    periodChanged = true;
                    continue;
                }
                status = live.status();
                canWrite = access.fullAccess();
            }
            result.add(new ProjectedItem(toDto(item, status, canWrite), status, item.getEffectiveWeight()));
        }
        if (periodChanged && activePeriod(period)) {
            touch(period);
        }
        return result;
    }

    private boolean activePeriod(FocusPeriod period) {
        return "active".equals(period.getStatus());
    }

    private List<FocusItem> rolloverItems(FocusPeriod source, UUID userId) {
        if (source.getRolloverResolvedAt() != null) {
            return List.of();
        }
        return itemRepository.findByPeriodIdOrderByPositionAsc(source.getId()).stream()
                .filter(item -> !item.isHistoryOnly())
                .filter(item -> !"done".equals(item.getStatus()))
                .filter(item -> {
                    LiveTask live = loadTask(item.getTaskId());
                    return live != null && !live.archived() && !"done".equals(live.status()) && accessFor(live, userId) != null;
                })
                .toList();
    }

    private ProgressDto progress(List<ProjectedItem> items) {
        int totalWeight = items.stream().mapToInt(ProjectedItem::weight).sum();
        int completedWeight = items.stream().filter(item -> "done".equals(item.status())).mapToInt(ProjectedItem::weight).sum();
        int completedCount = (int) items.stream().filter(item -> "done".equals(item.status())).count();
        int percent = totalWeight == 0 ? 0 : (int) Math.round(completedWeight * 100.0 / totalWeight);
        return new ProgressDto(completedWeight, totalWeight, percent, completedCount, items.size());
    }

    private FocusItem snapshot(UUID periodId, LiveTask task, TaskAccess access, int position, Instant now) {
        FocusItem item = new FocusItem();
        item.setId(UUID.randomUUID());
        item.setPeriodId(periodId);
        item.setTaskId(task.taskId());
        item.setPosition(position);
        item.setHistoryOnly(false);
        item.setTitle(task.title());
        item.setStatus(task.status());
        item.setEffort(task.effort());
        item.setEffectiveWeight(effectiveWeight(task.effort()));
        item.setPlannedTime(task.plannedTime());
        item.setDueTime(task.dueTime());
        item.setFolderId(task.folderId());
        item.setFolderTitle(task.folderTitle());
        item.setGoalId(task.goalId());
        item.setGoalTitle(task.goalTitle());
        item.setShared(access.shared() && !access.owner());
        item.setCanWrite(access.fullAccess());
        item.setSnapshotAt(now);
        item.setAddedAt(now);
        item.setUpdatedAt(now);
        return item;
    }

    private int nextPosition(UUID periodId) {
        return itemRepository.findByPeriodIdOrderByPositionAsc(periodId).stream()
                .mapToInt(FocusItem::getPosition).max().orElse(-1) + 1;
    }

    private void normalizePositions(UUID periodId) {
        List<FocusItem> items = itemRepository.findByPeriodIdOrderByPositionAsc(periodId);
        moveToTemporaryPositions(items);
        for (int i = 0; i < items.size(); i++) {
            items.get(i).setPosition(i);
        }
        itemRepository.saveAll(items);
    }

    private void moveToTemporaryPositions(List<FocusItem> items) {
        for (int i = 0; i < items.size(); i++) {
            items.get(i).setPosition(100_000 + i);
        }
        itemRepository.saveAllAndFlush(items);
    }

    private void touch(FocusPeriod period) {
        period.setUpdatedAt(Instant.now());
        periodRepository.saveAndFlush(period);
    }

    private void verifyVersion(FocusPeriod period, Long expected) {
        if (expected != null && expected != period.getVersion()) {
            throw new ApiException(HttpStatus.CONFLICT, "focus_version_conflict", "Focus was changed by another client.");
        }
    }

    private boolean isRepeated(UUID userId, String key, String operation) {
        if (key == null || key.isBlank()) {
            return false;
        }
        String existing = jdbcTemplate.query(
                "select operation from focus_idempotency_keys where user_id = ? and idempotency_key = ?",
                result -> result.next() ? result.getString(1) : null,
                userId, key
        );
        if (existing != null) {
            if (!existing.equals(operation)) {
                throw new ApiException(HttpStatus.CONFLICT, "idempotency_key_reused", "The idempotency key was used for another operation.");
            }
            return true;
        }
        jdbcTemplate.update(
                "insert into focus_idempotency_keys(user_id,idempotency_key,operation,created_at) values (?,?,?,?)",
                userId, key, operation, java.sql.Timestamp.from(Instant.now())
        );
        return false;
    }

    private FocusNotificationSettings requireSettings(UUID userId) {
        return settingsRepository.findById(userId).orElseGet(() -> {
            Instant now = Instant.now();
            FocusNotificationSettings settings = new FocusNotificationSettings();
            settings.setUserId(userId);
            settings.setCreatedAt(now);
            settings.setUpdatedAt(now);
            return settingsRepository.save(settings);
        });
    }

    private NotificationSettingsDto toSettings(FocusNotificationSettings settings) {
        return new NotificationSettingsDto(
                settings.getIntervalMinutes(), formatTime(settings.getQuietHoursStart()),
                formatTime(settings.getQuietHoursEnd()), settings.getVersion()
        );
    }

    private LiveTask requireVisibleTask(UUID taskId, UUID userId) {
        LiveTask task = loadTask(taskId);
        if (task == null || task.archived()) {
            throw notFound("Task");
        }
        requireAccess(taskId, userId);
        return task;
    }

    private TaskAccess requireAccess(UUID taskId, UUID userId) {
        return sharingAccessService.requireTaskAccess(taskId, userId);
    }

    private TaskAccess accessFor(LiveTask task, UUID userId) {
        if (task == null || task.deleted() || task.archived()) {
            return null;
        }
        try {
            return accessProbe.requireTaskAccess(task.taskId(), userId);
        } catch (ApiException exception) {
            if (exception.getStatus() == HttpStatus.NOT_FOUND) {
                return null;
            }
            throw exception;
        }
    }

    private LiveTask loadTask(UUID taskId) {
        List<LiveTask> rows = jdbcTemplate.query("""
                select t.id, t.title, t.status, t.effort, t.planned_time, t.due_time,
                       t.archived, t.deleted_at, t.created_at,
                       g.id, g.name, f.id, f.name
                  from tasks t
                  join goals g on g.id = t.goal_id
                  join folders f on f.id = g.folder_id
                 where t.id = ? and t.deleted_at is null
                """, (rs, row) -> liveTask(rs), taskId);
        return rows.isEmpty() ? null : rows.getFirst();
    }

    private LiveTask liveTask(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new LiveTask(
                rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), (Integer) rs.getObject(4),
                rs.getTimestamp(5) == null ? null : rs.getTimestamp(5).toInstant(),
                rs.getTimestamp(6) == null ? null : rs.getTimestamp(6).toInstant(),
                rs.getBoolean(7), rs.getTimestamp(8) != null, rs.getTimestamp(9).toInstant(),
                rs.getObject(10, UUID.class), rs.getString(11), rs.getObject(12, UUID.class), rs.getString(13)
        );
    }

    private LiveTask liveTask(FocusCandidateRepository.CandidateRow row) {
        return new LiveTask(
                row.getTaskId(), row.getTitle(), row.getStatus(), row.getEffort(), row.getPlannedTime(),
                row.getDueTime(), false, false, row.getCreatedAt(), row.getGoalId(), row.getGoalTitle(),
                row.getFolderId(), row.getFolderTitle()
        );
    }

    private CandidateDto toCandidate(LiveTask task, UUID userId, boolean inFocus) {
        TaskAccess access = requireAccess(task.taskId(), userId);
        return new CandidateDto(
                task.taskId(), task.title(), task.status(), task.effort(), effectiveWeight(task.effort()),
                task.plannedTime(), task.dueTime(), task.folderId(), task.folderTitle(), task.goalId(),
                task.goalTitle(), access.shared() && !access.owner(), access.fullAccess(), inFocus
        );
    }

    private ItemDto toSnapshotDto(FocusItem item) {
        return toDto(item, item.getStatus(), item.isCanWrite());
    }

    private ItemDto toDto(FocusItem item, String status, boolean canWrite) {
        return new ItemDto(
                item.getId(), item.getTaskId(), item.getTitle(), status, item.getEffort(), item.getEffectiveWeight(),
                item.getPlannedTime(), item.getDueTime(), item.getPosition(), item.isHistoryOnly(), item.getFolderId(),
                item.getFolderTitle(), item.getGoalId(), item.getGoalTitle(), item.isShared(), canWrite
        );
    }

    static int effectiveWeight(Integer effort) {
        return effort == null || effort <= 0 ? 1 : effort;
    }

    private String encodeCursor(int offset) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(Integer.toString(offset).getBytes(StandardCharsets.UTF_8));
    }

    private int decodeCursor(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return 0;
        }
        try {
            return Integer.parseInt(new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8));
        } catch (IllegalArgumentException exception) {
            throw badRequest("focus_cursor_invalid", "The candidate cursor is invalid.");
        }
    }

    private LocalTime parseTime(String value) {
        return value == null ? null : LocalTime.parse(value);
    }

    private String formatTime(LocalTime value) {
        return value == null ? null : value.toString();
    }

    private ApiException badRequest(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    private ApiException notFound(String entity) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entity + " was not found.");
    }

    private record ProjectedItem(ItemDto dto, String status, int weight) {
    }

    private record LiveTask(
            UUID taskId,
            String title,
            String status,
            Integer effort,
            Instant plannedTime,
            Instant dueTime,
            boolean archived,
            boolean deleted,
            Instant createdAt,
            UUID goalId,
            String goalTitle,
            UUID folderId,
            String folderTitle
    ) {
    }
}
