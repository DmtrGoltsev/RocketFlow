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
                        entity_links,
                        notes,
                        idea_notes,
                        ideas,
                        idea_shares,
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
    void ownerCanManageIdeasHistoryAndPlainNotes() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String folderId = createFolder(owner.accessToken());

        String ideaResponse = createIdea(owner.accessToken(), folderId, "Voice capture inbox");
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(ideaId))
                .andExpect(jsonPath("$.items[0].allowAuthorNoteEdits").value(false));

        String ideaNoteResponse = mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
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
                .andExpect(jsonPath("$.createdAt", notNullValue()))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String ideaNoteId = read(ideaNoteResponse, "/id");
        String ideaNoteVersion = read(ideaNoteResponse, "/version");

        mockMvc.perform(patch("/api/idea-notes/" + ideaNoteId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "First refinement edited",
                                  "metadata": {
                                    "source": "owner-edit"
                                  },
                                  "version": %s
                                }
                                """.formatted(ideaNoteVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.body").value("First refinement edited"))
                .andExpect(jsonPath("$.metadata.source").value("owner-edit"));

        String noteResponse = mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Launch note",
                                  "body": "Plain shared note"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.title").value("Launch note"))
                .andExpect(jsonPath("$.authorEmail").value("owner@example.com"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String noteId = read(noteResponse, "/id");
        String noteVersion = read(noteResponse, "/version");

        mockMvc.perform(patch("/api/notes/" + noteId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Launch note edited",
                                  "body": "Updated body",
                                  "displayOrder": 1,
                                  "archived": false,
                                  "version": %s
                                }
                                """.formatted(noteVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("Launch note edited"));

        mockMvc.perform(get("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(noteId));

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
                                  "allowAuthorNoteEdits": true,
                                  "version": %s
                                }
                                """.formatted(ideaVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.allowAuthorNoteEdits").value(true));

        mockMvc.perform(delete("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNoContent());
    }

    @Test
    void onlyIdeaCreatorCanDeleteIdea() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session creator = registerAndLogin("creator@example.com", "Creator");
        String folderId = createFolder(owner.accessToken());
        shareAndAccept(owner.accessToken(), creator.accessToken(), "/api/folders/" + folderId + "/share", "creator@example.com", true);

        String ideaResponse = createIdea(creator.accessToken(), folderId, "Creator owned idea");
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");

        mockMvc.perform(delete("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(patch("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Owner cannot archive creator idea",
                                  "body": "Idea body",
                                  "status": "active",
                                  "displayOrder": 1,
                                  "archived": true,
                                  "allowAuthorNoteEdits": false,
                                  "version": %s
                                }
                                """.formatted(ideaVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(delete("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + creator.accessToken()))
                .andExpect(status().isNoContent());
    }

    @Test
    void ideaCreatorDeletesAnyHistoryNoteButEditingIsAuthorOnly() throws Exception {
        Session creator = registerAndLogin("creator@example.com", "Creator");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");
        String folderId = createFolder(creator.accessToken());
        String ideaId = read(createIdea(creator.accessToken(), folderId, "History permissions"), "/id");
        shareAndAccept(creator.accessToken(), collaborator.accessToken(), "/api/folders/" + folderId + "/share", "collaborator@example.com", true);

        String creatorNoteResponse = createIdeaNote(creator.accessToken(), ideaId, "Creator note");
        String creatorNoteId = read(creatorNoteResponse, "/id");
        String creatorNoteVersion = read(creatorNoteResponse, "/version");
        String collaboratorNoteResponse = createIdeaNote(collaborator.accessToken(), ideaId, "Collaborator note");
        String collaboratorNoteId = read(collaboratorNoteResponse, "/id");
        String collaboratorNoteVersion = read(collaboratorNoteResponse, "/version");

        mockMvc.perform(delete("/api/idea-notes/" + creatorNoteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(patch("/api/idea-notes/" + collaboratorNoteId)
                        .header("Authorization", "Bearer " + creator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "Creator cannot edit collaborator note",
                                  "metadata": {},
                                  "version": %s
                                }
                                """.formatted(collaboratorNoteVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        String editedCollaboratorNoteResponse = mockMvc.perform(patch("/api/idea-notes/" + collaboratorNoteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "Collaborator edits own note",
                                  "metadata": {
                                    "edited": true
                                  },
                                  "version": %s
                                }
                                """.formatted(collaboratorNoteVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.body").value("Collaborator edits own note"))
                .andExpect(jsonPath("$.metadata.edited").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String editedCollaboratorNoteVersion = read(editedCollaboratorNoteResponse, "/version");

        mockMvc.perform(patch("/api/idea-notes/" + creatorNoteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "Collaborator cannot edit creator note",
                                  "metadata": {},
                                  "version": %s
                                }
                                """.formatted(creatorNoteVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(delete("/api/idea-notes/" + creatorNoteId)
                        .header("Authorization", "Bearer " + creator.accessToken()))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/idea-notes/" + collaboratorNoteId)
                        .header("Authorization", "Bearer " + creator.accessToken()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + creator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));

        mockMvc.perform(patch("/api/idea-notes/" + collaboratorNoteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "Deleted note cannot be edited",
                                  "metadata": {},
                                  "version": %s
                                }
                                """.formatted(editedCollaboratorNoteVersion)))
                .andExpect(status().isNotFound());
    }

    @Test
    void ideaSettingControlsAuthorHistoryNoteEditing() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");
        String folderId = createFolder(owner.accessToken());
        String ideaResponse = createIdea(owner.accessToken(), folderId, "Editable note policy");
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");
        shareAndAccept(owner.accessToken(), collaborator.accessToken(), "/api/folders/" + folderId + "/share", "collaborator@example.com", true);

        String noteResponse = mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "comment",
                                  "body": "Draft from collaborator",
                                  "metadata": {}
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String noteId = read(noteResponse, "/id");
        String noteVersion = read(noteResponse, "/version");

        mockMvc.perform(patch("/api/idea-notes/" + noteId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "comment",
                                  "body": "Owner cannot edit collaborator note",
                                  "metadata": {},
                                  "version": %s
                                }
                                """.formatted(noteVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(patch("/api/idea-notes/" + noteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "comment",
                                  "body": "Author edit while full access",
                                  "metadata": {},
                                  "version": %s
                                }
                                """.formatted(noteVersion)))
                .andExpect(status().isOk());

        mockMvc.perform(patch("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Editable note policy",
                                  "body": "Idea body",
                                  "status": "active",
                                  "displayOrder": 1,
                                  "archived": false,
                                  "allowAuthorNoteEdits": true,
                                  "version": %s
                                }
                                """.formatted(ideaVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.allowAuthorNoteEdits").value(true));
    }

    @Test
    void directGoalShareDoesNotGrantFolderIdeasOrNotes() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session goalCollaborator = registerAndLogin("goal-collaborator@example.com", "Goal Collaborator");
        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId), "/id");
        String ideaId = read(createIdea(owner.accessToken(), folderId, "Private folder idea"), "/id");
        String noteId = read(createNote(owner.accessToken(), folderId), "/id");

        shareAndAccept(owner.accessToken(), goalCollaborator.accessToken(), "/api/goals/" + goalId + "/share", "goal-collaborator@example.com", false);

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/notes/" + noteId)
                        .header("Authorization", "Bearer " + goalCollaborator.accessToken()))
                .andExpect(status().isNotFound());
    }

    @Test
    void directIdeaShareGrantsOnlyThatIdeaAndHistory() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("idea-collaborator@example.com", "Idea Collaborator");
        String folderId = createFolder(owner.accessToken());
        String ideaResponse = createIdea(owner.accessToken(), folderId, "Scoped idea");
        String ideaId = read(ideaResponse, "/id");
        String ideaVersion = read(ideaResponse, "/version");
        String siblingIdeaId = read(createIdea(owner.accessToken(), folderId, "Private sibling idea"), "/id");
        String folderNoteId = read(createNote(owner.accessToken(), folderId), "/id");
        String ownerHistoryId = read(createIdeaNote(owner.accessToken(), ideaId, "Owner history"), "/id");

        mockMvc.perform(post("/api/ideas/" + ideaId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "idea-collaborator@example.com",
                                  "fullAccess": false
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.targetType").value("idea"))
                .andExpect(jsonPath("$.targetId").value(ideaId));

        String invitationId = read(mockMvc.perform(get("/api/shares/invitations")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].targetType").value("idea"))
                .andReturn()
                .getResponse()
                .getContentAsString(), "/items/0/id");

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("accepted"));

        mockMvc.perform(get("/api/shares/resources")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.folders[0].id").value(folderId))
                .andExpect(jsonPath("$.folders[0].canAccessFolderContent").value(false))
                .andExpect(jsonPath("$.ideas[0].id").value(ideaId))
                .andExpect(jsonPath("$.ideas[0].shared").value(true))
                .andExpect(jsonPath("$.ideas[0].fullAccess").value(false));

        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(ideaId))
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.fullAccess").value(false));

        mockMvc.perform(get("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(ownerHistoryId));

        mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "Collaborator history",
                                  "metadata": {}
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.authorEmail").value("idea-collaborator@example.com"));

        mockMvc.perform(patch("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + collaborator.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "No read-only edit",
                                  "body": "Idea body",
                                  "status": "active",
                                  "displayOrder": 1,
                                  "archived": false,
                                  "allowAuthorNoteEdits": false,
                                  "version": %s
                                }
                                """.formatted(ideaVersion)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/ideas/" + siblingIdeaId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/notes/" + folderNoteId)
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shared").value(true))
                .andExpect(jsonPath("$.fullAccess").value(true));
    }

    @Test
    void archivedIdeasNotesAndFolderChildrenAreHiddenFromDefaultReads() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String folderId = createFolder(owner.accessToken());

        String deletedIdeaId = read(createIdea(owner.accessToken(), folderId, "Archived idea"), "/id");
        String deletedNoteId = read(createNote(owner.accessToken(), folderId), "/id");

        mockMvc.perform(delete("/api/ideas/" + deletedIdeaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/notes/" + deletedNoteId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/folders/" + folderId + "/ideas")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        mockMvc.perform(get("/api/ideas/" + deletedIdeaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        mockMvc.perform(get("/api/notes/" + deletedNoteId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());

        String childFolderId = read(mockMvc.perform(post("/api/folders/" + folderId + "/folders")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Child folder",
                                  "description": "Hidden with parent"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");
        String goalId = read(createGoal(owner.accessToken(), folderId), "/id");
        String taskId = read(createTask(owner.accessToken(), goalId), "/id");
        String ideaId = read(createIdea(owner.accessToken(), folderId, "Folder child idea"), "/id");
        String noteId = read(createNote(owner.accessToken(), folderId), "/id");

        mockMvc.perform(delete("/api/folders/" + folderId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/folders")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        mockMvc.perform(get("/api/folders/" + childFolderId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/ideas/" + ideaId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/notes/" + noteId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());
    }

    @Test
    void legacyFolderNoteEndpointsAreRemoved() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");

        mockMvc.perform(post("/api/folder-notes/00000000-0000-0000-0000-000000000001/items")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "text": "No public folder-note item API",
                                  "checked": false
                                }
                                """))
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

    private String createIdeaNote(String accessToken, String ideaId, String body) throws Exception {
        return mockMvc.perform(post("/api/ideas/" + ideaId + "/notes")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventType": "note",
                                  "body": "%s",
                                  "metadata": {}
                                }
                                """.formatted(body)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createNote(String accessToken, String folderId) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/notes")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Private note",
                                  "body": "Folder-only note"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createTask(String accessToken, String goalId) throws Exception {
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Folder child task",
                                  "description": "Hidden with parent goal",
                                  "type": "green",
                                  "priority": 5,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": []
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
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
