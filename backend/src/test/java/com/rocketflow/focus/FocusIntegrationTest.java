package com.rocketflow.focus;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.Connection;
import java.sql.PreparedStatement;
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

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class FocusIntegrationTest {
    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void configureDatasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> POSTGRES.getJdbcUrl("postgres", "postgres"));
        registry.add("spring.datasource.username", () -> "postgres");
        registry.add("spring.datasource.password", () -> "postgres");
    }

    @BeforeEach
    void cleanDatabase() throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.createStatement()) {
            statement.executeUpdate("truncate table users cascade");
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void duplicateAddIsIdempotentAndProgressUsesEffort() throws Exception {
        Session session = register("focus-owner@example.com", "Europe/Moscow");
        Hierarchy hierarchy = hierarchy(session.token(), "Work", "Launch");
        String todoId = task(session.token(), hierarchy.goalId(), "Small task", 0, "todo");
        String doneId = task(session.token(), hierarchy.goalId(), "Large task", 3, "done");

        String initial = mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        long initialVersion = objectMapper.readTree(initial).path("version").asLong();

        String request = """
                {"periodVersion":%d,"idempotencyKey":"add-small"}
                """.formatted(initialVersion);
        mockMvc.perform(put("/api/focus/current/items/" + todoId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isOk());
        mockMvc.perform(put("/api/focus/current/items/" + todoId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1));
        mockMvc.perform(put("/api/focus/current/items/" + doneId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"periodVersion\":" + initialVersion + "}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("focus_version_conflict"));
        mockMvc.perform(put("/api/focus/current/items/" + doneId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(2))
                .andExpect(jsonPath("$.items[0].effectiveWeight").value(1))
                .andExpect(jsonPath("$.progress.completedWeight").value(3))
                .andExpect(jsonPath("$.progress.totalWeight").value(4))
                .andExpect(jsonPath("$.progress.percent").value(75))
                .andExpect(jsonPath("$.progress.completedCount").value(1));
    }

    @Test
    void candidatesFilterAccessBeforeBoundedPaginationAndPreserveSearchAndHierarchy() throws Exception {
        Session viewer = register("candidate-viewer@example.com", "Europe/Moscow");
        Session owner = register("candidate-owner@example.com", "Europe/Moscow");
        Session foreign = register("candidate-foreign@example.com", "Europe/Moscow");

        Hierarchy ownHierarchy = hierarchy(viewer.token(), "Own area", "Own goal");
        String ownTaskId = task(viewer.token(), ownHierarchy.goalId(), "Own old needle", 1, "todo");
        setTaskCreatedAt(UUID.fromString(ownTaskId), Instant.parse("2020-01-02T00:00:00Z"));

        Hierarchy sharedRoot = hierarchy(owner.token(), "Shared root", "Root goal");
        UUID sharedChildId = childFolder(owner.token(), sharedRoot.folderId(), "Shared child");
        String sharedGoalId = goal(owner.token(), sharedChildId, "Shared child goal");
        String sharedTaskId = task(owner.token(), sharedGoalId, "Shared old needle", 2, "todo");
        setTaskCreatedAt(UUID.fromString(sharedTaskId), Instant.parse("2020-01-01T00:00:00Z"));
        UUID shareId = createFolderShare(sharedRoot.folderId(), owner.userId(), viewer.userId());

        Hierarchy foreignHierarchy = hierarchy(foreign.token(), "Foreign area", "Foreign goal");
        insertTasks(foreign.userId(), UUID.fromString(foreignHierarchy.goalId()), 5_001, "Foreign flood");

        String firstPage = mockMvc.perform(get("/api/focus/candidates")
                        .header("Authorization", bearer(viewer.token()))
                        .param("limit", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].taskId").value(ownTaskId))
                .andExpect(jsonPath("$.nextCursor").isString())
                .andReturn().getResponse().getContentAsString();

        String cursor = read(firstPage, "/nextCursor");
        mockMvc.perform(get("/api/focus/candidates")
                        .header("Authorization", bearer(viewer.token()))
                        .param("limit", "1")
                        .param("cursor", cursor))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].taskId").value(sharedTaskId))
                .andExpect(jsonPath("$.items[0].shared").value(true))
                .andExpect(jsonPath("$.nextCursor").doesNotExist());

        mockMvc.perform(get("/api/focus/candidates")
                        .header("Authorization", bearer(viewer.token()))
                        .param("q", "shared old needle")
                        .param("folderId", sharedChildId.toString())
                        .param("goalId", sharedGoalId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].taskId").value(sharedTaskId));

        mockMvc.perform(get("/api/focus/candidates")
                        .header("Authorization", bearer(viewer.token()))
                        .param("q", "Foreign flood"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0))
                .andExpect(jsonPath("$.nextCursor").doesNotExist());

        revokeFolderShare(shareId);
        mockMvc.perform(get("/api/focus/candidates")
                        .header("Authorization", bearer(viewer.token()))
                        .param("q", "shared old needle"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        mockMvc.perform(put("/api/focus/current/items/" + sharedTaskId)
                        .header("Authorization", bearer(viewer.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void deletedTaskIsRemovedFromActiveFocus() throws Exception {
        Session session = register("deleted@example.com", "Europe/Moscow");
        Hierarchy hierarchy = hierarchy(session.token(), "Area", "Goal");
        String taskId = task(session.token(), hierarchy.goalId(), "Delete me", 1, "todo");
        mockMvc.perform(put("/api/focus/current/items/" + taskId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1));

        mockMvc.perform(delete("/api/tasks/" + taskId)
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        org.junit.jupiter.api.Assertions.assertEquals(0, countFocusItems(UUID.fromString(taskId)));
        org.junit.jupiter.api.Assertions.assertTrue(taskHasDeletedAt(UUID.fromString(taskId)));
    }

    @Test
    void archiveKeepsSnapshotHistoryOnlyWithoutDeletingTask() throws Exception {
        Session session = register("archived@example.com", "Europe/Moscow");
        Hierarchy hierarchy = hierarchy(session.token(), "Area", "Goal");
        String taskId = task(session.token(), hierarchy.goalId(), "Archive me", 2, "todo");
        mockMvc.perform(put("/api/focus/current/items/" + taskId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk());

        String task = mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title":"Archive me","description":"","type":"green","priority":5,
                                  "effort":2,"status":"todo","archived":true,"tagIds":[],"version":%s
                                }
                                """.formatted(read(task, "/version"))))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        org.junit.jupiter.api.Assertions.assertEquals(1, countFocusItems(UUID.fromString(taskId)));
        org.junit.jupiter.api.Assertions.assertTrue(focusItemIsHistoryOnly(UUID.fromString(taskId)));
        org.junit.jupiter.api.Assertions.assertFalse(taskHasDeletedAt(UUID.fromString(taskId)));
    }

    @Test
    void goalAndFolderDeleteRemoveDescendantTasksFromActiveFocus() throws Exception {
        Session session = register("hierarchy-delete@example.com", "Europe/Moscow");
        Hierarchy goalHierarchy = hierarchy(session.token(), "Goal area", "Deleted goal");
        String goalTaskId = task(session.token(), goalHierarchy.goalId(), "Goal child", 1, "todo");
        Hierarchy folderHierarchy = hierarchy(session.token(), "Deleted folder", "Folder goal");
        String folderTaskId = task(session.token(), folderHierarchy.goalId(), "Folder child", 1, "todo");
        for (String taskId : List.of(goalTaskId, folderTaskId)) {
            mockMvc.perform(put("/api/focus/current/items/" + taskId)
                            .header("Authorization", bearer(session.token()))
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isOk());
        }

        mockMvc.perform(delete("/api/goals/" + goalHierarchy.goalId())
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/folders/" + folderHierarchy.folderId())
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));
        for (String taskId : List.of(goalTaskId, folderTaskId)) {
            UUID id = UUID.fromString(taskId);
            org.junit.jupiter.api.Assertions.assertEquals(0, countFocusItems(id));
            org.junit.jupiter.api.Assertions.assertTrue(taskHasDeletedAt(id));
        }
    }

    @Test
    void completedTaskStaysInActiveFocusUntilRollover() throws Exception {
        Session session = register("completed-stays@example.com", "Europe/Moscow");
        Hierarchy hierarchy = hierarchy(session.token(), "Area", "Goal");
        String taskId = task(session.token(), hierarchy.goalId(), "Already done", 4, "done");

        mockMvc.perform(put("/api/focus/current/items/" + taskId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].taskId").value(taskId))
                .andExpect(jsonPath("$.progress.completedWeight").value(4))
                .andExpect(jsonPath("$.progress.percent").value(100));
        mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].taskId").value(taskId));
    }

    @Test
    void rolloverOffersOnlyIncompleteTasksAndResolveIsIdempotent() throws Exception {
        Session session = register("rollover@example.com", "Pacific/Kiritimati");
        Hierarchy hierarchy = hierarchy(session.token(), "Area", "Goal");
        String taskId = task(session.token(), hierarchy.goalId(), "Carry me", 2, "todo");
        mockMvc.perform(put("/api/focus/current/items/" + taskId)
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk());

        shiftActivePeriodToPreviousWeek(session.userId());
        String current = mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rolloverOffer.items[0].taskId").value(taskId))
                .andReturn().getResponse().getContentAsString();
        String sourceId = read(current, "/rolloverOffer/sourcePeriodId");
        String body = """
                {"taskIds":["%s"],"idempotencyKey":"carry-once"}
                """.formatted(taskId);

        mockMvc.perform(post("/api/focus/rollovers/" + sourceId + "/resolve")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.rolloverOffer").doesNotExist());
        mockMvc.perform(post("/api/focus/rollovers/" + sourceId + "/resolve")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1));
    }

    @Test
    void revokedSharedAccessHidesTaskFromCurrentFocus() throws Exception {
        Session owner = register("shared-owner@example.com", "Europe/Moscow");
        Session viewer = register("shared-viewer@example.com", "Europe/Moscow");
        Hierarchy hierarchy = hierarchy(owner.token(), "Shared", "Goal");
        String taskId = task(owner.token(), hierarchy.goalId(), "Shared task", 2, "todo");
        UUID shareId = createFolderShare(hierarchy.folderId(), owner.userId(), viewer.userId());

        mockMvc.perform(put("/api/focus/current/items/" + taskId)
                        .header("Authorization", bearer(viewer.token()))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].shared").value(true))
                .andExpect(jsonPath("$.items[0].canWrite").value(false));

        revokeFolderShare(shareId);
        mockMvc.perform(get("/api/focus/current")
                        .header("Authorization", bearer(viewer.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0))
                .andExpect(jsonPath("$.progress.totalCount").value(0));
    }

    @Test
    void validatesNotificationIntervalAndQuietHoursPair() throws Exception {
        Session session = register("settings@example.com", "Europe/Moscow");
        String current = mockMvc.perform(get("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        long currentVersion = Long.parseLong(read(current, "/version"));
        String initial = mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"intervalMinutes":60,"quietHoursStart":"22:30","quietHoursEnd":"07:00","version":%d}
                                """.formatted(currentVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.intervalMinutes").value(60))
                .andExpect(jsonPath("$.quietHoursStart").value("22:30"))
                .andReturn().getResponse().getContentAsString();
        long version = Long.parseLong(read(initial, "/version"));

        mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"intervalMinutes":120,"quietHoursStart":"22:30","quietHoursEnd":"07:00","version":%d}
                                """.formatted(version)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.intervalMinutes").value(120))
                .andExpect(jsonPath("$.version").value(version + 1));

        mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"intervalMinutes":240,"quietHoursStart":"22:30","quietHoursEnd":"07:00","version":%d}
                                """.formatted(version)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("focus_settings_version_conflict"));

        mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"intervalMinutes\":30}"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"intervalMinutes":45,"version":%d}
                                """.formatted(version + 1)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("focus_interval_invalid"));

        mockMvc.perform(patch("/api/focus/notification-settings")
                        .header("Authorization", bearer(session.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"intervalMinutes":30,"quietHoursStart":"22:00","version":%d}
                                """.formatted(version + 1)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("focus_quiet_hours_invalid"));
    }

    private Session register(String email, String timezone) throws Exception {
        String response = mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email":"%s","password":"strong-password","displayName":"Focus User",
                                  "timezone":"%s","language":"ru"
                                }
                                """.formatted(email, timezone)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return new Session(read(response, "/tokens/accessToken"), UUID.fromString(read(response, "/user/id")));
    }

    private Hierarchy hierarchy(String token, String folderName, String goalName) throws Exception {
        String folder = mockMvc.perform(post("/api/folders")
                        .header("Authorization", bearer(token)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + folderName + "\",\"description\":\"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String folderId = read(folder, "/id");
        String goal = mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", bearer(token)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + goalName + "\",\"description\":\"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return new Hierarchy(UUID.fromString(folderId), read(goal, "/id"));
    }

    private UUID childFolder(String token, UUID parentFolderId, String name) throws Exception {
        String response = mockMvc.perform(post("/api/folders/" + parentFolderId + "/folders")
                        .header("Authorization", bearer(token)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"description\":\"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return UUID.fromString(read(response, "/id"));
    }

    private String goal(String token, UUID folderId, String name) throws Exception {
        String response = mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", bearer(token)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"description\":\"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return read(response, "/id");
    }

    private String task(String token, String goalId, String title, int effort, String taskStatus) throws Exception {
        String response = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", bearer(token)).contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title":"%s","description":"","type":"green","priority":5,
                                  "effort":%d,"status":"%s","tagIds":[]
                                }
                                """.formatted(title, effort, taskStatus)))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return read(response, "/id");
    }

    private void setTaskCreatedAt(UUID taskId, Instant createdAt) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement("update tasks set created_at=? where id=?")) {
            statement.setTimestamp(1, java.sql.Timestamp.from(createdAt));
            statement.setObject(2, taskId);
            statement.executeUpdate();
        }
    }

    private void insertTasks(UUID ownerId, UUID goalId, int count, String titlePrefix) throws Exception {
        Instant now = Instant.now();
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement("""
                     insert into tasks(
                         id,goal_id,owner_user_id,creator_user_id,title,description,type,priority,effort,status,
                         archived,created_at,updated_at,version
                     ) values (?,?,?,?,?,'','green',5,1,'todo',false,?,?,0)
                     """)) {
            for (int index = 0; index < count; index++) {
                statement.setObject(1, UUID.randomUUID());
                statement.setObject(2, goalId);
                statement.setObject(3, ownerId);
                statement.setObject(4, ownerId);
                statement.setString(5, titlePrefix + " " + index);
                statement.setTimestamp(6, java.sql.Timestamp.from(now.plusMillis(index)));
                statement.setTimestamp(7, java.sql.Timestamp.from(now.plusMillis(index)));
                statement.addBatch();
            }
            statement.executeBatch();
        }
    }

    private void shiftActivePeriodToPreviousWeek(UUID userId) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement("""
                     update weekly_focus_periods
                        set week_start = week_start - 7,
                            week_end_exclusive = week_end_exclusive - 7,
                            starts_at = starts_at - interval '7 days',
                            ends_at = ends_at - interval '7 days'
                      where user_id = ? and status = 'active'
                     """)) {
            statement.setObject(1, userId);
            statement.executeUpdate();
        }
    }

    private boolean taskHasDeletedAt(UUID taskId) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement("select deleted_at is not null from tasks where id=?")) {
            statement.setObject(1, taskId);
            try (var result = statement.executeQuery()) {
                result.next();
                return result.getBoolean(1);
            }
        }
    }

    private boolean focusItemIsHistoryOnly(UUID taskId) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement(
                     "select history_only from weekly_focus_items where task_id=?")) {
            statement.setObject(1, taskId);
            try (var result = statement.executeQuery()) {
                result.next();
                return result.getBoolean(1);
            }
        }
    }

    private int countFocusItems(UUID taskId) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement(
                     "select count(*) from weekly_focus_items where task_id=?")) {
            statement.setObject(1, taskId);
            try (var result = statement.executeQuery()) {
                result.next();
                return result.getInt(1);
            }
        }
    }

    private UUID createFolderShare(UUID folderId, UUID ownerId, UUID viewerId) throws Exception {
        UUID id = UUID.randomUUID();
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement("""
                     insert into folder_shares(
                         id,folder_id,owner_user_id,collaborator_user_id,status,created_at,updated_at,full_access
                     ) values (?,?,?,?, 'active',?,?,false)
                     """)) {
            statement.setObject(1, id);
            statement.setObject(2, folderId);
            statement.setObject(3, ownerId);
            statement.setObject(4, viewerId);
            statement.setTimestamp(5, java.sql.Timestamp.from(Instant.now()));
            statement.setTimestamp(6, java.sql.Timestamp.from(Instant.now()));
            statement.executeUpdate();
        }
        return id;
    }

    private void revokeFolderShare(UUID shareId) throws Exception {
        try (Connection connection = POSTGRES.getPostgresDatabase().getConnection();
             PreparedStatement statement = connection.prepareStatement(
                     "update folder_shares set status='revoked', revoked_at=?, updated_at=? where id=?")) {
            statement.setTimestamp(1, java.sql.Timestamp.from(Instant.now()));
            statement.setTimestamp(2, java.sql.Timestamp.from(Instant.now()));
            statement.setObject(3, shareId);
            statement.executeUpdate();
        }
    }

    private String read(String json, String path) throws Exception {
        JsonNode value = objectMapper.readTree(json).at(path);
        return value.isTextual() ? value.asText() : value.toString();
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }

    private static EmbeddedPostgres startPostgres() {
        try {
            return EmbeddedPostgres.start();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    private record Session(String token, UUID userId) {
    }

    private record Hierarchy(UUID folderId, String goalId) {
    }
}
