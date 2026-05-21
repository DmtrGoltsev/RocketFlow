# MVP2 hierarchy, notes, links, dependencies contract

Date: 2026-05-18

Scope: target contract for the next RocketFlow MVP2 implementation wave after commit `reliz2` (`4d82e24c055edaae2a64d8e72701d42a78482635`).

This document is the handoff contract for backend, Android, web/iPhone, QA, and integration workers. It is based on a read-only inspection of the current code:

- backend DB: `backend/src/main/resources/db/migration/V3__planning_core.sql`, `V4__sharing_foundation.sql`, `V10__folder_and_link_sharing.sql`, `V12__ideas_and_folder_notes.sql`, `V13__idea_history_note_editing.sql`
- backend API/model: `folders`, `goals`, `tasks`, `ideas`, `sharing`
- web/iPhone: `web/src/features/planning/types.ts`, `planning-api.ts`, `TasksRoute.tsx`, `advanced/SharingRoute.tsx`
- Android: `PlanningModels.kt`, `PlanningRepository.kt`, `PlanningLocalStore.kt`, `MainActivity.kt`

## Current State Summary

- `folders` are flat: no `parent_folder_id`.
- `goals` belong to a folder and do not have a status/closure field.
- `tasks` belong to a goal and already have status `todo | in_progress | done | cancelled`.
- `ideas` belong to a folder and have editable history notes.
- Legacy folder notes/lists exist in older DB/API/client code and must be removed by V14 without data migration.
- Sharing exists for folders/goals/tasks. Folder access must give content access to goals/tasks/ideas/notes in that folder.
- Android has local/offline planning tables, pending sync, and legacy note/list models that must be replaced with `PlanningNote`.
- Web/iPhone `TasksRoute.tsx` is the main planning surface and must replace legacy folder note/list detail panels with regular note details.

## Entities

### Folder

Purpose: container and hierarchy node.

Fields:

- `id`
- `parentFolderId: UUID?`
- `ownerUserId`
- `name`
- `description`
- `displayOrder`
- `archived`
- `createdAt`
- `updatedAt`
- `version`

Rules:

- A folder can contain child folders, goals, ideas, and notes.
- Root folders have `parentFolderId = null`.
- Folder hierarchy must not allow cycles.
- A folder cannot be linked in entity links and cannot participate in dependencies.
- A folder can be moved/cloned only into another folder.
- Moving a folder into itself or any descendant is forbidden.
- Child folder owner must match parent folder owner.
- If a collaborator with full access creates a folder under a shared folder, the new folder `ownerUserId` is the shared root owner, not the collaborator. The collaborator is creator only if a later audit field is added.

### Goal

Purpose: objective inside a folder.

Fields:

- existing fields: `id`, `folderId`, `ownerUserId`, `name`, `description`, `archived`, timestamps, `version`
- add `status: todo | in_progress | done | cancelled`
- optional future/audit field: `creatorUserId`; not required for this wave unless backend worker needs creator display parity.

Rules:

- A goal belongs to a folder.
- A goal can be linked to goals, tasks, or ideas.
- A goal can be closed (`status=done`) independently of task dependencies because dependencies are task-to-task only.
- A goal can be moved/cloned only into a folder.
- Cloned goal must not copy links, dependencies, share grants, or child tasks unless explicitly requested by the clone request. Default clone copies the goal fields only.

### Task

Purpose: actionable item inside a goal.

Fields:

- existing task fields remain.
- no new status enum is required.

Rules:

- A task belongs to a goal.
- A task can be linked to goals, tasks, or ideas.
- A task can have dependencies only on other tasks.
- A task cannot be closed (`status=done`) while any active blocking task dependency is not done.
- A task can be moved/cloned only into a goal.
- Cloned task must not copy links, dependencies, share grants, recurrence, reminders, or tags unless the request explicitly opts into tags. Default clone copies title/description/type/priority/status/planned/due fields and lets user delete/edit unwanted copied content after creation.

### Idea

Purpose: non-deadline idea inside a folder, with own history notes.

Fields:

- existing fields remain, including `allowAuthorNoteEdits`.

