package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
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
class PlanningCrudIntegrationTest {

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
            statement.executeUpdate("truncate table task_tag_links, task_tags, tasks, goals, folders, auth_sessions, user_settings, user_credentials, users cascade");
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void foldersGoalsTasksCrudFlowWorks() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String tagResponse = mockMvc.perform(post("/api/tags")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "career",
                                  "color": "#4f6b9a"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("career"))
                .andReturn().getResponse().getContentAsString();
        String tagId = read(tagResponse, "/id");

        String folderResponse = mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work",
                                  "description": "Main work area"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.displayOrder").value(1))
                .andReturn().getResponse().getContentAsString();
        String folderId = read(folderResponse, "/id");
        String folderVersion = read(folderResponse, "/version");

        mockMvc.perform(get("/api/folders")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].name").value("Work"));

        String goalResponse = mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Promotion",
                                  "description": "Grow into the next role"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.folderId").value(folderId))
                .andReturn().getResponse().getContentAsString();
        String goalId = read(goalResponse, "/id");
        String goalVersion = read(goalResponse, "/version");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Prepare promotion plan",
                                  "description": "Outline achievements and next steps",
                                  "type": "green",
                                  "priority": 8,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": ["%s"]
                                }
                                """.formatted(tagId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.tags[0].name").value("career"))
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");
        String taskVersion = read(taskResponse, "/version");

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].title").value("Prepare promotion plan"));

        mockMvc.perform(patch("/api/folders/" + folderId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work Projects",
                                  "description": "Priority work area",
                                  "displayOrder": 2,
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(folderVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Work Projects"));

        mockMvc.perform(patch("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Promotion 2026",
                                  "description": "Move into the next role this year",
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(goalVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Promotion 2026"));

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken)
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
                                  "tagIds": ["%s"],
                                  "version": %s
                                }
                                """.formatted(tagId, taskVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Prepare promotion plan draft"))
                .andExpect(jsonPath("$.status").value("in_progress"));

        mockMvc.perform(delete("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(true));

        mockMvc.perform(delete("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(true));

        mockMvc.perform(delete("/api/folders/" + folderId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/folders")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].archived").value(true));
    }

    @Test
    void taskPatchWithoutTagIdsPreservesExistingTags() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String tagResponse = mockMvc.perform(post("/api/tags")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "android-sync",
                                  "color": "#4f6b9a"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String tagId = read(tagResponse, "/id");

        String folderId = read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Mobile",
                                  "description": "Created during sync"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String goalId = read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Offline goal",
                                  "description": "Android-created goal"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Tagged mobile task",
                                  "description": "Has a tag created by another client",
                                  "type": "green",
                                  "priority": 6,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": ["%s"]
                                }
                                """.formatted(tagId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.tags[0].id").value(tagId))
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");
        String taskVersion = read(taskResponse, "/version");

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Tagged mobile task updated on web",
                                  "description": "Web client did not send tagIds",
                                  "type": "green",
                                  "priority": 7,
                                  "status": "in_progress",
                                  "plannedTime": "2026-05-01T10:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(taskVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tags[0].id").value(tagId));
    }

    private String registerAndLogin() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "planner@example.com",
                                  "password": "strong-password",
                                  "displayName": "Planner",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """))
                .andExpect(status().isCreated());

        return mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "planner@example.com",
                                  "password": "strong-password"
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
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
