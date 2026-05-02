package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class SharingIntegrationTest {

    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

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
                        folder_shares,
                        task_shares,
                        goal_shares,
                        share_links,
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
    void goalShareAcceptEnablesCollaborativeGoalAndTaskAccess() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");

        String folderId = createFolder(owner.accessToken());
        String goalResponse = createGoal(owner.accessToken(), folderId, "Promotion", "Grow into the next role");
        String goalId = read(goalResponse, "/id");
        String goalVersion = read(goalResponse, "/version");

        String taskResponse = createTask(owner.accessToken(), goalId, "Prepare promotion plan", 8);
        String taskId = read(taskResponse, "/id");

        String invitationResponse = mockMvc.perform(post("/api/goals/" + goalId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "collaborator@example.com"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("goal"))
                .andExpect(jsonPath("$.status").value("pending"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String invitationId = read(invitationResponse, "/id");

        mockMvc.perform(get("/api/shares/invitations")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(invitationId))
                .andExpect(jsonPath("$.items[0].status").value("pending"));

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(invitationId))
                .andExpect(jsonPath("$.status").value("accepted"));

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shared").value(true));

        String collaboratorGoalResponse = mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(goalId))
                .andExpect(jsonPath("$.shared").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String collaboratorGoalVersion = read(collaboratorGoalResponse, "/version");

        mockMvc.perform(patch("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Promotion 2026",
                                  "description": "Grow into the next role this year",
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(collaboratorGoalVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(patch("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Promotion 2026",
                                  "description": "Grow into the next role this year",
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(goalVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Promotion 2026"))
                .andExpect(jsonPath("$.shared").value(true));

        String collaboratorTaskResponse = mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(taskId))
                .andExpect(jsonPath("$.items[0].shared").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String collaboratorTaskVersion = read(collaboratorTaskResponse, "/items/0/version");

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Prepare promotion plan draft",
                                  "description": "Outline achievements and next steps in writing",
                                  "type": "green",
                                  "priority": 7,
                                  "status": "in_progress",
                                  "plannedTime": "2026-05-01T10:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "archived": false,
                                  "tagIds": [],
                                  "version": %s
                                }
                                """.formatted(collaboratorTaskVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(put("/api/tasks/" + taskId + "/recurrence")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "weekly",
                                  "interval": 1,
                                  "daysOfWeek": ["FRIDAY"],
                                  "startAt": "2026-05-01T10:00:00Z",
                                  "endAt": null,
                                  "active": true
                                }
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
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
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(delete("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(post("/api/tasks/" + taskId + "/move")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "plannedTime": "2026-05-03T09:00:00Z"
                                }
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(post("/api/tasks/" + taskId + "/reschedule")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "preset": "1h"
                                }
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Prepare promotion plan draft",
                                  "description": "Outline achievements and next steps in writing",
                                  "type": "green",
                                  "priority": 7,
                                  "status": "in_progress",
                                  "plannedTime": "2026-05-01T10:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "archived": false,
                                  "tagIds": [],
                                  "version": %s
                                }
                                """.formatted(collaboratorTaskVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Prepare promotion plan draft"))
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(put("/api/tasks/" + taskId + "/recurrence")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "weekly",
                                  "interval": 1,
                                  "daysOfWeek": ["FRIDAY"],
                                  "startAt": "2026-05-01T10:00:00Z",
                                  "endAt": null,
                                  "active": true
                                }
                                """))
                .andExpect(status().isOk());

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + owner.accessToken())
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
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Schedule 1:1 with manager",
                                  "description": "Discuss timeline and expectations",
                                  "type": "green",
                                  "priority": 6,
                                  "status": "todo",
                                  "plannedTime": "2026-05-03T09:00:00Z",
                                  "dueTime": "2026-05-03T18:00:00Z",
                                  "tagIds": []
                                }
                                """))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goals[0].id").value(goalId))
                .andExpect(jsonPath("$.goals[0].shared").value(true))
                .andExpect(jsonPath("$.tasks.length()").value(1))
                .andExpect(jsonPath("$.tasks[0].shared").value(true))
                .andExpect(jsonPath("$.tasks[0].recurrence.mode").value("weekly"))
                .andExpect(jsonPath("$.tasks[0].reminders[0].mode").value("before_planned_time"));
    }

    @Test
    void directTaskShareDeclineDuplicateAndRevokeAreEnforced() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session taskCollaborator = registerAndLogin("tasker@example.com", "Tasker");
        Session decliner = registerAndLogin("decliner@example.com", "Decliner");

        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId, "Work", "Main work area"), "/id");
        String taskId = read(createTask(owner.accessToken(), goalId, "Prepare status update", 5), "/id");

        String declinedInvitationId = read(mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "decliner@example.com"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        mockMvc.perform(post("/api/shares/invitations/" + declinedInvitationId + "/decline")
                        .header("Authorization", "Bearer " + decliner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("declined"));

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + decliner.accessToken()))
                .andExpect(status().isNotFound());

        String acceptedInvitationResponse = mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "tasker@example.com"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("task"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String acceptedInvitationId = read(acceptedInvitationResponse, "/id");

        mockMvc.perform(post("/api/shares/invitations/" + acceptedInvitationId + "/accept")
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));

        String collaboratorTaskResponse = mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(taskId))
                .andExpect(jsonPath("$.shared").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String collaboratorTaskVersion = read(collaboratorTaskResponse, "/version");

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Prepare status update draft",
                                  "description": "Collect highlights and risks",
                                  "type": "green",
                                  "priority": 4,
                                  "status": "in_progress",
                                  "plannedTime": "2026-05-04T09:00:00Z",
                                  "dueTime": "2026-05-04T18:00:00Z",
                                  "archived": false,
                                  "tagIds": [],
                                  "version": %s
                                }
                                """.formatted(collaboratorTaskVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goals.length()").value(0))
                .andExpect(jsonPath("$.tasks.length()").value(1))
                .andExpect(jsonPath("$.tasks[0].id").value(taskId));

        mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "tasker@example.com"
                                }
                                """))
                .andExpect(status().isConflict());

        mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "owner@example.com"
                                }
                                """))
                .andExpect(status().isBadRequest());

        mockMvc.perform(post("/api/shares/invitations/" + acceptedInvitationId + "/revoke")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("revoked"));

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + taskCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goals.length()").value(0))
                .andExpect(jsonPath("$.tasks.length()").value(0));
    }

    @Test
    void folderShareByUserIdAndShareLinksExposeReadOnlyResources() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session folderCollaborator = registerAndLogin("folder-collaborator@example.com", "Folder Collaborator");
        Session linkCollaborator = registerAndLogin("link-collaborator@example.com", "Link Collaborator");
        Session outsider = registerAndLogin("outsider@example.com", "Outsider");

        String folderId = createFolder(owner.accessToken());
        String goalResponse = createGoal(owner.accessToken(), folderId, "Roadmap", "Product work");
        String goalId = read(goalResponse, "/id");
        String taskId = read(createTask(owner.accessToken(), goalId, "Write backend contract", 7), "/id");
        String folderCollaboratorUserId = userId("folder-collaborator@example.com");

        String folderInvitationResponse = mockMvc.perform(post("/api/folders/" + folderId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "userId": "%s"
                                }
                                """.formatted(folderCollaboratorUserId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("folder"))
                .andExpect(jsonPath("$.targetId").value(folderId))
                .andExpect(jsonPath("$.targetUserId").value(folderCollaboratorUserId))
                .andExpect(jsonPath("$.targetEmail").value("folder-collaborator@example.com"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String folderInvitationId = read(folderInvitationResponse, "/id");

        mockMvc.perform(post("/api/folders/" + folderId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "userId": "%s"
                                }
                                """.formatted(folderCollaboratorUserId)))
                .andExpect(status().isConflict());

        mockMvc.perform(post("/api/shares/invitations/" + folderInvitationId + "/accept")
                        .header("Authorization", "Bearer " + folderCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));

        mockMvc.perform(get("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + folderCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(goalId))
                .andExpect(jsonPath("$.items[0].shared").value(true));

        String sharedTaskResponse = mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + folderCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(taskId))
                .andExpect(jsonPath("$.items[0].shared").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String sharedTaskVersion = read(sharedTaskResponse, "/items/0/version");

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + folderCollaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Write backend contract draft",
                                  "description": "Task description",
                                  "type": "green",
                                  "priority": 7,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "archived": false,
                                  "tagIds": [],
                                  "version": %s
                                }
                                """.formatted(sharedTaskVersion)))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + folderCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folders[0].id").value(folderId))
                .andExpect(jsonPath("$.folders[0].shared").value(true))
                .andExpect(jsonPath("$.goals[0].id").value(goalId))
                .andExpect(jsonPath("$.tasks[0].id").value(taskId));

        String folderLinkResponse = mockMvc.perform(post("/api/folders/" + folderId + "/share-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("folder"))
                .andExpect(jsonPath("$.targetId").value(folderId))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String folderLinkId = read(folderLinkResponse, "/id");
        String folderLinkToken = read(folderLinkResponse, "/token");

        mockMvc.perform(get("/api/folders/" + folderId + "/share-links")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(folderLinkId))
                .andExpect(jsonPath("$.items[0].targetType").value("folder"));

        mockMvc.perform(post("/api/shares/links/" + folderLinkToken + "/accept")
                        .header("Authorization", "Bearer " + outsider.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.targetType").value("folder"))
                .andExpect(jsonPath("$.status").value("active"));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + outsider.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folders[0].id").value(folderId))
                .andExpect(jsonPath("$.goals[0].id").value(goalId))
                .andExpect(jsonPath("$.tasks[0].id").value(taskId));

        String goalLinkResponse = mockMvc.perform(post("/api/goals/" + goalId + "/share-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "expiresAt": "2030-01-01T00:00:00Z"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("goal"))
                .andExpect(jsonPath("$.targetId").value(goalId))
                .andExpect(jsonPath("$.token").isNotEmpty())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String goalLinkId = read(goalLinkResponse, "/id");
        String goalLinkToken = read(goalLinkResponse, "/token");

        mockMvc.perform(get("/api/goals/" + goalId + "/share-links")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(goalLinkId))
                .andExpect(jsonPath("$.items[0].targetType").value("goal"));

        mockMvc.perform(get("/api/shares/links/" + goalLinkToken)
                        .header("Authorization", "Bearer " + linkCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(goalLinkId))
                .andExpect(jsonPath("$.targetType").value("goal"))
                .andExpect(jsonPath("$.targetId").value(goalId));

        mockMvc.perform(post("/api/shares/links/" + goalLinkToken + "/accept")
                        .header("Authorization", "Bearer " + linkCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.targetType").value("goal"))
                .andExpect(jsonPath("$.status").value("active"));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + linkCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folders.length()").value(0))
                .andExpect(jsonPath("$.goals[0].id").value(goalId))
                .andExpect(jsonPath("$.tasks[0].id").value(taskId));

        String taskLinkResponse = mockMvc.perform(post("/api/tasks/" + taskId + "/share-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("task"))
                .andExpect(jsonPath("$.targetId").value(taskId))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String taskLinkId = read(taskLinkResponse, "/id");
        String taskLinkToken = read(taskLinkResponse, "/token");

        mockMvc.perform(post("/api/shares/links/" + taskLinkId + "/revoke")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("revoked"));

        mockMvc.perform(get("/api/shares/links/" + taskLinkToken)
                        .header("Authorization", "Bearer " + outsider.accessToken()))
                .andExpect(status().isNotFound());
    }

    @Test
    void sharingRequiresExistingInviteeAccountBinding() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");

        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId, "Work", "Main work area"), "/id");

        mockMvc.perform(post("/api/goals/" + goalId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "future-user@example.com"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_error"));

        Session invitee = registerAndLogin("invitee@example.com", "Invitee");
        Session other = registerAndLogin("other@example.com", "Other");

        String invitationResponse = mockMvc.perform(post("/api/goals/" + goalId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "invitee@example.com"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetEmail").value("invitee@example.com"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String invitationId = read(invitationResponse, "/id");

        mockMvc.perform(get("/api/shares/invitations")
                        .header("Authorization", "Bearer " + invitee.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(invitationId));

        mockMvc.perform(get("/api/shares/invitations")
                        .header("Authorization", "Bearer " + other.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + other.accessToken()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("forbidden"));

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + invitee.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));
    }

    @Test
    void legacyPendingInvitationWithoutTargetUserIdCanStillBeAcceptedByEmailOwner() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session invitee = registerAndLogin("legacy-invitee@example.com", "Invitee");

        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId, "Legacy share", "Pre V9 invitation"), "/id");
        String invitationId = UUID.randomUUID().toString();

        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.createStatement()) {
            statement.executeUpdate("""
                    insert into share_invitations (
                        id,
                        inviter_user_id,
                        target_type,
                        target_id,
                        target_email,
                        status,
                        created_at,
                        updated_at,
                        expires_at
                    )
                    values (
                        '%s',
                        '%s',
                        'goal',
                        '%s',
                        'legacy-invitee@example.com',
                        'pending',
                        now(),
                        now(),
                        now() + interval '7 days'
                    )
                    """.formatted(invitationId, userId("owner@example.com"), goalId));
        }

        mockMvc.perform(get("/api/shares/invitations")
                        .header("Authorization", "Bearer " + invitee.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(invitationId));

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + invitee.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + invitee.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goals[0].id").value(goalId));
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

        return new Session(read(loginResponse, "/tokens/accessToken"));
    }

    private String createFolder(String accessToken) throws Exception {
        return read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work",
                                  "description": "Main work area"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");
    }

    private String createGoal(String accessToken, String folderId, String name, String description) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "%s"
                                }
                                """.formatted(name, description)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createTask(String accessToken, String goalId, String title, int priority) throws Exception {
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "description": "Task description",
                                  "type": "green",
                                  "priority": %s,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": []
                                }
                                """.formatted(title, priority)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String read(String json, String path) throws Exception {
        JsonNode root = objectMapper.readTree(json);
        JsonNode value = root.at(path);
        return value.isTextual() ? value.asText() : value.toString();
    }

    private String userId(String email) throws Exception {
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.prepareStatement("select id from users where lower(email) = lower(?)")) {
            statement.setString(1, email);
            try (var resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    throw new IllegalStateException("User was not found: " + email);
                }
                return resultSet.getString(1);
            }
        }
    }

    private static EmbeddedPostgres startPostgres() {
        try {
            return EmbeddedPostgres.start();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to start embedded PostgreSQL", exception);
        }
    }

    private record Session(String accessToken) {
    }
}