Rules:

- An idea belongs to a folder.
- An idea can be linked to goals, tasks, or ideas.
- An idea cannot be a dependency blocker or dependent.
- An idea can be moved/cloned only into a folder.
- Clone copies idea title/body/status/settings only; it does not copy history notes, links, dependencies, or share grants by default.

### Note

Purpose: plain shared note inside a folder. Replaces user-facing `folder_note`.

Fields:

- `id`
- `folderId`
- `ownerUserId`
- `authorUserId`
- `title`
- `body`
- `displayOrder`
- `archived`
- `createdAt`
- `updatedAt`
- `version`

Rules:

- A note belongs to a folder.
- A note does not have dependencies.
- A note can be linked to goal/task/idea as a linked note.
- Linked notes are displayed in the details of the linked goal/task/idea in a collapsed list.
- Tapping/clicking a linked note opens note details.
- A note can be moved/cloned only into a folder.
- Clone copies title/body only and does not copy links or sharing.

### Entity Link

Purpose: generic relationship between supported entities.

Supported endpoints:

- `goal`
- `task`
- `idea`
- `note`

Unsupported:

- `folder`

Fields:

- `id`
- `ownerUserId`
- `sourceType`
- `sourceId`
- `targetType`
- `targetId`
- `relationType: related | dependency`
- `createdByUserId`
- `createdAt`
- `updatedAt`
- `version`
- optional `archived` if soft delete is preferred.

Rules:

- Multiple links between entities are allowed only if they are meaningfully distinct by relation type. Exact duplicates are forbidden.
- Links are directional in storage (`source -> target`) but the UI must show the relation from either side.
- Creating a link from either entity must produce the same visible relation.
- A `related` link can connect goal/task/idea/note, except folder.
- A `dependency` link is valid only for task -> task.
- Notes cannot be dependency source or target for `dependency`.
- For linked notes, the UI treats note links specially: notes appear in a collapsed "linked notes" section in goal/task/idea details.

### Task Dependency

Implementation options:

1. Use `entity_links` with `relationType='dependency'`, `sourceType='task'`, `targetType='task'`.
2. Or split into `task_dependencies` for stricter DB constraints.

Contract preference: use `entity_links` with DB checks and service validation. This keeps one relationship API while enforcing dependency rules in service and tests.

Semantics:

- Dependent task: `source task`.
- Blocking task: `target task`.
- A dependent task cannot be set to `done` while at least one active blocking task is not `done`.
- `cancelled` blockers do not satisfy dependency unless product owner later decides otherwise. Current contract: only `done` unblocks.
- Dependency cycles are forbidden.
- Self-dependency is forbidden.

## DB Migrations

Create the next Flyway migration after `V13__idea_history_note_editing.sql`.

Required DB changes:

1. `folders`
   - Add nullable `parent_folder_id uuid references folders(id) on delete cascade`.
   - Add indexes:
     - `(owner_user_id, parent_folder_id, archived, display_order, created_at)`
     - `(parent_folder_id)`
   - Add service-level cycle guard. PostgreSQL recursive constraint is optional; tests must cover.

2. `goals`
   - Add `status varchar(32) not null default 'todo'`.
   - Add check `status in ('todo', 'in_progress', 'done', 'cancelled')`.
   - Add index `(folder_id, status, archived)`.

3. `notes`
   - Create replacement table for plain folder notes:
     - `id uuid primary key`
     - `folder_id uuid not null references folders(id) on delete cascade`
     - `owner_user_id uuid not null references users(id) on delete cascade`
     - `author_user_id uuid not null references users(id) on delete restrict`
     - `title varchar(200) not null`
     - `body varchar(4000)`
     - `display_order integer not null`
     - `archived boolean not null default false`
     - `created_at timestamptz not null`
     - `updated_at timestamptz not null`
     - `version bigint not null default 0`
   - Indexes:
     - `(folder_id, owner_user_id, archived, display_order, created_at)`
     - `(owner_user_id)`
     - `(author_user_id)`

