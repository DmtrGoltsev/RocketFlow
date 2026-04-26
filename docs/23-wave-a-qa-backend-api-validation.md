# Wave A QA Backend/API Validation

## 1. Purpose

This document turns the QA-1 Wave A brief into an executable validation package for:

- the current backend foundation already in the repo
- backend subagent `A1` sharing and access work
- backend subagent `A2` recurrence and reminders work

Source alignment:

- `docs/17-qa-lead-decomposition.md`
- `docs/19-cross-lead-orchestration-plan.md`
- supporting frozen contracts from `docs/03-domain-specification.md`, `docs/05-api-contracts.md`, and `docs/14-backend-lead-decomposition.md`

Frozen execution rules:

- keep MVP scope frozen
- do not reinterpret documented behavior to make a slice easier to pass
- validate each backend slice as it lands, then rerun the full backend suite
- do not require web, Android, or push end-to-end behavior for Wave A acceptance

## 2. Current Backend Baseline

Working directory:

- `C:\Users\hp\Documents\Codex\RocketFlow\backend`

Verified on `2026-04-26`:

- `mvn test` passes locally in `backend/`

Current executable backend test targets:

- `FlywayMigrationTest`
- `AuthSettingsIntegrationTest`
- `PlanningCrudIntegrationTest`
- `RocketFlowApplicationTests`

Current migration chain under executable coverage:

- `V1__baseline_foundation.sql`
- `V2__auth_sessions.sql`
- `V3__planning_core.sql`

Execution rule for all Wave A backend slices:

- run the focused slice target first
- rerun `PlanningCrudIntegrationTest` for any slice that touches `goals`, `tasks`, or shared task DTOs
- rerun `FlywayMigrationTest` for any slice that adds or changes a Flyway migration
- finish with `mvn test`

## 3. Pack A: Foundation and Contract Pack

Run this pack now against the current foundation and rerun it after each Wave A backend merge candidate.

Commands:

- `mvn -Dtest=FlywayMigrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest test`
- `mvn -Dtest=RocketFlowApplicationTests test`
- `mvn test`

Checklist:

- [ ] Flyway applies the full migration chain from an empty PostgreSQL database to the newest version without repair steps or checksum drift.
- [ ] Spring Boot starts with Flyway, JPA, and security enabled.
- [ ] `POST /api/auth/register` returns the documented auth payload and creates a usable session.
- [ ] `POST /api/auth/login` and `POST /api/auth/refresh` return working token pairs.
- [ ] `GET /api/me` returns stable user profile fields.
- [ ] `GET /api/me/settings` returns stable settings DTO fields and defaults.
- [ ] `PATCH /api/me/settings` persists changes and keeps optimistic-locking version behavior intact.
- [ ] Stale settings writes are rejected with `409 Conflict`; silent overwrite is never acceptable.
- [ ] Protected endpoints reject missing or invalid bearer tokens with `401`.
- [ ] Validation and business-rule failures continue to use the common API error model.

Pack A blockers:

- migration failure or migration-order drift
- auth regression on register, login, or refresh
- settings payload drift on a frozen contract
- silent stale-write overwrite

## 4. Pack B: Planning CRUD Pack

Run this pack now against the current foundation and rerun it after each Wave A backend merge candidate that touches planning access paths or task DTOs.

Commands:

- `mvn -Dtest=PlanningCrudIntegrationTest test`
- `mvn test`

Checklist:

- [ ] Owner-scoped folder, goal, task, and tag create/read/update/archive flows still succeed end to end.
- [ ] `POST /api/tags` and task tag assignment still work on both create and update paths.
- [ ] Existing planning endpoints remain owner-scoped until sharing is explicitly accepted.
- [ ] Soft delete continues to hide archived records from list endpoints.
- [ ] Archived-detail behavior does not change silently inside a branch; if a slice changes archived `GET` semantics, QA requires explicit document sync before pass.
- [ ] Folder, goal, and task writes continue to honor optimistic locking with `409 Conflict` on stale versions.
- [ ] Task DTO shape remains stable for `shared`, `recurrence`, and `reminders`, including placeholder behavior when no sharing or scheduling data exists yet.
- [ ] Wave A work does not regress existing task create/update status handling.

Pack B blockers:

- owner-scope leak on current planning endpoints
- silent overwrite on mutable planning entities
- DTO drift that breaks frozen client expectations
- untracked change to archived-read behavior

## 5. Immediate Validation Checklist for A1 Sharing and Access

This is the first Wave A backend slice gate for sharing and centralized permissions.

Expected new primary test target:

- `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`

Commands QA expects to run when A1 lands:

- `mvn -Dtest=FlywayMigrationTest,SharingIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest test`
- `mvn test`

Immediate checklist:

