package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Prepare promotion plan draft"))
                .andExpect(jsonPath("$.shared").value(true));

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
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goals[0].id").value(goalId))
                .andExpect(jsonPath("$.goals[0].shared").value(true))
                .andExpect(jsonPath("$.tasks.length()").value(2))
                .andExpect(jsonPath("$.tasks[0].shared").value(true))
                .andExpect(jsonPath("$.tasks[1].shared").value(true));
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
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shared").value(true));

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