4. `entity_links`
   - Create:
     - `id uuid primary key`
     - `owner_user_id uuid not null references users(id) on delete cascade`
     - `source_type varchar(16) not null`
     - `source_id uuid not null`
     - `target_type varchar(16) not null`
     - `target_id uuid not null`
     - `relation_type varchar(16) not null`
     - `created_by_user_id uuid not null references users(id) on delete restrict`
     - `archived boolean not null default false`
     - `created_at timestamptz not null`
     - `updated_at timestamptz not null`
     - `version bigint not null default 0`
   - Checks:
     - `source_type in ('goal','task','idea','note')`
     - `target_type in ('goal','task','idea','note')`
     - `relation_type in ('related','dependency')`
     - `source_id <> target_id or source_type <> target_type`
   - Unique index for active exact duplicates:
     - `(source_type, source_id, target_type, target_id, relation_type)` where `archived=false`
   - Indexes for both directions:
     - `(source_type, source_id, archived)`
     - `(target_type, target_id, archived)`
     - `(owner_user_id, archived)`

5. `folder_notes` deletion policy
   - Existing data is deleted, not migrated.
   - Drop `folder_note_items` first, then `folder_notes`.
   - Backend/web/Android must remove all public legacy folder note/list contracts after this migration.

Compatibility note:

- If production has meaningful `folder_notes`, the backend worker must confirm product owner still accepts data deletion immediately before deploy. Current user answer says delete.

## REST Endpoints

Keep existing endpoints where possible; add new endpoints rather than overloading unrelated ones.

### Folders

- `GET /api/folders`
  - Returns all accessible folders, now with `parentFolderId`.
  - Clients build hierarchy locally.
- `GET /api/folders/{folderId}`
- `POST /api/folders`
  - Creates root folder when `parentFolderId` absent/null.
- `POST /api/folders/{folderId}/folders`
  - Creates child folder.
- `PATCH /api/folders/{folderId}`
- `DELETE /api/folders/{folderId}`
- `POST /api/folders/{folderId}/move`
  - Body: `targetFolderId`, `version`.
- `POST /api/folders/{folderId}/clone`
  - Body: `targetFolderId`, optional `name`.

### Goals

- Existing:
  - `GET /api/folders/{folderId}/goals`
  - `POST /api/folders/{folderId}/goals`
  - `GET /api/goals/{goalId}`
  - `PATCH /api/goals/{goalId}`
  - `DELETE /api/goals/{goalId}`
- Add:
  - `POST /api/goals/{goalId}/move`
  - `POST /api/goals/{goalId}/clone`

### Tasks

- Existing:
  - `GET /api/goals/{goalId}/tasks`
  - `POST /api/goals/{goalId}/tasks`
  - `GET /api/tasks/{taskId}`
  - `PATCH /api/tasks/{taskId}`
  - `DELETE /api/tasks/{taskId}`
- Existing `POST /api/tasks/{taskId}/move` is currently time move/reschedule. Do not reuse it for hierarchy move.
- Add:
  - `POST /api/tasks/{taskId}/move-to-goal`
  - `POST /api/tasks/{taskId}/clone`

### Ideas

- Existing idea endpoints stay.
- Add:
  - `POST /api/ideas/{ideaId}/move`
  - `POST /api/ideas/{ideaId}/clone`

### Notes

Target notes API:

- `GET /api/folders/{folderId}/notes`
- `POST /api/folders/{folderId}/notes` returning `NoteDto`
- `GET /api/notes/{noteId}`
- `PATCH /api/notes/{noteId}`
- `DELETE /api/notes/{noteId}`
- `POST /api/notes/{noteId}/move`
- `POST /api/notes/{noteId}/clone`

Remove the legacy folder note/list API from the public target contract:

- No `kind`-based folder note/list DTO is allowed for target `notes`.
- No item-based folder note/list routes are allowed in the target API.
- Any old route kept temporarily for compatibility must return an explicit removal response such as 404 or 410.

### Links and Dependencies

- `GET /api/entity-links?entityType={goal|task|idea|note}&entityId={uuid}`
  - Returns links where the entity is either source or target.
- `POST /api/entity-links`
  - Creates a related link or task dependency.
