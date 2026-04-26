# Planning CRUD Foundation

## Stage Summary

This stage implements the first planning domain slice on top of the existing backend foundation:

- folders CRUD
- goals CRUD
- tasks CRUD
- tags CRUD
- optimistic locking for mutable planning entities
- soft delete semantics for folders, goals, and tasks
- integration coverage for the end-to-end planning flow

The work stays inside the current MVP boundary and deliberately does not yet include:

- sharing permissions
- recurrence and reminders
- quick reschedule
- priority decay
- task links API
- calendar projections beyond task date fields

## Implemented Backend Scope

### Persistence

Added migration:

- `backend/src/main/resources/db/migration/V3__planning_core.sql`

Added tables:

- `folders`
- `goals`
- `tasks`
- `task_tags`
- `task_tag_links`

Key persistence rules:

- planning entities belong to an owner user
- folders, goals, and tasks use `archived` for MVP soft delete
- folders, goals, tasks, and user settings use `version` for optimistic locking
- task priority is constrained to `1..10`
- task type is constrained to `green` or `red`
- task status is constrained to `todo`, `in_progress`, `done`, or `cancelled`

### Domain/API slice

Implemented folders:

- `GET /api/folders`
- `POST /api/folders`
- `PATCH /api/folders/{folderId}`
- `DELETE /api/folders/{folderId}`

Implemented goals:

- `GET /api/folders/{folderId}/goals`
- `POST /api/folders/{folderId}/goals`
- `GET /api/goals/{goalId}`
- `PATCH /api/goals/{goalId}`
- `DELETE /api/goals/{goalId}`

Implemented tasks:

- `GET /api/goals/{goalId}/tasks`
- `POST /api/goals/{goalId}/tasks`
- `GET /api/tasks/{taskId}`
- `PATCH /api/tasks/{taskId}`
- `DELETE /api/tasks/{taskId}`

Implemented tags:

- `GET /api/tags`
- `POST /api/tags`

## Current Behavioral Decisions

- All current planning CRUD endpoints are owner-scoped.
- Access to another user's folders, goals, tasks, and tags is denied.
- `DELETE` marks records as archived instead of physically deleting them.
- Archived records are hidden from list endpoints.
- `GET` by id returns `404` for archived entities.
- Task completion timestamp is set when status becomes `done` and cleared when moved to a non-`done` status, including `cancelled`.
- Tags can be attached during task create and update.
- Task DTOs already expose stable placeholders for future sharing and recurrence expansion:
  - `shared`
  - `recurrence`
  - `reminders`

## Files Added or Extended

Planning migration:

- `backend/src/main/resources/db/migration/V3__planning_core.sql`

Folders:

- `backend/src/main/java/com/rocketflow/folders/Folder.java`
- `backend/src/main/java/com/rocketflow/folders/FolderRepository.java`
- `backend/src/main/java/com/rocketflow/folders/FolderService.java`
- `backend/src/main/java/com/rocketflow/folders/FolderController.java`
- `backend/src/main/java/com/rocketflow/folders/FoldersApi.java`

Goals:

- `backend/src/main/java/com/rocketflow/goals/Goal.java`
- `backend/src/main/java/com/rocketflow/goals/GoalRepository.java`
- `backend/src/main/java/com/rocketflow/goals/GoalService.java`
- `backend/src/main/java/com/rocketflow/goals/GoalController.java`
- `backend/src/main/java/com/rocketflow/goals/GoalsApi.java`

Tasks and tags:

- `backend/src/main/java/com/rocketflow/tasks/Task.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskRepository.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskController.java`
- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTag.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTagRepository.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTagService.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTagLink.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTagLinkId.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskTagLinkRepository.java`

Tests:

- `backend/src/test/java/com/rocketflow/PlanningCrudIntegrationTest.java`
- `backend/src/test/java/com/rocketflow/RocketFlowApplicationTests.java`

## Verification

Executed:

- `mvn test`

Current result:

- full backend test suite passes
- migration chain `V1 -> V2 -> V3` applies on embedded PostgreSQL
- planning CRUD flow passes through real HTTP, security, Flyway, JPA, and PostgreSQL-backed integration tests

## Known Gaps Left Intentionally For Next Waves

- sharing and collaborator permissions
- recurrence model and reminder rules
- quick reschedule endpoint and history
- priority decay settings application to task postponement
- task link management endpoints
- calendar-focused projection endpoints beyond current task listing

## Status Against Plan

Completed:

- backend project skeleton
- database migration setup
- auth + settings foundation
- folders / goals / tasks CRUD foundation

Next planned step:

- sharing foundation for goals and tasks
