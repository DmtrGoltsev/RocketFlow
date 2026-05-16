package com.rocketflow;

import static org.hamcrest.Matchers.notNullValue;
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
class IdeasFolderNotesIntegrationTest {

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
                        folder_note_items,
                        folder_notes,
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
    void ownerCanManageIdeasAndFolderNotes() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String folderId = createFolder(owner.accessToken());

        String ideaResponse = mockMvc.perform(post("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Voice capture inbox",
                                  "body": "Collect rough thoughts before planning"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.folderId").value(folderId))
                .andExpect(jsonPath("$.status").value("active"))
                .andExpect(jsonPath("$.creatorEmail").value("owner@example.com"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(ideaId))
                .andExpect(jsonPath("$.items[0].shared").value(false));

        mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "First refinement",
                                  "metadata": {
                                    "source": "owner-test"
                                  }
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.ideaId").value(ideaId))
                .andExpect(jsonPath("$.authorEmail").value("owner@example.com"))
                .andExpect(jsonPath("$.createdAt", notNullValue()));

        mockMvc.perform(get("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].metadata.source").value("owner-test"));

        String folderNoteResponse = mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "kind": "list",
                                  "title": "Launch checklist",
                                  "body": "MVP list"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.kind").value("list"))
                .andExpect(jsonPath("$.items.length()").value(0))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String noteId = read(folderNoteResponse, "/id");

        String itemResponse = mockMvc.perform(post("/api/folder-notes/" + noteId + "/items")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "Document API",
                                  "checked": false
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.text").value("Document API"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String itemId = read(itemResponse, "/id");
        String itemVersion = read(itemResponse, "/version");

        mockMvc.perform(patch("/api/folder-note-items/" + itemId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "Document backend API",
                                  "checked": true,
                                  "displayOrder": 1,
                                  "version": %s
                                }
                                """.formatted(itemVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.checked").value(true));

        mockMvc.perform(patch("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Voice capture inbox refined",
                                  "body": "Ready for grooming",
                                  "status": "active",
                                  "displayOrder": 2,
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(ideaVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Voice capture inbox refined"));

        mockMvc.perform(delete("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived").value(true));
    }

    @Test
    void folderCollaboratorCanCreateAndReadIdeasNotesAndListItems() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");
        String folderId = createFolder(owner.accessToken());
        String ideaId = read(createIdea(owner.accessToken(), folderId, "Shared idea"), "/id");
        shareAndAccept(owner.accessToken(), collaborator.accessToken(), "/api/folders/" + folderId + "/share", "collaborator@example.com");

        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(ideaId))
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(post("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Collaborator idea",
                                  "body": "Created through folder share"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.creatorEmail").value("collaborator@example.com"));

        mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "comment",
                                  "body": "Collaborator refinement",
                                  "metadata": {}
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.authorEmail").value("collaborator@example.com"))
                .andExpect(jsonPath("$.createdAt", notNullValue()));

        String listNoteId = read(mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "kind": "list",
                                  "title": "Collaborative checklist",
                                  "body": "Shared work"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.authorEmail").value("collaborator@example.com"))
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        String itemResponse = mockMvc.perform(post("/api/folder-notes/" + listNoteId + "/items")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "Check shared flow",
                                  "checked": false
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String itemId = read(itemResponse, "/id");
        String itemVersion = read(itemResponse, "/version");

        mockMvc.perform(patch("/api/folder-note-items/" + itemId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "Check shared flow",
                                  "checked": true,
                                  "displayOrder": 1,
                                  "version": %s
                                }
                                """.formatted(itemVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.checked").value(true));

        mockMvc.perform(get("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].items[0].checked").value(true));

        String collaboratorIdea = mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String collaboratorIdeaVersion = read(collaboratorIdea, "/items/0/version");

        mockMvc.perform(patch("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Shared idea updated",
                                  "body": "Should not be allowed",
                                  "status": "active",
                                  "displayOrder": 1,
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(collaboratorIdeaVersion)))
                .andExpect(status().isNotFound());
    }

    @Test
    void directGoalShareDoesNotGrantFolderContentAccess() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session goalCollaborator = registerAndLogin("goal-collaborator@example.com", "Goal Collaborator");
        Session outsider = registerAndLogin("outsider@example.com", "Outsider");
        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId), "/id");
        String ideaId = read(createIdea(owner.accessToken(), folderId, "Private folder idea"), "/id");
        String noteId = read(createFolderNote(owner.accessToken(), folderId), "/id");

        shareAndAccept(owner.accessToken(), goalCollaborator.accessToken(), "/api/goals/" + goalId + "/share", "goal-collaborator@example.com");

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shared").value(true));

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "comment",
                                  "body": "No folder-level access"
                                }
                                """))
                .andExpect(status().isNotFound());
        mockMvc.perform(post("/api/folder-notes/" + noteId + "/items")
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "Nope",
                                  "checked": false
                                }
                                """))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + outsider.accessToken()))
                .andExpect(status().isNotFound());
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

    private String createGoal(String accessToken, String folderId) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Delivery",
                                  "description": "Shared goal"
                                }
                                """))
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

    private String createFolderNote(String accessToken, String folderId) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "kind": "list",
                                  "title": "Private list",
                                  "body": "Folder-only list"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private void shareAndAccept(String ownerAccessToken, String collaboratorAccessToken, String shareEndpoint, String email) throws Exception {
        String invitationId = read(mockMvc.perform(post(shareEndpoint)
                        .header("Authorization", "Bearer " + ownerAccessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s"
                                }
                                """.formatted(email)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + collaboratorAccessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));
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