- `PATCH /api/entity-links/{linkId}`
  - Allows relation type changes only if valid. Use sparingly; delete/recreate is acceptable if simpler.
- `DELETE /api/entity-links/{linkId}`
  - Soft delete/archive preferred.

For dependency creation:

- Request with `relationType='dependency'` requires `sourceType='task'` and `targetType='task'`.
- Response should include both entities summarized for UI.

### Sharing

Existing sharing endpoints should be extended with access mode:

- `POST /api/folders/{folderId}/share`
- `POST /api/goals/{goalId}/share`
- `POST /api/tasks/{taskId}/share`
- `POST /api/.../share-links`

Add field:

- `accessLevel: owner_full | read` or simpler `fullAccess: boolean`.

Contract for this wave:

- Default when not provided: existing behavior, treated as read/content-limited for backward compatibility.
- Owner UI should expose one button "Full access".
- If full access is enabled for a shared folder/goal/task, collaborator can create/edit/move/clone lower-category descendants within that shared subtree.

## DTOs

### FolderDto

Add:

- `parentFolderId: UUID?`
- `shared: boolean`
- `fullAccess: boolean`

### CreateFolderRequest / UpdateFolderRequest

Add:

- `parentFolderId: UUID?` for root create/update if using single endpoint.
- `version` remains required for update/move.

### GoalDto

Add:

- `status`
- `fullAccess`

### CreateGoalRequest / UpdateGoalRequest

Add:

- `status` optional on create, required/optional on update with default `todo`.

### TaskDto

Add:

- `blockedBy: EntityLinkSummary[]` optional for detail endpoints, or expose through separate entity-links endpoint only. Separate endpoint is preferred for list performance.

### IdeaDto

No required field changes.

### NoteDto

New:

- `id`
- `folderId`
- `title`
- `body`
- `displayOrder`
- `archived`
- `shared`
- `fullAccess`
- `authorUserId`
- `authorEmail`
- `authorName`
- `version`
- `createdAt`
- `updatedAt`

### EntityLinkDto

New:

- `id`
- `source: EntityRefDto`
- `target: EntityRefDto`
- `relationType: related | dependency`
- `createdByUserId`
- `createdByName`
- `createdAt`
- `updatedAt`
- `version`

`EntityRefDto`:

- `type: goal | task | idea | note`
- `id`
- `title`
- `subtitle`
- `status?`
- `path`
- `archived`
- MVP3 redaction addendum: accessible refs also include `accessible: true` and `redacted: false`.
  Inaccessible opposite-side refs in `GET /api/entity-links` include `accessible: false` and `redacted: true`;
  private `type`, `id`, `title`, `subtitle`, `status`, `path`, and `archived` are null or omitted.

### Move Request

Use entity-specific endpoints with simple DTOs:

- Folder move: `{ targetFolderId, version }`
- Goal move: `{ targetFolderId, version }`
- Task move: `{ targetGoalId, version }`
- Idea move: `{ targetFolderId, version }`
- Note move: `{ targetFolderId, version }`

### Clone Request

- Folder clone: `{ targetFolderId, name?, includeChildren?: false }`
- Goal clone: `{ targetFolderId, name? }`
- Task clone: `{ targetGoalId, title?, includeTags?: false }`
- Idea clone: `{ targetFolderId, title? }`
- Note clone: `{ targetFolderId, title? }`

Default clone flags must be conservative and not copy dependencies/sharing.

## Permissions

Definitions:

- `owner`: `ownerUserId == actorUserId`.
- `fullAccess collaborator`: user who received explicit full access on an entity or inherited it from an ancestor.
- `read/shared collaborator`: existing shared access without full access.

Rules:

- Owner has full access to all owned entities.
- Full access collaborator can create/edit/archive/move/clone descendants within the shared subtree.
- Full access collaborator does not become owner. New descendants created inside a shared subtree inherit the original owner of the shared ancestor.
- Full access collaborator can create links/dependencies only between entities they can access and only when they have full access on the source entity's owning subtree.
- Read/shared collaborator can view and, only where existing behavior already allows, create tasks if legacy `createTaskGoalIds` grants it. New work should prefer `fullAccess`.
- Sharing a parent entity grants access to lower-category descendants:
  - shared folder: child folders, goals, tasks, ideas, notes, and links in subtree.
  - shared goal: tasks inside goal plus links involving that goal/tasks when both sides are accessible.
  - shared task: that task and its visible links if target is accessible.
