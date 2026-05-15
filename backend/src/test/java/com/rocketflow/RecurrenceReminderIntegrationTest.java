package com.rocketflow;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rocketflow.recurrence.RecurrenceCalculationService;
import com.rocketflow.recurrence.TaskRecurrenceRule;
import com.rocketflow.recurrence.TaskRecurrenceRuleRepository;
import com.rocketflow.reminders.ReminderEligibilityService;
import com.rocketflow.reminders.TaskReminderRule;
import com.rocketflow.reminders.TaskReminderRuleRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class RecurrenceReminderIntegrationTest {

    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private TaskRecurrenceRuleRepository recurrenceRuleRepository;

    @Autowired
    private TaskReminderRuleRepository reminderRuleRepository;

    @Autowired
    private RecurrenceCalculationService recurrenceCalculationService;

    @Autowired
    private ReminderEligibilityService reminderEligibilityService;

    @Autowired
    private TaskRepository taskRepository;

    @DynamicPropertySource
    static void configureDatasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> POSTGRES.getJdbcUrl("postgres", "postgres"));
        registry.add("spring.datasource.username", () -> "postgres");
        registry.add("spring.datasource.password", () -> "postgres");
    }

    @BeforeEach
    void cleanDatabase() throws Exception {
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.createStatement()) {
            statement.executeUpdate(
                    "truncate table task_reminder_rules, task_recurrence_rules, task_tag_links, task_tags, tasks, goals, folders, task_shares, goal_shares, share_invitations, auth_sessions, user_settings, user_credentials, users cascade"
            );
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void recurrenceIsPersistedAndExposedThroughTaskReads() throws Exception {
        String accessToken = accessToken();
        String taskId = createTask(accessToken, """
                {
                  "title": "Weekly planning",
                  "description": "Review the week",
                  "type": "green",
                  "priority": 6,
                  "status": "todo",
                  "plannedTime": "2026-05-04T06:00:00Z",
                  "dueTime": "2026-05-04T08:00:00Z"
                }
                """);

        mockMvc.perform(put("/api/tasks/" + taskId + "/recurrence")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "weekly",
                                  "interval": 1,
                                  "daysOfWeek": ["MONDAY", "WEDNESDAY"],
                                  "startAt": "2026-05-04T06:00:00Z",
                                  "endAt": null,
                                  "active": true
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recurrence.mode").value("weekly"))
                .andExpect(jsonPath("$.recurrence.daysOfWeek[0]").value("MONDAY"));

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recurrence.mode").value("weekly"))
                .andExpect(jsonPath("$.recurrence.daysOfWeek[1]").value("WEDNESDAY"));
    }

    @Test
    void weeklyRecurrenceRequiresWeekdays() throws Exception {
        String accessToken = accessToken();
        String taskId = createTask(accessToken, """
                {
                  "title": "No weekdays",
                  "description": null,
                  "type": "green",
                  "priority": 5,
                  "status": "todo",
                  "plannedTime": "2026-05-04T06:00:00Z",
                  "dueTime": null
                }
                """);

        mockMvc.perform(put("/api/tasks/" + taskId + "/recurrence")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "weekly",
                                  "interval": 1,
                                  "daysOfWeek": [],
                                  "startAt": "2026-05-04T06:00:00Z",
                                  "endAt": null,
                                  "active": true
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_error"));
    }

    @Test
    void serverSideTaskReminderEndpointIsGoneAndTaskDtoDoesNotExposeReminders() throws Exception {
        String accessToken = accessToken();
        String taskId = createTask(accessToken, """
                {
                  "title": "Submit report",
                  "description": "Send final copy",
                  "type": "red",
                  "priority": 9,
                  "status": "todo",
                  "plannedTime": "2026-05-04T09:00:00Z",
                  "dueTime": "2026-05-05T15:00:00Z"
                }
                """);

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "reminders": [
                                    {
                                      "mode": "before_planned_time",
                                      "offsetMinutes": 30,
                                      "active": true
                                    },
                                    {
                                      "mode": "before_due_time",
                                      "offsetMinutes": 1440,
                                      "active": true
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("reminders_not_supported"));

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reminders").doesNotExist());
    }

    @Test
    void serverSideTaskReminderEndpointIsGoneForDueOnlyTasks() throws Exception {
        String accessToken = accessToken();
        String taskId = createTask(accessToken, """
                {
                  "title": "Due-only task",
                  "description": null,
                  "type": "red",
                  "priority": 4,
                  "status": "todo",
                  "plannedTime": null,
                  "dueTime": "2026-05-05T15:00:00Z"
                }
                """);

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "reminders": [
                                    {
                                      "mode": "before_planned_time",
                                      "offsetMinutes": 30,
                                      "active": true
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("reminders_not_supported"));
    }

    @Test
    void ownerTimezoneDrivesWeeklyAnchors() throws Exception {
        String accessToken = accessToken();
        String taskId = createTask(accessToken, """
                {
                  "title": "Timezone-sensitive task",
                  "description": "Local Monday after midnight",
                  "type": "green",
                  "priority": 7,
                  "status": "todo",
                  "plannedTime": "2026-05-03T21:30:00Z",
                  "dueTime": "2026-05-04T03:00:00Z"
                }
                """);

        mockMvc.perform(put("/api/tasks/" + taskId + "/recurrence")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "weekly",
                                  "interval": 1,
                                  "daysOfWeek": ["MONDAY"],
                                  "startAt": "2026-05-03T21:30:00Z",
                                  "endAt": null,
                                  "active": true
                                }
                                """))
                .andExpect(status().isOk());

        UUID taskUuid = UUID.fromString(taskId);
        TaskRecurrenceRule recurrenceRule = recurrenceRuleRepository.findByTaskId(taskUuid).orElseThrow();
        Optional<Instant> nextOccurrence = recurrenceCalculationService.nextOccurrence(
                recurrenceRule,
                ZoneId.of("Europe/Moscow"),
                Instant.parse("2026-05-03T21:31:00Z")
        );
        assertTrue(nextOccurrence.isPresent());
        assertEquals(Instant.parse("2026-05-10T21:30:00Z"), nextOccurrence.orElseThrow());
    }

    private String accessToken() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "scheduler@example.com",
                                  "password": "strong-password",
                                  "displayName": "Scheduler",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """))
                .andExpect(status().isCreated());

        String loginResponse = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "scheduler@example.com",
                                  "password": "strong-password"
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        return read(loginResponse, "/tokens/accessToken");
    }

    private String createTask(String accessToken, String taskPayload) throws Exception {
        String folderResponse = mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work",
                                  "description": "Scheduling work"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String folderId = read(folderResponse, "/id");

        String goalResponse = mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Execution",
                                  "description": "Keep it moving"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String goalId = read(goalResponse, "/id");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPayload))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();

        return read(taskResponse, "/id");
    }

    private String read(String json, String path) throws Exception {
        JsonNode root = objectMapper.readTree(json);
        JsonNode value = root.at(path);
        return value.isTextual() ? value.asText() : value.toString();
    }

    private static EmbeddedPostgres startPostgres() {
        try {
            return EmbeddedPostgres.start();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to start embedded PostgreSQL", exception);
        }
    }
}
