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
class HierarchyLinksIntegrationTest {

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
                        entity_links,
                        notes,
                        idea_notes,
                        ideas,
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
    void nestedFoldersCloneMoveAndFullAccessSharingWork() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");
        Session readOnly = registerAndLogin("readonly@example.com", "Read Only");

        String rootFolderId = createFolder(owner.accessToken(), "Root");
        String childResponse = createChildFolder(owner.accessToken(), rootFolderId, "Child");
        String childFolderId = read(childResponse, "/id");
        String childFolderVersion = read(childResponse, "/version");
        String grandchildFolderId = read(createChildFolder(owner.accessToken(), childFolderId, "Grandchild"), "/id");

        mockMvc.perform(post("/api/folders/" + rootFolderId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "version": 0
                                }
                                """.formatted(grandchildFolderId)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_error"));

        mockMvc.perform(post("/api/folders/" + childFolderId + "/clone")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "name": "Child copy"
                                }
                                """.formatted(rootFolderId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.parentFolderId").value(rootFolderId))
                .andExpect(jsonPath("$.name").value("Child copy"));

        shareAndAccept(owner.accessToken(), collaborator.accessToken(), "/api/folders/" + rootFolderId + "/share", "collaborator@example.com", true);
        shareAndAccept(owner.accessToken(), readOnly.accessToken(), "/api/folders/" + rootFolderId + "/share", "readonly@example.com", false);

        mockMvc.perform(post("/api/folders/" + childFolderId + "/folders")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Collaborator child",
                                  "description": "Created through full access"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.fullAccess").value(true));

        mockMvc.perform(post("/api/folders/" + rootFolderId + "/goals")
                        .header("Authorization", "Bearer " + readOnly.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Read-only goal",
                                  "description": "Must fail"
                                }
                                """))
                .andExpect(status().isNotFound());

        String sharedGoalId = read(mockMvc.perform(post("/api/folders/" + childFolderId + "/goals")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Shared goal",
                                  "description": "Created through full access",
                                  "status": "in_progress"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.fullAccess").value(true))
                .andExpect(jsonPath("$.status").value("in_progress"))
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        mockMvc.perform(post("/api/goals/" + sharedGoalId + "/tasks")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Shared task",
                                  "description": "Created under shared goal",
                                  "type": "green",
                                  "priority": 5,
                                  "status": "todo",
                                  "tagIds": []
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(post("/api/folders/" + childFolderId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Shared note",
                                  "body": "Created by collaborator"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.fullAccess").value(true));

        mockMvc.perform(post("/api/folders/" + childFolderId + "/ideas")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Shared idea",
                                  "body": "Created by collaborator"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(post("/api/folders/" + childFolderId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "version": %s
                                }
                                """.formatted(rootFolderId, childFolderVersion)))
                .andExpect(status().isOk());
    }

    @Test
    void linksAndTaskDependenciesAreEnforced() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String folderId = createFolder(owner.accessToken(), "Root");
        String goalId = read(createGoal(owner.accessToken(), folderId, "Goal A"), "/id");
        String otherGoalId = read(createGoal(owner.accessToken(), folderId, "Goal B"), "/id");
        String dependentResponse = createTask(owner.accessToken(), goalId, "Dependent task", "todo");
        String dependentTaskId = read(dependentResponse, "/id");
        String dependentVersion = read(dependentResponse, "/version");
        String blockerResponse = createTask(owner.accessToken(), otherGoalId, "Blocking task", "todo");
        String blockerTaskId = read(blockerResponse, "/id");
        String blockerVersion = read(blockerResponse, "/version");
        String noteId = read(createNote(owner.accessToken(), folderId, "Linked note"), "/id");
        String ideaId = read(createIdea(owner.accessToken(), folderId, "Linked idea"), "/id");

        mockMvc.perform(post("/api/entity-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "sourceType": "task",
                                  "sourceId": "%s",
                                  "targetType": "note",
                                  "targetId": "%s",
                                  "relationType": "related"
                                }
                                """.formatted(dependentTaskId, noteId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.target.type").value("note"));

        mockMvc.perform(post("/api/entity-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "sourceType": "idea",
                                  "sourceId": "%s",
                                  "targetType": "task",
                                  "targetId": "%s",
                                  "relationType": "related"
                                }
                                """.formatted(ideaId, dependentTaskId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.source.type").value("idea"));

        mockMvc.perform(get("/api/entity-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .param("entityType", "task")
                        .param("entityId", dependentTaskId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(2));

        mockMvc.perform(post("/api/entity-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "sourceType": "task",
                                  "sourceId": "%s",
                                  "targetType": "task",
                                  "targetId": "%s",
                                  "relationType": "dependency"
                                }
                                """.formatted(dependentTaskId, blockerTaskId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.relationType").value("dependency"));

        mockMvc.perform(post("/api/entity-links")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "sourceType": "goal",
                                  "sourceId": "%s",
                                  "targetType": "task",
                                  "targetId": "%s",
                                  "relationType": "dependency"
                                }
                                """.formatted(goalId, blockerTaskId)))
                .andExpect(status().isBadRequest());

        mockMvc.perform(patch("/api/tasks/" + dependentTaskId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPatchJson("Dependent task", "done", dependentVersion)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("dependency_blocked"));

        mockMvc.perform(patch("/api/tasks/" + blockerTaskId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPatchJson("Blocking task", "done", blockerVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("done"));

        String dependentAfterBlocked = mockMvc.perform(get("/api/tasks/" + dependentTaskId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String dependentAfterVersion = read(dependentAfterBlocked, "/version");

        mockMvc.perform(patch("/api/tasks/" + dependentTaskId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPatchJson("Dependent task", "done", dependentAfterVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("done"));
    }

    @Test
    void moveAndCloneEndpointsUseTheAllowedMatrix() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String sourceFolderId = createFolder(owner.accessToken(), "Source");
        String targetFolderId = createFolder(owner.accessToken(), "Target");
        String sourceGoalResponse = createGoal(owner.accessToken(), sourceFolderId, "Source goal");
        String sourceGoalId = read(sourceGoalResponse, "/id");
        String sourceGoalVersion = read(sourceGoalResponse, "/version");
        String targetGoalId = read(createGoal(owner.accessToken(), targetFolderId, "Target goal"), "/id");
        String taskResponse = createTask(owner.accessToken(), sourceGoalId, "Move me", "todo");
        String taskId = read(taskResponse, "/id");
        String taskVersion = read(taskResponse, "/version");
        String ideaResponse = createIdea(owner.accessToken(), sourceFolderId, "Move idea");
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");
        String noteResponse = createNote(owner.accessToken(), sourceFolderId, "Move note");
        String noteId = read(noteResponse, "/id");
        String noteVersion = read(noteResponse, "/version");

        mockMvc.perform(post("/api/goals/" + sourceGoalId + "/clone")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "name": "Goal clone"
                                }
                                """.formatted(targetFolderId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));

        mockMvc.perform(post("/api/goals/" + sourceGoalId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "version": %s
                                }
                                """.formatted(targetFolderId, sourceGoalVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));

        mockMvc.perform(post("/api/tasks/" + taskId + "/clone")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetGoalId": "%s",
                                  "title": "Task clone"
                                }
                                """.formatted(targetGoalId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.goalId").value(targetGoalId));

        mockMvc.perform(post("/api/tasks/" + taskId + "/move-to-goal")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetGoalId": "%s",
                                  "version": %s
                                }
                                """.formatted(targetGoalId, taskVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goalId").value(targetGoalId));

        mockMvc.perform(post("/api/ideas/" + ideaId + "/clone")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "title": "Idea clone"
                                }
                                """.formatted(targetFolderId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));

        mockMvc.perform(post("/api/ideas/" + ideaId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "version": %s
                                }
                                """.formatted(targetFolderId, ideaVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));

        mockMvc.perform(post("/api/notes/" + noteId + "/clone")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "title": "Note clone"
                                }
                                """.formatted(targetFolderId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));

        mockMvc.perform(post("/api/notes/" + noteId + "/move")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetFolderId": "%s",
                                  "version": %s
                                }
                                """.formatted(targetFolderId, noteVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folderId").value(targetFolderId));
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

    private String createFolder(String accessToken, String name) throws Exception {
        return read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Folder"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");
    }

    private String createChildFolder(String accessToken, String parentFolderId, String name) throws Exception {
        return mockMvc.perform(post("/api/folders/" + parentFolderId + "/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Child folder"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createGoal(String accessToken, String folderId, String name) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Goal"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createTask(String accessToken, String goalId, String title, String status) throws Exception {
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "description": "Task description",
                                  "type": "green",
                                  "priority": 5,
                                  "status": "%s",
                                  "tagIds": []
                                }
                                """.formatted(title, status)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createIdea(String accessToken, String folderId, String title) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "body": "Idea body"
                                }
                                """.formatted(title)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createNote(String accessToken, String folderId, String title) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "body": "Note body"
                                }
                                """.formatted(title)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String taskPatchJson(String title, String status, String version) {
        return """
                {
                  "title": "%s",
                  "description": "Task description",
                  "type": "green",
                  "priority": 5,
                  "status": "%s",
                  "plannedTime": null,
                  "dueTime": null,
                  "archived": false,
                  "tagIds": [],
                  "version": %s
                }
                """.formatted(title, status, version);
    }

    private void shareAndAccept(String ownerAccessToken, String collaboratorAccessToken, String shareEndpoint, String email, boolean fullAccess) throws Exception {
        String invitationId = read(mockMvc.perform(post(shareEndpoint)
                        .header("Authorization", "Bearer " + ownerAccessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s",
                                  "fullAccess": %s
                                }
                                """.formatted(email, fullAccess)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + collaboratorAccessToken))
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

    private record Session(String accessToken) {
    }
}