- Sharing does not automatically share unrelated linked entities unless access is independently granted.
  MVP3 supersedes the MVP2 omission preference: `GET /api/entity-links` returns the link row for an accessible requested entity and redacts any inaccessible opposite-side `EntityRefDto`.

## Clone / Move Behavior

### Move

- Move changes the parent reference:
  - folder: `parentFolderId`
  - goal: `folderId`
  - task: `goalId`
  - idea: `folderId`
  - note: `folderId`
- Move must preserve `id`, timestamps except `updatedAt`, owner, creator/author, status, links, dependencies, notes, and sharing.
- Move must validate target access and owner compatibility.
- Move between different owners is forbidden unless backend explicitly re-parents ownership; this wave forbids cross-owner move.
- Drag-and-drop and `three dots -> Move` must call the same backend move endpoint.

### Clone

- Clone creates a new entity with a new `id`.
- Clone copies core editable fields.
- Clone does not copy:
  - dependencies
  - links
  - sharing grants
  - idea history
  - note links
  - reminders
  - recurrence
- Clone target must be selected by user.
- After clone, UI opens the cloned entity details so user can delete/edit extra copied content.
- Backend response returns the cloned DTO and enough path info to navigate.

## Dependency Closure Rules

Only task-to-task dependencies block closure.

When updating a task:

- If status is changing to `done`, backend checks all active `dependency` links where source is this task.
- For each blocking target task, backend requires `status='done'` and `archived=false`.
- If any blocking task is not done, reject with:
  - HTTP `409 Conflict`
  - code `dependency_blocked`
  - details containing blocker task ids and titles.

When updating a blocker task away from `done`:

- Allowed.
- Dependent tasks already done remain done. No automatic reopening in this wave.

Dependency graph:

- Self-dependency forbidden.
- Cycles forbidden.
- Duplicate active dependency forbidden.
- Cross-goal dependencies allowed.
- Cross-owner dependencies only allowed if actor has access to both tasks; this creates a link but does not grant sharing to either side.

Goal status:

- Goal can be set to done without dependency checks.
- UI may warn if not all child tasks are done, but backend does not block unless product later requires it.

## Android Sync Implications

Android worker must update:

- `android/app/src/main/java/com/rocketflow/companion/planning/PlanningModels.kt`
- `PlanningRepository.kt`
- `PlanningLocalStore.kt`
- `PlanningSyncWorker.kt` if needed
- `MainActivity.kt`
- Android instrumented/unit tests under `android/app/src/androidTest` and `android/app/src/test`

Required changes:

- Add `parentFolderId` to `PlanningFolder`, local DB, JSON parsing, create/update/push/pull.
- Add `status` to `PlanningGoal`, local DB, JSON parsing, create/update/push/pull.
- Remove legacy folder note/list drafts, local tables, pending sync, repository methods, and UI copy.
- Add `PlanningNote`, `NoteDraft`, local table, pending create/update/delete, pull/push, UI detail.
- Add `EntityLink`, `EntityRef`, local table, pull/push if offline is supported for links.
- Support dependency blocked API error and show actionable message.
- Add move/clone methods for folder/goal/task/idea/note.
- Drag-and-drop:
  - folder rows can be dropped on folder rows.
  - goals can be dropped on folders.
  - tasks can be dropped on goals.
  - ideas/notes can be dropped on folders.
  - Invalid drop targets must show localized rejection and not create pending local changes.
- `three dots -> Move` must use explicit target picker and same repository method as drag.
- Shared full access must be represented locally (`fullAccess` flag) and used for UI enabling.
- Offline conflicts:
  - If dependency close fails during sync, mark task `Conflict` with `dependency_blocked` message.
  - If move target no longer exists, mark moved entity `Conflict`.

## Web / iPhone UI Implications

