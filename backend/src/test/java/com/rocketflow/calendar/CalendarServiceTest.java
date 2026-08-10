package com.rocketflow.calendar;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.folders.Folder;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.recurrence.RecurrenceCalculationService;
import com.rocketflow.recurrence.TaskRecurrenceRule;
import com.rocketflow.recurrence.TaskRecurrenceRuleRepository;
import com.rocketflow.sharing.GoalShareRepository;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.TaskShareRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class CalendarServiceTest {

    private static final UUID ACTOR_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");

    @Mock
    private TaskRepository taskRepository;
    @Mock
    private GoalRepository goalRepository;
    @Mock
    private GoalShareRepository goalShareRepository;
    @Mock
    private TaskShareRepository taskShareRepository;
    @Mock
    private SharingAccessService sharingAccessService;
    @Mock
    private TaskRecurrenceRuleRepository recurrenceRuleRepository;
    @Mock
    private UserRepository userRepository;

    private CalendarService service;

    @BeforeEach
    void setUp() {
        service = new CalendarService(
                taskRepository,
                goalRepository,
                goalShareRepository,
                taskShareRepository,
                sharingAccessService,
                recurrenceRuleRepository,
                new RecurrenceCalculationService(),
                userRepository
        );
        when(goalShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(any(), any()))
                .thenReturn(List.of());
        when(taskShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(any(), any()))
                .thenReturn(List.of());
        when(sharingAccessService.accessibleSharedFolders(any())).thenReturn(List.of());
    }

    @Test
    void includesDueOnlyTaskAndBothMarkersForDualDateTask() {
        User actor = user(ACTOR_ID, "Europe/Moscow");
        Task dueOnly = task("Due only", null, Instant.parse("2026-08-10T09:00:00Z"));
        Task dual = task(
                "Dual",
                Instant.parse("2026-08-10T07:00:00Z"),
                Instant.parse("2026-08-10T12:00:00Z")
        );
        stubOwned(actor, List.of(dueOnly, dual));

        var response = service.getCalendarMarkers(
                ACTOR_ID,
                LocalDate.parse("2026-08-10"),
                LocalDate.parse("2026-08-11")
        );

        assertEquals("Europe/Moscow", response.timezone());
        assertEquals(3, response.markers().size());
        assertEquals(List.of("planned", "deadline", "deadline"),
                response.markers().stream().map(CalendarApi.CalendarMarkerDto::kind).toList());
        assertEquals(response.markers().get(0).occurrenceId(), response.markers().get(2).occurrenceId());
    }

    @Test
    void expandsDailyRecurrenceAcrossDstAndPreservesDeadlineOffset() {
        User actor = user(ACTOR_ID, "America/New_York");
        Task recurring = task(
                "DST recurrence",
                Instant.parse("2026-03-07T14:00:00Z"),
                Instant.parse("2026-03-07T16:00:00Z")
        );
        recurring.setOwnerUserId(OWNER_ID);
        TaskRecurrenceRule rule = dailyRule(recurring.getId(), recurring.getPlannedTime());
        stubOwned(actor, List.of(recurring));
        when(recurrenceRuleRepository.findByTaskIdIn(anyList())).thenReturn(List.of(rule));
        when(userRepository.findAllById(anyList())).thenReturn(List.of(user(OWNER_ID, "America/New_York")));

        var response = service.getCalendarMarkers(
                ACTOR_ID,
                LocalDate.parse("2026-03-07"),
                LocalDate.parse("2026-03-10")
        );

        assertEquals(6, response.markers().size());
        assertEquals(List.of(
                        Instant.parse("2026-03-07T14:00:00Z"),
                        Instant.parse("2026-03-08T13:00:00Z"),
                        Instant.parse("2026-03-09T13:00:00Z")
                ), response.markers().stream()
                        .filter(marker -> marker.kind().equals("planned"))
                        .map(CalendarApi.CalendarMarkerDto::at)
                        .toList());
        assertEquals(List.of(2L, 2L, 2L), response.markers().stream()
                .filter(marker -> marker.kind().equals("deadline"))
                .map(marker -> java.time.Duration.between(
                        response.markers().stream()
                                .filter(planned -> planned.occurrenceId().equals(marker.occurrenceId())
                                        && planned.kind().equals("planned"))
                                .findFirst().orElseThrow().at(),
                        marker.at()).toHours())
                .toList());
    }

    @Test
    void includesAccessibleFolderDescendantsAndFiltersFailedAccessChecks() {
        User actor = user(ACTOR_ID, "UTC");
        Folder descendant = new Folder();
        descendant.setId(UUID.randomUUID());
        Goal goal = new Goal();
        goal.setId(UUID.randomUUID());
        Task visible = task("Visible shared", Instant.parse("2026-08-10T10:00:00Z"), null);
        Task leaked = task("Revoked", Instant.parse("2026-08-10T11:00:00Z"), null);

        when(userRepository.findById(ACTOR_ID)).thenReturn(Optional.of(actor));
        when(taskRepository.findCalendarCandidatesForOwner(ACTOR_ID)).thenReturn(List.of());
        when(sharingAccessService.accessibleSharedFolders(ACTOR_ID))
                .thenReturn(List.of(new SharingAccessService.FolderAccess(descendant, false, true, false)));
        when(goalRepository.findByFolderIdInAndArchivedFalse(List.of(descendant.getId()))).thenReturn(List.of(goal));
        when(taskRepository.findCalendarCandidatesByGoalIds(List.of(goal.getId()))).thenReturn(List.of(visible, leaked));
        when(sharingAccessService.requireTaskAccess(visible.getId(), ACTOR_ID))
                .thenReturn(new SharingAccessService.TaskAccess(visible, false, true, false));
        when(sharingAccessService.requireTaskAccess(leaked.getId(), ACTOR_ID))
                .thenThrow(mock(ApiException.class));
        when(recurrenceRuleRepository.findByTaskIdIn(anyList())).thenReturn(List.of());
        when(userRepository.findAllById(anyList())).thenReturn(List.of(user(OWNER_ID, "UTC")));

        var response = service.getCalendarMarkers(
                ACTOR_ID,
                LocalDate.parse("2026-08-10"),
                LocalDate.parse("2026-08-11")
        );

        assertEquals(1, response.markers().size());
        assertEquals("Visible shared", response.markers().getFirst().title());
    }

    @Test
    void validatesEmptyAndOversizedDateRanges() {
        assertThrows(ApiException.class, () -> service.getCalendarMarkers(
                ACTOR_ID,
                LocalDate.parse("2026-08-10"),
                LocalDate.parse("2026-08-10")
        ));
        assertThrows(ApiException.class, () -> service.getCalendarMarkers(
                ACTOR_ID,
                LocalDate.parse("2026-01-01"),
                LocalDate.parse("2027-03-01")
        ));
    }

    private void stubOwned(User actor, List<Task> tasks) {
        when(userRepository.findById(ACTOR_ID)).thenReturn(Optional.of(actor));
        when(taskRepository.findCalendarCandidatesForOwner(ACTOR_ID)).thenReturn(tasks);
        for (Task task : tasks) {
            when(sharingAccessService.requireTaskAccess(task.getId(), ACTOR_ID))
                    .thenReturn(new SharingAccessService.TaskAccess(task, true, false, true));
        }
        when(recurrenceRuleRepository.findByTaskIdIn(anyList())).thenReturn(List.of());
        when(userRepository.findAllById(anyList())).thenReturn(List.of(actor));
    }

    private User user(UUID id, String timezone) {
        User user = new User();
        user.setId(id);
        user.setTimezone(timezone);
        return user;
    }

    private Task task(String title, Instant planned, Instant due) {
        Task task = new Task();
        task.setId(UUID.randomUUID());
        task.setGoalId(UUID.randomUUID());
        task.setOwnerUserId(ACTOR_ID);
        task.setTitle(title);
        task.setStatus("todo");
        task.setEffort(3);
        task.setPlannedTime(planned);
        task.setDueTime(due);
        task.setCreatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        return task;
    }

    private TaskRecurrenceRule dailyRule(UUID taskId, Instant start) {
        TaskRecurrenceRule rule = new TaskRecurrenceRule();
        rule.setId(UUID.randomUUID());
        rule.setTaskId(taskId);
        rule.setMode("daily");
        rule.setIntervalValue(1);
        rule.setStartAt(start);
        rule.setActive(true);
        return rule;
    }
}