- [ ] New share-related migrations apply cleanly from `V1` to the newest version.
- [ ] `POST /api/goals/{goalId}/share` returns `201 Created` with `id`, `targetType`, `targetId`, `targetEmail`, `status`, `createdAt`, and `expiresAt`.
- [ ] `POST /api/tasks/{taskId}/share` returns the same contract shape for task shares.
- [ ] `GET /api/shares/invitations` lists invitations visible to the invited user.
- [ ] `POST /api/shares/invitations/{invitationId}/accept` changes status to `accepted`.
- [ ] `POST /api/shares/invitations/{invitationId}/decline` changes status to `declined`.
- [ ] `POST /api/shares/invitations/{invitationId}/revoke` changes status to `revoked`.
- [ ] Self-invite is rejected.
- [ ] Duplicate active invitation or duplicate effective access is rejected.
- [ ] Accepted goal share grants collaborator access to the shared goal and its tasks.
- [ ] Accepted task share grants collaborator access only to the directly shared task.
- [ ] Folder ownership remains owner-only; collaborators discover shared goals and tasks through `/api/shares/resources`, not folder ownership.
- [ ] Revoked, declined, and expired invitations do not grant access.
- [ ] `/api/shares/resources` lists only accepted accessible resources and marks them as `shared: true`.
- [ ] Existing goal and task read/write endpoints use centralized permission checks instead of owner-only shortcuts.
- [ ] Shared goal and shared task stale writes still return `409 Conflict`.

A1 blockers:

- any permission leak
- any collaborator visibility outside the documented goal/task rules
- any owner-only shortcut left in an accepted-share path
- any silent stale-write overwrite on a shared entity

## 6. Immediate Validation Checklist for A2 Recurrence and Reminders

This is the parallel Wave A backend slice gate for recurrence and reminder rule persistence, validation, and DTO stability.

Expected new primary test target:

- `backend/src/test/java/com/rocketflow/RecurrenceReminderIntegrationTest.java`

Commands QA expects to run when A2 lands:

- `mvn -Dtest=FlywayMigrationTest,RecurrenceReminderIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,RecurrenceReminderIntegrationTest test`
- `mvn test`

Immediate checklist:

- [ ] New recurrence/reminder migrations apply cleanly from `V1` to the newest version.
- [ ] `PUT /api/tasks/{taskId}/recurrence` accepts supported MVP recurrence payloads and returns a stable recurrence object.
- [ ] Weekly recurrence without at least one weekday is rejected.
- [ ] Recurrence payloads with incoherent timing anchors are rejected.
- [ ] `GET /api/tasks/{taskId}` returns stable stored recurrence state after write.
- [ ] `PUT /api/tasks/{taskId}/reminders` accepts valid reminder rules and returns stable reminder objects with ids.
- [ ] Invalid reminder-anchor combinations are rejected.
- [ ] Reminder rules that depend on `plannedTime` fail when `plannedTime` is absent.
- [ ] Reminder rules that depend on `dueTime` fail when `dueTime` is absent.
- [ ] Task reads remain stable when reminders are empty, present, replaced, or disabled.
- [ ] Recurrence and reminder calculations use the owner's canonical timezone.
- [ ] A user timezone change affects future recurrence/reminder evaluation only.
- [ ] Shared-task reminder semantics remain owner-scoped in MVP; A2 must not create collaborator-specific reminder behavior.
- [ ] If `PUT /api/tasks/{taskId}/reminders` is implemented as full replacement, omission removes previous reminder rules predictably.
- [ ] If `PUT /api/tasks/{taskId}/reminders` is implemented as partial patch instead, `docs/05-api-contracts.md` must be updated before QA can pass the slice.

A2 blockers:

- invalid recurrence or reminder payloads accepted as valid
- owner timezone ignored or misapplied
- collaborator-targeted reminders introduced in MVP
- unannounced `PUT /reminders` contract drift
- task DTO breakage when recurrence or reminders are present

## 7. Cancelled-Status Documentation Drift

Drift item:

- `docs/03-domain-specification.md` and `docs/05-api-contracts.md` include task status `cancelled` and `POST /api/tasks/{taskId}/cancel`
- `docs/10-planning-crud-foundation.md` still states task status is constrained to `todo`, `in_progress`, and `done`
- `docs/17-qa-lead-decomposition.md` and `docs/19-cross-lead-orchestration-plan.md` already flag this as drift

QA treatment rule:

- treat this as documentation drift, not as product ambiguity
- the frozen task status set remains `todo`, `in_progress`, `done`, `cancelled`
- do not accept any Wave A backend slice that hard-codes the three-status model into validation, persistence, DTO mapping, or task update behavior
- do not treat A1 or A2 as responsible for adding new cancel-flow product scope beyond the frozen contract
- if a Wave A slice touches task write semantics, task DTO shape, or status validation, QA must re-open this drift item and require explicit reconciliation before pass

Practical validation effect:

- Pack A and Pack B may stay green only if A1 and A2 do not further entrench the stale three-status assumption
- the first backend integration pass that touches task-status semantics must add or restore executable coverage for the frozen four-status model and the cancel route

## 8. Exact Commands and Test Targets QA Expects

Current foundation targets:

- `mvn -Dtest=FlywayMigrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest test`
- `mvn -Dtest=RocketFlowApplicationTests test`
- `mvn test`

Expected Wave A landing targets:

- `mvn -Dtest=FlywayMigrationTest,SharingIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest test`
- `mvn -Dtest=FlywayMigrationTest,RecurrenceReminderIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,RecurrenceReminderIntegrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest,PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,FlywayMigrationTest,RocketFlowApplicationTests test`
- `mvn test`

Expected dedicated test files as slices land:

- `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`
- `backend/src/test/java/com/rocketflow/RecurrenceReminderIntegrationTest.java`

QA enforcement rule:

- if A1 lands without `SharingIntegrationTest`, QA marks the slice incomplete
- if A2 lands without `RecurrenceReminderIntegrationTest`, QA marks the slice incomplete
- if either slice adds migrations without rerunnable Flyway coverage from empty DB, QA marks the slice incomplete