Web worker must update:

- `web/src/features/planning/types.ts`
- `web/src/features/planning/planning-api.ts`
- `web/src/features/planning/planning-copy.ts`
- `web/src/features/planning/routes/TasksRoute.tsx`
- `web/src/features/advanced/advanced-copy.ts`
- `web/src/features/advanced/routes/SharingRoute.tsx`
- `web/src/styles/components.css`
- Tests if present.

Required UI behavior:

- Folder detail header:
  - left: `Cancel`
  - center: `Add`
  - right: `Edit`
  - Add menu items: folder, goal, idea, note.
- Goal detail header:
  - left: `Cancel`
  - center: `Add`
  - right: `Edit`
  - Add creates task.
- Remove all legacy `Folder note` and `List` user flows.
- Notes can be created inside any folder, opened, edited, shared through parent access, moved, cloned, and linked.
- Ideas can be created inside any folder, opened, edited, moved, cloned, and linked.
- Entity detail pages for goal/task/idea show:
  - direct links/dependencies section;
  - dependencies clickable to open target entity details;
  - linked notes as collapsed list, expandable;
  - each linked note clickable to open note details.
- Creating a link can start from either entity in the relation.
- Dependency option appears only when both selected entities are tasks.
- iPhone viewport must keep primary buttons reachable above browser bottom bars.
- Drag-and-drop for iPhone/web:
  - Use pointer/touch compatible implementation.
  - Provide non-drag fallback through `three dots -> Move`.
  - Invalid targets must be visibly rejected without data changes.
- All new strings go through RU/EN copy dictionaries.

## Migration / Deletion Policy for `folder_notes`

User decision: delete existing `folder_notes`; do not migrate.

Implementation policy:

- Remove user-facing legacy folder note/list concepts from backend DTO/API, web, Android, and copy.
- Drop tables in DB migration:
  - `folder_note_items`
  - `folder_notes`
- Do not map old rows to new `notes`.
- Add a release note warning that old folder notes/lists are removed.
- QA must verify no UI labels remain:
  - `Folder note`
  - `List`
  - `Заметка папки`
  - `Список`

## QA Acceptance Matrix

Backend:

- Nested folders:
  - create root folder;
  - create child folder;
  - create grandchild folder;
  - reject cycle move;
  - reject move into self/descendant.
- Goal status:
  - create default `todo`;
  - update to `in_progress`;
  - update to `done`;
  - reject invalid status.
- Notes:
  - create/edit/archive note in folder;
  - note appears in folder details;
  - legacy folder note/list endpoints are gone or return expected 404/410 if kept temporarily.
- Links:
  - create goal-task related link;
  - create idea-task related link;
  - create note-task related link;
  - list from both sides;
  - reject folder link;
  - reject duplicate exact link.
- Dependencies:
  - create task->task dependency;
  - reject task->goal dependency;
  - reject goal->task dependency;
  - reject note dependency;
  - reject cycle;
  - block closing dependent task while blocker not done;
  - allow closing after blocker done.
- Move:
  - folder->folder;
  - goal->folder;
  - task->goal;
  - idea/note->folder;
  - reject invalid target types.
- Clone:
  - clone each supported entity;
  - verify no links/dependencies/shares copied;
  - verify cloned detail opens with editable copied content.
- Sharing:
  - default collaborator cannot full-edit unless full access granted;
  - full access collaborator can create descendants;
  - full access inherited down subtree;
  - no access leak through links.

Android:

- Same scenarios as backend through UI.
- Offline create/update/move/clone/link queues and syncs.
- Dependency block conflict visible.
- Drag-and-drop works for valid matrix and rejects invalid drops.
- `three dots -> Move` works for all movable types.
- Screenshots required for two users: owner Android and collaborator iPhone-web.

Web/iPhone:

- Same functional scenarios in mobile viewport.
- Buttons in folder/goal detail match contract.
- Add menu creates correct child types.
- Linked notes are collapsed by default and expandable.
- Dependency links are clickable.
- Save buttons are not hidden by iPhone browser bottom bar.

Localization:

