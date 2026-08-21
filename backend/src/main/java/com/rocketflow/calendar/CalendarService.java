package com.rocketflow.calendar;

import static com.rocketflow.calendar.CalendarApi.*;
import static com.rocketflow.sharing.SharingValues.SHARE_ACTIVE;

import java.nio.charset.StandardCharsets;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.common.UuidOrder;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.recurrence.RecurrenceCalculationService;
import com.rocketflow.recurrence.TaskRecurrenceRule;
import com.rocketflow.recurrence.TaskRecurrenceRuleRepository;
import com.rocketflow.sharing.GoalShare;
import com.rocketflow.sharing.GoalShareRepository;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.TaskShare;
import com.rocketflow.sharing.TaskShareRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class CalendarService {

    private static final int MAX_RANGE_DAYS = 400;
    private static final int MAX_OCCURRENCES = 10_000;
    private static final Comparator<CalendarMarkerDto> MARKER_ORDER = Comparator
            .comparing(CalendarMarkerDto::at)
            .thenComparing(CalendarMarkerDto::kind)
            .thenComparing(CalendarMarkerDto::markerId);
    private static final Comparator<Task> LEGACY_ORDER = Comparator
            .comparing(Task::getPlannedTime)
            .thenComparing(Task::getCreatedAt)
            .thenComparing(Task::getId, UuidOrder.POSTGRES_ASC);

    private final TaskRepository taskRepository;
    private final GoalRepository goalRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;
    private final SharingAccessService sharingAccessService;
    private final TaskRecurrenceRuleRepository recurrenceRuleRepository;
    private final RecurrenceCalculationService recurrenceCalculationService;
    private final UserRepository userRepository;

    public CalendarService(
            TaskRepository taskRepository,
            GoalRepository goalRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository,
            SharingAccessService sharingAccessService,
            TaskRecurrenceRuleRepository recurrenceRuleRepository,
            RecurrenceCalculationService recurrenceCalculationService,
            UserRepository userRepository
    ) {
        this.taskRepository = taskRepository;
        this.goalRepository = goalRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
        this.sharingAccessService = sharingAccessService;
        this.recurrenceRuleRepository = recurrenceRuleRepository;
        this.recurrenceCalculationService = recurrenceCalculationService;
        this.userRepository = userRepository;
    }

    @Transactional(readOnly = true)
    public CalendarMarkersResponse getCalendarMarkers(UUID actorUserId, LocalDate from, LocalDate toExclusive) {
        validateDateRange(from, toExclusive);
        User actor = requireUser(actorUserId);
        ZoneId actorZone = ZoneId.of(actor.getTimezone());
        Instant rangeStart = from.atStartOfDay(actorZone).toInstant();
        Instant rangeEnd = toExclusive.atStartOfDay(actorZone).toInstant();

        List<Task> tasks = findVisibleCandidates(actorUserId);
        Map<UUID, TaskRecurrenceRule> rules = findRules(tasks);
        Map<UUID, ZoneId> ownerZones = findOwnerZones(tasks);
        List<CalendarMarkerDto> markers = new ArrayList<>();
        OccurrenceBudget budget = new OccurrenceBudget();

        for (Task task : tasks) {
            TaskRecurrenceRule rule = rules.get(task.getId());
            if (rule == null || !rule.isActive()) {
                addSingleOccurrence(task, actorZone, rangeStart, rangeEnd, markers, budget);
                continue;
            }
            ZoneId ownerZone = ownerZones.getOrDefault(task.getOwnerUserId(), actorZone);
            addRecurringOccurrences(task, rule, ownerZone, actorZone, rangeStart, rangeEnd, markers, budget);
        }

        markers.sort(MARKER_ORDER);
        return new CalendarMarkersResponse(actorZone.getId(), from, toExclusive, List.copyOf(markers));
    }

    /** Compatibility path for clients that still send an inclusive Instant range. */
    @Transactional(readOnly = true)
    public CalendarResponse getCalendar(UUID actorUserId, Instant from, Instant to) {
        validateLegacyRange(from, to);
        return new CalendarResponse(findVisibleCandidates(actorUserId).stream()
                .filter(task -> task.getPlannedTime() != null)
                .filter(task -> !task.getPlannedTime().isBefore(from) && !task.getPlannedTime().isAfter(to))
                .sorted(LEGACY_ORDER)
                .map(this::toLegacyDto)
                .toList());
    }

    private List<Task> findVisibleCandidates(UUID actorUserId) {
        List<Task> candidates = new ArrayList<>(taskRepository.findCalendarCandidatesForOwner(actorUserId));

        List<UUID> sharedFolderIds = sharingAccessService.accessibleSharedFolders(actorUserId).stream()
                .map(access -> access.folder().getId())
                .distinct()
                .toList();
        if (!sharedFolderIds.isEmpty()) {
            List<UUID> goalIds = goalRepository.findByFolderIdInAndArchivedFalse(sharedFolderIds).stream()
                    .map(Goal::getId)
                    .toList();
            if (!goalIds.isEmpty()) {
                candidates.addAll(taskRepository.findCalendarCandidatesByGoalIds(goalIds));
            }
        }

        List<UUID> sharedGoalIds = goalShareRepository
                .findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE).stream()
                .map(GoalShare::getGoalId)
                .distinct()
                .toList();
        if (!sharedGoalIds.isEmpty()) {
            candidates.addAll(taskRepository.findCalendarCandidatesByGoalIds(sharedGoalIds));
        }

        List<UUID> sharedTaskIds = taskShareRepository
                .findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE).stream()
                .map(TaskShare::getTaskId)
                .distinct()
                .toList();
        if (!sharedTaskIds.isEmpty()) {
            candidates.addAll(taskRepository.findCalendarCandidatesByIds(sharedTaskIds));
        }

        Map<UUID, Task> deduplicated = new LinkedHashMap<>();
        for (Task task : candidates) {
            if (hasAccess(task, actorUserId)) {
                deduplicated.putIfAbsent(task.getId(), task);
            }
        }
        return List.copyOf(deduplicated.values());
    }

    private boolean hasAccess(Task task, UUID actorUserId) {
        try {
            sharingAccessService.requireTaskAccess(task.getId(), actorUserId);
            return true;
        } catch (ApiException exception) {
            return false;
        }
    }

    private Map<UUID, TaskRecurrenceRule> findRules(List<Task> tasks) {
        List<UUID> taskIds = tasks.stream().map(Task::getId).toList();
        if (taskIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, TaskRecurrenceRule> result = new HashMap<>();
        for (TaskRecurrenceRule rule : recurrenceRuleRepository.findByTaskIdIn(taskIds)) {
            result.put(rule.getTaskId(), rule);
        }
        return result;
    }

    private Map<UUID, ZoneId> findOwnerZones(List<Task> tasks) {
        Map<UUID, ZoneId> result = new HashMap<>();
        List<UUID> ownerIds = tasks.stream().map(Task::getOwnerUserId).distinct().toList();
        for (User owner : userRepository.findAllById(ownerIds)) {
            result.put(owner.getId(), ZoneId.of(owner.getTimezone()));
        }
        return result;
    }

    private void addSingleOccurrence(
            Task task,
            ZoneId actorZone,
            Instant rangeStart,
            Instant rangeEnd,
            List<CalendarMarkerDto> markers,
            OccurrenceBudget budget
    ) {
        Instant anchor = task.getPlannedTime() != null ? task.getPlannedTime() : task.getDueTime();
        UUID occurrenceId = stableId("occurrence", task.getId(), anchor.toString());
        boolean added = addMarkers(task, occurrenceId, false, task.getPlannedTime(), task.getDueTime(),
                actorZone, rangeStart, rangeEnd, markers);
        if (added) {
            budget.consume();
        }
    }

    private void addRecurringOccurrences(
            Task task,
            TaskRecurrenceRule rule,
            ZoneId ownerZone,
            ZoneId actorZone,
            Instant rangeStart,
            Instant rangeEnd,
            List<CalendarMarkerDto> markers,
            OccurrenceBudget budget
    ) {
        Instant anchor = rule.getStartAt();
        Duration plannedOffset = task.getPlannedTime() == null ? null : Duration.between(anchor, task.getPlannedTime());
        Duration dueOffset = task.getDueTime() == null ? null : Duration.between(anchor, task.getDueTime());
        List<Duration> offsets = new ArrayList<>();
        if (plannedOffset != null) {
            offsets.add(plannedOffset);
        }
        if (dueOffset != null) {
            offsets.add(dueOffset);
        }

        Instant occurrenceSearchStart = offsets.stream()
                .map(offset -> safeMinus(rangeStart, offset))
                .min(Instant::compareTo)
                .orElse(rangeStart);
        Instant occurrenceSearchEnd = offsets.stream()
                .map(offset -> safeMinus(rangeEnd, offset))
                .max(Instant::compareTo)
                .orElse(rangeEnd);

        Instant cursor = occurrenceSearchStart.equals(Instant.MIN)
                ? Instant.MIN
                : occurrenceSearchStart.minusNanos(1);
        while (true) {
            var next = recurrenceCalculationService.nextOccurrence(rule, ownerZone, cursor);
            if (next.isEmpty()) {
                return;
            }
            Instant occurrence = next.get();
            if (!occurrence.isBefore(occurrenceSearchEnd)) {
                return;
            }
            budget.consume();
            Instant plannedAt = plannedOffset == null ? null : safePlus(occurrence, plannedOffset);
            Instant dueAt = dueOffset == null ? null : safePlus(occurrence, dueOffset);
            UUID occurrenceId = stableId("occurrence", task.getId(), occurrence.toString());
            addMarkers(task, occurrenceId, true, plannedAt, dueAt,
                    actorZone, rangeStart, rangeEnd, markers);
            cursor = occurrence;
        }
    }

    private boolean addMarkers(
            Task task,
            UUID occurrenceId,
            boolean recurring,
            Instant plannedAt,
            Instant dueAt,
            ZoneId actorZone,
            Instant rangeStart,
            Instant rangeEnd,
            List<CalendarMarkerDto> markers
    ) {
        boolean added = false;
        if (isWithin(plannedAt, rangeStart, rangeEnd)) {
            markers.add(toMarker(task, occurrenceId, "planned", plannedAt, actorZone, recurring));
            added = true;
        }
        if (isWithin(dueAt, rangeStart, rangeEnd)) {
            markers.add(toMarker(task, occurrenceId, "deadline", dueAt, actorZone, recurring));
            added = true;
        }
        return added;
    }

    private CalendarMarkerDto toMarker(
            Task task,
            UUID occurrenceId,
            String kind,
            Instant at,
            ZoneId actorZone,
            boolean recurring
    ) {
        return new CalendarMarkerDto(
                stableId("marker", occurrenceId, kind),
                occurrenceId,
                task.getId(),
                task.getGoalId(),
                task.getTitle(),
                task.getStatus(),
                task.getEffort(),
                kind,
                at,
                at.atZone(actorZone).toLocalDate(),
                recurring
        );
    }

    private CalendarItemDto toLegacyDto(Task task) {
        return new CalendarItemDto(
                task.getId(),
                task.getGoalId(),
                task.getTitle(),
                task.getType(),
                task.getPriority(),
                task.getStatus(),
                task.getPlannedTime(),
                task.getDueTime()
        );
    }

    private boolean isWithin(Instant value, Instant from, Instant toExclusive) {
        return value != null && !value.isBefore(from) && value.isBefore(toExclusive);
    }

    private UUID stableId(String namespace, Object first, String second) {
        return UUID.nameUUIDFromBytes((namespace + ":" + first + ":" + second).getBytes(StandardCharsets.UTF_8));
    }

    private Instant safeMinus(Instant instant, Duration duration) {
        try {
            return instant.minus(duration);
        } catch (ArithmeticException | DateTimeException exception) {
            return duration.isNegative() ? Instant.MAX : Instant.MIN;
        }
    }

    private Instant safePlus(Instant instant, Duration duration) {
        try {
            return instant.plus(duration);
        } catch (ArithmeticException | DateTimeException exception) {
            return duration.isNegative() ? Instant.MIN : Instant.MAX;
        }
    }

    private User requireUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "User was not found."));
    }

    private void validateDateRange(LocalDate from, LocalDate toExclusive) {
        if (from == null || toExclusive == null) {
            throw validationError("Calendar date range requires from and toExclusive.");
        }
        long days = ChronoUnit.DAYS.between(from, toExclusive);
        if (days <= 0) {
            throw validationError("Calendar date range must be non-empty.");
        }
        if (days > MAX_RANGE_DAYS) {
            throw validationError("Calendar date range cannot exceed " + MAX_RANGE_DAYS + " days.");
        }
    }

    private void validateLegacyRange(Instant from, Instant to) {
        if (from == null || to == null) {
            throw validationError("Calendar range requires from and to.");
        }
        if (from.isAfter(to)) {
            throw validationError("Calendar range is invalid.");
        }
    }

    private ApiException validationError(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "validation_error", message);
    }

    private static final class OccurrenceBudget {
        private int used;

        private void consume() {
            used++;
            if (used > MAX_OCCURRENCES) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "calendar_occurrence_limit",
                        "Calendar range expands to too many occurrences."
                );
            }
        }
    }
}
