package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
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
            statement.executeUpdate("truncate table task_checklist_items, task_tag_links, task_tags, tasks, goals, folders, auth_sessions, user_settings, user_credentials, users cascade");
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
                                  "effort": 5,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": ["%s"]
                                }
                                """.formatted(tagId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.effort").value(5))
                .andExpect(jsonPath("$.tags[0].name").value("career"))
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");
        String taskVersion = read(taskResponse, "/version");

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].title").value("Prepare promotion plan"))
                .andExpect(jsonPath("$.items[0].effort").value(5));

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
                                  "effort": 9,
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
                .andExpect(jsonPath("$.effort").value(9))
                .andExpect(jsonPath("$.status").value("in_progress"));

        mockMvc.perform(delete("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/goals/" + goalId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/folders/" + folderId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/folders")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(0));

        mockMvc.perform(get("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isNotFound());
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
                                  "effort": 4,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": ["%s"]
                                }
                                """.formatted(tagId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.effort").value(4))
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
                .andExpect(jsonPath("$.effort").value(4))
                .andExpect(jsonPath("$.tags[0].id").value(tagId));
    }

    @Test
    void successfulTaskPatchReturnsUpdatedTaskBody() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String folderId = read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Edit response",
                                  "description": "Verify update contract"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String goalId = read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Task editing",
                                  "description": "Successful patch response"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Editable task",
                                  "description": "Before edit",
                                  "type": "green",
                                  "priority": 4,
                                  "effort": 2,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "tagIds": []
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");
        String taskVersion = read(taskResponse, "/version");

        mockMvc.perform(patch("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Editable task saved",
                                  "description": "After edit",
                                  "type": "red",
                                  "priority": 6,
                                  "effort": 3,
                                  "status": "in_progress",
                                  "plannedTime": "2026-05-01T10:00:00Z",
                                  "dueTime": "2026-05-02T19:00:00Z",
                                  "archived": false,
                                  "tagIds": [],
                                  "version": %s
                                }
                                """.formatted(taskVersion)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(taskId))
                .andExpect(jsonPath("$.title").value("Editable task saved"))
                .andExpect(jsonPath("$.description").value("After edit"))
                .andExpect(jsonPath("$.type").value("red"))
                .andExpect(jsonPath("$.priority").value(5))
                .andExpect(jsonPath("$.effort").value(3))
                .andExpect(jsonPath("$.status").value("in_progress"))
                .andExpect(jsonPath("$.archived").value(false))
                .andExpect(jsonPath("$.version").exists());
    }

    @Test
    void taskChecklistPersistsInTaskDtoAndCanBeReplaced() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String folderId = read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Checklist",
                                  "description": "Task plan source of truth"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String goalId = read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Task plan",
                                  "description": "Checklist-backed plan"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Ship checklist contract",
                                  "description": "Expose plan items",
                                  "type": "green",
                                  "priority": 8,
                                  "status": "todo",
                                  "plannedTime": "2026-05-01T09:00:00Z",
                                  "dueTime": "2026-05-02T18:00:00Z",
                                  "checklistItems": [
                                    {
                                      "text": "Wire DTO",
                                      "checked": true,
                                      "displayOrder": 2
                                    },
                                    {
                                      "text": "Draft API",
                                      "checked": false,
                                      "displayOrder": 1
                                    }
                                  ],
                                  "tagIds": []
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.checklistItems.length()").value(2))
                .andExpect(jsonPath("$.checklistItems[0].text").value("Draft API"))
                .andExpect(jsonPath("$.checklistItems[0].checked").value(false))
                .andExpect(jsonPath("$.checklistItems[1].text").value("Wire DTO"))
                .andExpect(jsonPath("$.checklistItems[1].checked").value(true))
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");
        String firstItemId = read(taskResponse, "/checklistItems/0/id");

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.checklistItems[0].id").value(firstItemId))
                .andExpect(jsonPath("$.checklistItems[0].taskId").value(taskId));

        mockMvc.perform(put("/api/tasks/" + taskId + "/checklist")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "items": [
                                    {
                                      "id": "%s",
                                      "text": "Draft API contract",
                                      "checked": true,
                                      "displayOrder": 0
                                    },
                                    {
                                      "text": "Update clients",
                                      "checked": false,
                                      "displayOrder": 1
                                    }
                                  ]
                                }
                                """.formatted(firstItemId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.taskId").value(taskId))
                .andExpect(jsonPath("$.items.length()").value(2))
                .andExpect(jsonPath("$.items[0].id").value(firstItemId))
                .andExpect(jsonPath("$.items[0].text").value("Draft API contract"))
                .andExpect(jsonPath("$.items[0].checked").value(true))
                .andExpect(jsonPath("$.items[1].text").value("Update clients"));

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].checklistItems[0].text").value("Draft API contract"))
                .andExpect(jsonPath("$.items[0].checklistItems[1].checked").value(false));
    }

    @Test
    void taskListIgnoresHistoricalPriorityAndOrdersByCreatedAtThenId() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String folderId = read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Priority",
                                  "description": "Sort task list"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String goalId = read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Ordering",
                                  "description": "Higher priority first"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String firstId = read(createTask(accessToken, goalId, "First task", 5), "/id");
        String secondId = read(createTask(accessToken, goalId, "Second task", 9), "/id");
        String thirdId = read(createTask(accessToken, goalId, "Third task", 2), "/id");
        setSameCreatedAt(List.of(firstId, secondId, thirdId));
        List<String> expectedIds = taskIdsOrderedById(goalId);
        setTaskPriority(expectedIds.get(0), 1);
        setTaskPriority(expectedIds.get(1), 10);
        setTaskPriority(expectedIds.get(2), 5);

        mockMvc.perform(get("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].id").value(expectedIds.get(0)))
                .andExpect(jsonPath("$.items[0].priority").value(1))
                .andExpect(jsonPath("$.items[1].id").value(expectedIds.get(1)))
                .andExpect(jsonPath("$.items[1].priority").value(10))
                .andExpect(jsonPath("$.items[2].id").value(expectedIds.get(2)))
                .andExpect(jsonPath("$.items[2].priority").value(5));
    }

    @Test
    void oldAndNewTaskPayloadsKeepPriorityAsAnIgnoredCompatibilityShadow() throws Exception {
        String accessToken = read(registerAndLogin(), "/tokens/accessToken");
        String folderId = createFolder(accessToken, "Compatibility");
        String goalId = createGoal(accessToken, folderId, "Priority retirement");

        String oldClientTask = createTask(accessToken, goalId, "Old client", 10);
        String omittedPriorityTask = createTaskWithoutPriority(accessToken, goalId, "New client", null);
        String nullPriorityTask = createTaskWithoutPriority(accessToken, goalId, "Nullable client", "null");

        String oldClientTaskId = read(oldClientTask, "/id");
        org.junit.jupiter.api.Assertions.assertEquals("5", read(oldClientTask, "/priority"));
        org.junit.jupiter.api.Assertions.assertEquals("5", read(omittedPriorityTask, "/priority"));
        org.junit.jupiter.api.Assertions.assertEquals("5", read(nullPriorityTask, "/priority"));

        setTaskPriority(oldClientTaskId, 9);
        String historical = mockMvc.perform(get("/api/tasks/" + oldClientTaskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(9))
                .andReturn().getResponse().getContentAsString();

        mockMvc.perform(patch("/api/tasks/" + oldClientTaskId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskUpdatePayload("Old payload update", "\"priority\": 1,", read(historical, "/version"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(9));
        String afterOldUpdate = getTask(accessToken, oldClientTaskId);

        mockMvc.perform(patch("/api/tasks/" + oldClientTaskId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskUpdatePayload("Omitted priority update", "", read(afterOldUpdate, "/version"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(9));
        String afterOmittedUpdate = getTask(accessToken, oldClientTaskId);

        mockMvc.perform(patch("/api/tasks/" + oldClientTaskId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskUpdatePayload("Null priority update", "\"priority\": null,", read(afterOmittedUpdate, "/version"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(9));
    }

    @Test
    void cloneUsesLegacyPriorityWhileMoveToGoalPreservesHistoricalShadow() throws Exception {
        String accessToken = read(registerAndLogin(), "/tokens/accessToken");
        String folderId = createFolder(accessToken, "Clone and move");
        String sourceGoalId = createGoal(accessToken, folderId, "Source");
        String targetGoalId = createGoal(accessToken, folderId, "Target");
        String source = createTask(accessToken, sourceGoalId, "Historical source", 8);
        String sourceId = read(source, "/id");
        setTaskPriority(sourceId, 8);

        mockMvc.perform(post("/api/tasks/" + sourceId + "/clone")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetGoalId": "%s",
                                  "title": "Compatibility clone"
                                }
                                """.formatted(targetGoalId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.priority").value(5));

        String current = mockMvc.perform(get("/api/tasks/" + sourceId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.priority").value(8))
                .andReturn().getResponse().getContentAsString();

        mockMvc.perform(post("/api/tasks/" + sourceId + "/move-to-goal")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "targetGoalId": "%s",
                                  "version": %s
                                }
                                """.formatted(targetGoalId, read(current, "/version"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.goalId").value(targetGoalId))
                .andExpect(jsonPath("$.priority").value(8));
    }

    @Test
    void taskEffortDefaultsFromNullAndRejectsNegativeValues() throws Exception {
        String tokens = registerAndLogin();
        String accessToken = read(tokens, "/tokens/accessToken");

        String folderId = read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Defaults",
                                  "description": "Default task fields"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String goalId = read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Task defaults",
                                  "description": "Verify compatible defaults"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");

        String taskResponse = mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Nullable effort task",
                                  "description": "Client sends null effort",
                                  "type": "green",
                                  "priority": 5,
                                  "effort": null,
                                  "status": "todo",
                                  "plannedTime": "2026-05-03T09:00:00Z",
                                  "dueTime": "2026-05-04T18:00:00Z"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.effort").value(0))
                .andReturn().getResponse().getContentAsString();
        String taskId = read(taskResponse, "/id");

        mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.effort").value(0));

        mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "Negative effort task",
                                  "description": "Rejected by validation",
                                  "type": "green",
                                  "priority": 5,
                                  "effort": -1,
                                  "status": "todo",
                                  "plannedTime": "2026-05-03T09:00:00Z",
                                  "dueTime": "2026-05-04T18:00:00Z"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("validation_error"));
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
                .andReturn().getResponse().getContentAsString();
    }

    private String createTaskWithoutPriority(String accessToken, String goalId, String title, String priorityValue) throws Exception {
        String priorityProperty = priorityValue == null ? "" : "\"priority\": " + priorityValue + ",";
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "title": "%s",
                                  "description": "Task description",
                                  "type": "green",
                                  %s
                                  "status": "todo",
                                  "tagIds": []
                                }
                                """.formatted(title, priorityProperty)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
    }

    private String createFolder(String accessToken, String name) throws Exception {
        return read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Compatibility fixture"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");
    }

    private String createGoal(String accessToken, String folderId, String name) throws Exception {
        return read(mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "Compatibility fixture"
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "/id");
    }

    private String taskUpdatePayload(String title, String priorityProperty, String version) {
        return """
                {
                  "title": "%s",
                  "description": "Task description",
                  "type": "green",
                  %s
                  "status": "todo",
                  "plannedTime": "2026-05-01T09:00:00Z",
                  "dueTime": "2026-05-02T18:00:00Z",
                  "archived": false,
                  "tagIds": [],
                  "version": %s
                }
                """.formatted(title, priorityProperty, version);
    }

    private String getTask(String accessToken, String taskId) throws Exception {
        return mockMvc.perform(get("/api/tasks/" + taskId)
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
    }

    private void setTaskPriority(String taskId, int priority) throws Exception {
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.prepareStatement("update tasks set priority = ? where id = ?")) {
            statement.setInt(1, priority);
            statement.setObject(2, UUID.fromString(taskId));
            statement.executeUpdate();
        }
    }

    private void setSameCreatedAt(List<String> taskIds) throws Exception {
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.prepareStatement("update tasks set created_at = '2026-01-01T00:00:00Z' where id = ?")) {
            for (String taskId : taskIds) {
                statement.setObject(1, UUID.fromString(taskId));
                statement.addBatch();
            }
            statement.executeBatch();
        }
    }

    private List<String> taskIdsOrderedById(String goalId) throws Exception {
        List<String> result = new ArrayList<>();
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.prepareStatement("select id from tasks where goal_id = ? order by id")) {
            statement.setObject(1, UUID.fromString(goalId));
            try (var rows = statement.executeQuery()) {
                while (rows.next()) {
                    result.add(rows.getObject(1, UUID.class).toString());
                }
            }
        }
        return result;
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