- RU mode contains only Russian labels for new features.
- EN mode contains only English labels for new features.
- No legacy English labels (`Folder note`, `List`) or accidental `Idea` leaks in RU.

Build evidence:

- `git diff --check`
- backend `mvn test`
- web `npm run build`
- Android `assembleDebug`
- full QA screenshots folder for Android and iPhone-web
- final QA lead PASS report

## Worker File Ownership

### Backend DB/domain worker (`xhigh`)

Files/modules:

- `backend/src/main/resources/db/migration/V14__*.sql`
- `backend/src/main/java/com/rocketflow/folders/*`
- `backend/src/main/java/com/rocketflow/goals/*`
- `backend/src/main/java/com/rocketflow/tasks/*`
- `backend/src/main/java/com/rocketflow/ideas/*`
- new `backend/src/main/java/com/rocketflow/notes/*`
- new `backend/src/main/java/com/rocketflow/links/*`
- `backend/src/main/java/com/rocketflow/sharing/*`

Responsibilities:

- DB migration.
- Entity models/repositories/services/controllers.
- Permission rules.
- Dependency closure guard.
- Move/clone services.
- Remove legacy folder note/list domain/API.

### Backend QA worker (`high`)

Files/modules:

- `backend/src/test/java/com/rocketflow/*`

Responsibilities:

- Integration tests for all QA matrix backend rows.
- Flyway migration coverage.

### Web/iPhone worker (`high`)

Files/modules:

- `web/src/features/planning/types.ts`
- `web/src/features/planning/planning-api.ts`
- `web/src/features/planning/planning-copy.ts`
- `web/src/features/planning/routes/TasksRoute.tsx`
- `web/src/features/advanced/*`
- `web/src/styles/components.css`

Responsibilities:

- New UI/contract.
- iPhone viewport behavior.
- Remove legacy folder note/list UI.
- Links/dependencies/notes UI.
- Move/clone and drag/drop/fallback.

### Android sync worker (`xhigh`)

Files/modules:

- `android/app/src/main/java/com/rocketflow/companion/planning/*`
- Android local DB code in `PlanningLocalStore.kt`
- sync worker/enqueuer if needed

Responsibilities:

- Models/local tables/pending sync.
- API parsing/push/pull for folders/goals/notes/links.
- Move/clone repository methods.
- Offline conflict handling.

### Android UI worker (`high`)

Files/modules:

- `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- Android UI resources if any

Responsibilities:

- Hierarchy UI.
- Folder/goal detail headers.
- Add menus.
- Remove legacy folder note/list UI.
- Notes/links/dependencies detail UI.
- Drag/drop and move fallback.

### Localization QA worker (`medium`)

Files/modules:

- Android copy in `MainActivity.kt`
- web copy dictionaries

Responsibilities:

- RU/EN audit.
- New labels through dictionaries only.

### QA lead/executor (`high`)

Files/modules:

- `test-artifacts/2026-05-18/reports/*`
- screenshots folders under `test-artifacts`

Responsibilities:

- Update full QA model.
- Execute two-user Android + iPhone-web validation.
- Verify screenshots are valid PNG/JPG and open in Windows Photos.

### Integration reviewer (`high`)

Responsibilities:

- Review staged diff for accidental artifacts.
- Ensure `release_1` untouched.
- Ensure commit only on `MVP2`.
- Verify build/test evidence.

## Implementation Order

1. Backend DB/domain worker defines migration and backend contract.
2. Backend QA worker adds tests against the target API.
3. Web/iPhone and Android sync workers update client contracts in parallel after backend DTOs stabilize.
4. Android UI and web UI implement behavior.
5. Localization QA.
6. Full QA lead updates model.
7. QA executor performs two-user run with screenshots.
8. Integration reviewer signs off.

## Explicit Non-Goals For This Wave

- Do not migrate old `folder_notes` data.
- Do not make folders linkable.
- Do not make notes dependency participants.
- Do not copy links/dependencies/sharing/history by default during clone.
- Do not reopen dependent tasks automatically if a blocker is moved away from done.
- Do not grant access to an otherwise private linked entity just because a visible entity links to it.
