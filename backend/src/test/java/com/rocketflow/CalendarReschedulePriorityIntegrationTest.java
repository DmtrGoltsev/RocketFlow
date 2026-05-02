package com.rocketflow;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;
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
import com.rocketflow.calendar.TaskRescheduleEvent;
import com.rocketflow.calendar.TaskRescheduleEventRepository;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class CalendarReschedulePriorityIntegrationTest {

    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private TaskRescheduleEventRepository taskRescheduleEventRepository;

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
            statement.executeUpdate("""
                    truncate table
                        task_reschedule_events,
                        task_reminder_rules,
                        task_recurrence_rules,
                        task_shares,
                        goal_shares,
                        share_invitations,
                        task_tag_links,
                        task_tags,
                        tasks,
                        goals,
                        folders,
                        auth_sessions,
                        user_settings,
                        user_credentials,
                        users cascade
                    """);
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void calendarReturnsOwnerAndCollaboratorVisibleTasksWithinWindow() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");

        String folderId = createFolder(owner.accessToken());
        String sharedGoalId = read(createGoal(owner.accessToken(), folderId, "Shared Goal"), "/id");
        String sharedGoalTaskId = read(createTask(
                owner.accessToken(),
                sharedGoalId,
                "Shared goal task",
                "green",
                8,
                "2026-05-01T09:00:00Z",
                "2026-05-01T12:00:00Z"
        ), "/id");

        String privateGoalId = read(createGoal(owner.accessToken(), folderId, "Private Goal"), "/id");
        createTask(
                owner.accessToken(),
                privateGoalId,
                "Owner only task",
                "red",
                7,
                "2026-05-01T11:00:00Z",
                "2026-05-01T14:00:00Z"
        );

        String directGoalId = read(createGoal(owner.accessToken(), folderId, "Direct Share Goal"), "/id");
        String directTaskId = read(createTask(
                owner.accessToken(),
                directGoalId,
                "Direct share task",
                "green",
                6,
                "2026-05-01T15:00:00Z",
                "2026-05-01T16:00:00Z"
        ), "/id");

        createTask(
                owner.accessToken(),
                sharedGoalId,
                "Out of range task",
                "green",
                5,
                "2026-05-02T09:00:00Z",
                "2026-05-02T10:00:00Z"
        );

        String goalInvitationId = shareGoal(owner.accessToken(), sharedGoalId, collaborator.email());
        acceptInvitation(collaborator.accessToken(), goalInvitationId);

        String taskInvitationId = shareTask(owner.accessToken(), directTaskId, collaborator.email());
        acceptInvitation(collaborator.accessToken(), taskInvitationId);

        mockMvc.perform(get("/api/calendar")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .param("from", "2026-05-01T00:00:00Z")
                        .param("to", "2026-05-01T23:59:59Z"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(2))
                .andExpect(jsonPath("$.items[0].taskId").value(sharedGoalTaskId))
                .andExpect(jsonPath("$.items[1].taskId").value(directTaskId));

        mockMvc.perform(get("/api/calendar")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .param("from", "2026-05-01T00:00:00Z")
                        .param("to", "2026-05-01T23:59:59Z"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(3))
                .andExpect(jsonPath("$.items[0].taskId").value(sharedGoalTaskId))
                .andExpect(jsonPath("$.items[1].title").value("Owner only task"))
                .andExpect(jsonPath("$.items[2].taskId").value(directTaskId));
    }

    @Test
    void moveLaterCreatesAuditTrailAndAppliesDecayAfterThreshold() throws Exception {
        Session owner = registerAndLogin("scheduler@example.com", "Scheduler");
        String taskId = createOwnedTask(owner.accessToken(), """
                {
                  "title": "Prepare launch draft",
                  "description": "Move it forward",
                  "type": "green",
                  "priority": 5,
                  "status": "todo",
                  "plannedTime": "2026-05-01T09:00:00Z",
                  "dueTime": "2026-05-01T18:00:00Z"
                }
                """);

        mockMvc.perform(post("/api/tasks/" + taskId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "plannedTime": "2026-05-01T21:00:00Z"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(5));

        mockMvc.perform(post("/api/tasks/" + taskId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "plannedTime": "2026-05-02T10:00:00Z"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plannedTime").value("2026-05-02T10:00:00Z"))
                .andExpect(jsonPath("$.priority").value(4));

        List<TaskRescheduleEvent> events = taskRescheduleEventRepository.findByTaskIdOrderByCreatedAtAsc(UUID.fromString(taskId));
        assertEquals(2, events.size());

        TaskRescheduleEvent firstEvent = events.get(0);
        assertEquals(owner.userId(), firstEvent.getRescheduledByUserId());
        assertEquals(Instant.parse("2026-05-01T09:00:00Z"), firstEvent.getPreviousPlannedTime());
        assertEquals(Instant.parse("2026-05-01T21:00:00Z"), firstEvent.getNewPlannedTime());
        assertEquals(5, firstEvent.getPriorityBefore());
        assertEquals(5, firstEvent.getPriorityAfter());
        assertFalse(firstEvent.isPriorityDecayApplied());
        assertNotNull(firstEvent.getCreatedAt());

        TaskRescheduleEvent secondEvent = events.get(1);
        assertEquals(Instant.parse("2026-05-01T21:00:00Z"), secondEvent.getPreviousPlannedTime());
        assertEquals(Instant.parse("2026-05-02T10:00:00Z"), secondEvent.getNewPlannedTime());
        assertEquals(5, secondEvent.getPriorityBefore());
        assertEquals(4, secondEvent.getPriorityAfter());
        assertTrue(secondEvent.isPriorityDecayApplied());
    }

    @Test
    void quickRescheduleRejectsTaskWithoutPlannedTime() throws Exception {
        Session owner = registerAndLogin("noplan@example.com", "No Plan");
        String taskId = createOwnedTask(owner.accessToken(), """
                {
                  "title": "Unplanned task",
                  "description": null,
                  "type": "green",
                  "priority": 4,
                  "status": "todo",
                  "plannedTime": null,
                  "dueTime": "2026-05-03T18:00:00Z"
                }
                """);

        mockMvc.perform(post("/api/tasks/" + taskId + "/reschedule")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "preset": "1h"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_error"));
    }

    @Test
    void collaboratorQuickRescheduleIsOwnerOnly() throws Exception {
        Session owner = registerAndLogin("policy-owner@example.com", "Policy Owner");
        Session collaborator = registerAndLogin("policy-collaborator@example.com", "Policy Collaborator");
        updateGreenPolicy(collaborator.accessToken(), false, "month", 1);

        String taskId = createOwnedTask(owner.accessToken(), """
                {
                  "title": "Shared follow-up",
                  "description": "Owner policy should apply",
                  "type": "green",
                  "priority": 7,
                  "status": "todo",
                  "plannedTime": "2026-05-01T09:00:00Z",
                  "dueTime": "2026-05-01T18:00:00Z"
                }
                """);

        String invitationId = shareTask(owner.accessToken(), taskId, collaborator.email());
        acceptInvitation(collaborator.accessToken(), invitationId);

        mockMvc.perform(post("/api/tasks/" + taskId + "/reschedule")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "preset": "24h"
                        }
                        """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        List<TaskRescheduleEvent> events = taskRescheduleEventRepository.findByTaskIdOrderByCreatedAtAsc(UUID.fromString(taskId));
        assertEquals(0, events.size());
    }

    private Session registerAndLogin(String email, String displayName) throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s",
                                  "password": "strong-password",
                                  "displayName": "%s",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """.formatted(email, displayName)))
                .andExpect(status().isCreated());

        String loginResponse = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s",
                                  "password": "strong-password"
                                }
                                """.formatted(email)))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        return new Session(
                read(loginResponse, "/tokens/accessToken"),
                UUID.fromString(read(loginResponse, "/user/id")),
                email
        );
    }

    private String createFolder(String accessToken) throws Exception {
        String response = mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work",
                                  "description": "Scheduling work"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return read(response, "/id");
    }

    private String createGoal(String accessToken, String folderId, String name) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Goal description"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createTask(
            String accessToken,
            String goalId,
            String title,
            String type,
            int priority,
            String plannedTime,
            String dueTime
    ) throws Exception {
        String dueTimeValue = dueTime == null ? "null" : "\"" + dueTime + "\"";
        String plannedTimeValue = plannedTime == null ? "null" : "\"" + plannedTime + "\"";
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "description": "Task description",
                                  "type": "%s",
                                  "priority": %s,
                                  "status": "todo",
                                  "plannedTime": %s,
                                  "dueTime": %s,
                                  "tagIds": []
                                }
                                """.formatted(title, type, priority, plannedTimeValue, dueTimeValue)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createOwnedTask(String accessToken, String taskPayload) throws Exception {
        String folderId = createFolder(accessToken);
        String goalId = read(createGoal(accessToken, folderId, "Execution"), "/id");
        return read(mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPayload))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");
    }

    private String shareGoal(String accessToken, String goalId, String email) throws Exception {
        String response = mockMvc.perform(post("/api/goals/" + goalId + "/share")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s"
                                }
                                """.formatted(email)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return read(response, "/id");
    }

    private String shareTask(String accessToken, String taskId, String email) throws Exception {
        String response = mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s"
                                }
                                """.formatted(email)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return read(response, "/id");
    }

    private void acceptInvitation(String accessToken, String invitationId) throws Exception {
        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk());
    }

    private void updateGreenPolicy(String accessToken, boolean enabled, String thresholdPreset, int decayAmount) throws Exception {
        String settingsResponse = mockMvc.perform(get("/api/me/settings")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String version = read(settingsResponse, "/version");

        mockMvc.perform(patch("/api/me/settings")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "language": "ru",
                                  "greenPriorityDecayPolicy": {
                                    "enabled": %s,
                                    "thresholdPreset": "%s",
                                    "decayAmount": %s
                                  },
                                  "redPriorityDecayPolicy": {
                                    "enabled": true,
                                    "thresholdPreset": "week",
                                    "decayAmount": 1
                                  },
                                  "notificationsEnabled": true,
                                  "version": %s
                                }
                                """.formatted(enabled, thresholdPreset, decayAmount, version)))
                .andExpect(status().isOk());
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

    private record Session(String accessToken, UUID userId, String email) {
    }
}
