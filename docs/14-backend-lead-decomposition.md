# RocketFlow Backend Lead Decomposition

## 1. Purpose

This document decomposes the remaining backend MVP work after:

- backend skeleton and migrations
- auth and settings foundation
- owner-scoped folders, goals, tasks, and tags CRUD

The goal is to split the remaining backend scope into safe implementation slices without re-opening frozen MVP decisions.

## 2. Frozen Baseline

The backend lead should treat the following as already frozen unless a hard contradiction forces clarification:

- modular monolith architecture
- PostgreSQL plus Flyway migrations
- bearer-token auth model already implemented
- owner-only folders in MVP
- goal and task sharing only
- owner-scoped reminder delivery in MVP, even for shared resources
- recurring behavior staying on the same task record in MVP
- in-process scheduling, not a separate worker platform

## 3. Contradiction To Resolve Once, Then Freeze Again

One documentation mismatch exists in the handoff set:

- `docs/03-domain-specification.md` and `docs/05-api-contracts.md` include the `cancelled` task status and `POST /api/tasks/{taskId}/cancel`
- `docs/10-planning-crud-foundation.md` still describes the planning slice as CRUD-only and does not list the cancel endpoint

Backend recommendation:

- do not redesign task status semantics
- treat `todo`, `in_progress`, `done`, and `cancelled` as the frozen task status set
- treat the missing cancel mention in `docs/10-planning-crud-foundation.md` as documentation drift, not as a reason to expand or shrink MVP scope

This is not a blocker for the remaining backend work, but it should be acknowledged before parallel subagents start touching task flows.

## 4. Remaining Backend Workstreams

### Workstream A. Sharing and Authorization Foundation

Scope:

- share invitation persistence and lifecycle
- goal share and task share persistence
- centralized permission resolution for owner, goal collaborator, and task collaborator
- shared resource discovery endpoint
- authorization wiring for existing goal and task endpoints

Definition of done:

- accepted goal shares grant access to the goal and its tasks
- accepted task shares grant access only to the directly shared task
- revoked and expired invitations do not grant access
- existing planning endpoints enforce centralized access checks instead of owner-only assumptions

### Workstream B. Recurrence and Reminder Domain Foundation

Scope:

- recurrence rule persistence, validation, and lifecycle
- reminder rule persistence, validation, and eligibility calculation
- task DTO expansion from placeholders to real recurrence and reminder payloads
- timezone-aware scheduling calculations using the owner's canonical timezone

Definition of done:

- `PUT /api/tasks/{taskId}/recurrence` works for supported MVP shapes
- `PUT /api/tasks/{taskId}/reminders` works and rejects invalid anchor combinations
- task reads expose stable recurrence and reminder state

### Workstream C. Calendar, Move, Quick Reschedule, and Priority Decay

Scope:

- calendar projection endpoint
- task move endpoint
- quick reschedule endpoint and preset handling
- reschedule event persistence
- priority decay evaluation using owner settings and task type
- auditability for postponement and resulting priority changes

Definition of done:

- `GET /api/calendar` returns owner-visible and collaborator-visible tasks correctly
- `POST /api/tasks/{taskId}/move` updates planned time and records postpone history when required
- `POST /api/tasks/{taskId}/reschedule` supports `30m`, `1h`, `3h`, and `24h`
- priority decay applies only when policy conditions are met

### Workstream D. Device Registration and Notification Delivery

Scope:

- device registration persistence and API
- reminder-to-delivery scheduling bridge
- FCM sender abstraction and delivery logging
- idempotent-enough delivery behavior for MVP

Definition of done:

- Android devices can register and unregister
- eligible owner reminders generate delivery attempts
- delivery results are logged
- shared tasks still notify the owner only

### Workstream E. Backend Hardening and Release-Facing Coverage

Scope:

- integration and API coverage for new backend slices
- migration-chain stability for new tables
- permission, scheduling, and notification regressions
- documentation sync when implementation materially changes contract wording

Definition of done:

- backend high-risk flows are covered by focused tests
- migrations apply cleanly from `V1` through the newest version
- no critical permission or scheduling regressions remain open

## 5. Recommended Task Breakdown

### A. Sharing and Authorization Tasks

1. Add migration(s) for `goal_shares`, `task_shares`, and `share_invitations`.
2. Implement JPA entities and repositories under `sharing`.
3. Implement invitation creation, accept, decline, revoke, and expiry handling.
4. Introduce a centralized permission service used by `goals`, `tasks`, `calendar`, and later scheduling flows.
5. Implement `POST /api/goals/{goalId}/share`, `POST /api/tasks/{taskId}/share`, `GET /api/shares/invitations`, `POST /api/shares/invitations/{invitationId}/accept`, `POST /api/shares/invitations/{invitationId}/decline`, `POST /api/shares/invitations/{invitationId}/revoke`, and `GET /api/shares/resources`.
6. Convert existing owner-only planning reads and writes to use the shared permission layer.
7. Add integration tests for the permission matrix, including revocation and stale-access cases.

### B. Recurrence and Reminder Tasks

1. Add migration(s) for `task_recurrence_rules` and `task_reminder_rules`.
2. Implement recurrence entities, repositories, validators, and next-occurrence calculation services under `recurrence`.
3. Implement reminder entities, repositories, validators, and eligibility services under `reminders`.
4. Replace task DTO placeholders with real recurrence and reminder mappings.
5. Add endpoint handlers for recurrence and reminders.
6. Add focused tests for weekly rule validation, reminder anchor validation, and owner-timezone behavior.

### C. Calendar, Reschedule, and Priority Tasks

1. Add migration(s) for `task_reschedule_events`.
2. Implement `RescheduleService` and `PriorityDecayService`.
3. Implement `POST /api/tasks/{taskId}/move` with postponement detection.
4. Implement `POST /api/tasks/{taskId}/reschedule` with preset handling.
5. Implement `GET /api/calendar?from=...&to=...`.
6. Ensure collaborator postponement records actor identity but applies the owner's policy.
7. Add tests for postponement auditability, no-planned-time rejection, threshold behavior, and visibility through calendar projections.

### D. Notification Tasks

1. Add migration(s) for `device_registrations` and `notification_deliveries`.
2. Implement `POST /api/devices` and `DELETE /api/devices/{deviceId}`.
3. Implement notification payload preparation and an FCM gateway abstraction under `notifications`.
4. Implement in-process reminder polling or claim logic consistent with the single-instance MVP deployment rule.
5. Persist delivery attempts and outcomes.
6. Add tests for owner-only notification semantics, duplicate-token handling, and delivery logging.

### E. Hardening Tasks

1. Create dedicated integration test classes instead of continuing to grow a single shared planning test file.
2. Add regression coverage for permission leaks, scheduling drift, and reminder duplication.
3. Add migration verification for every new Flyway step.
4. Reconcile any contract-level changes back into `docs/05-api-contracts.md` only if implementation requires them.

## 6. Sequential Vs Parallel Execution

### Sequential Gate 0

These tasks should happen first and should not be split across multiple backend subagents:

1. Confirm the task-status contradiction is only documentation drift.
2. Reserve ownership of shared coordination surfaces:
   - Flyway migration ordering
   - shared task DTOs
   - shared permission interface
3. Define naming for new integration test classes to avoid file collisions.

### Parallel Wave 1

These can run in parallel after Gate 0:

- Workstream A: sharing and authorization foundation
- Workstream B: recurrence and reminder domain foundation

Why this is safe:

- sharing owns access-control semantics
- recurrence and reminders own rule persistence and validation
- they can proceed mostly independently if both avoid editing the same shared task DTO code at the same time

### Sequential Gate 1

These outputs should stabilize before the next wave:

- shared permission service contract from Workstream A
- recurrence and reminder DTO shape from Workstream B
- migration sequence up to the latest scheduling tables

### Parallel Wave 2

These can then run in parallel:

- Workstream C: calendar, move, quick reschedule, and priority decay
- Workstream D: device registration and notification delivery

Why this is safe:

- Workstream C depends on permission checks and reschedule semantics
- Workstream D can start device registration early and finish delivery integration after reminder eligibility contracts stabilize

### Final Sequential Wave

These should be integrated at the end:

- Workstream E hardening
- end-to-end permission regression
- end-to-end scheduling regression
- migration-chain verification across all new tables

## 7. Ownership Boundaries By Module and File Area

### Backend Lead / Integrator

Owns:

- `backend/src/main/resources/db/migration/`
- `backend/src/main/java/com/rocketflow/common/`
- `backend/src/main/java/com/rocketflow/config/`
- cross-module API shape changes in shared DTO classes
- final merge order across backend streams

Must not delegate concurrently:

- two different subagents editing the same Flyway migration file
- two different subagents editing the same existing integration test file

### Subagent 1. Sharing and Access

Primary ownership:

- `backend/src/main/java/com/rocketflow/sharing/`

Allowed narrow-touch areas:

- `backend/src/main/java/com/rocketflow/goals/`
- `backend/src/main/java/com/rocketflow/tasks/`
- `backend/src/main/java/com/rocketflow/accounts/`

Must not own:

- recurrence calculation
- reminder eligibility
- notification delivery

### Subagent 2. Recurrence and Reminders

Primary ownership:

- `backend/src/main/java/com/rocketflow/recurrence/`
- `backend/src/main/java/com/rocketflow/reminders/`

Allowed narrow-touch areas:

- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskController.java`

Must not own:

- share invitation flow
- calendar projection logic
- FCM delivery logic

### Subagent 3. Calendar and Priority Behavior

Primary ownership:

- `backend/src/main/java/com/rocketflow/calendar/`
- `backend/src/main/java/com/rocketflow/prioritypolicy/`

Allowed narrow-touch areas:

- `backend/src/main/java/com/rocketflow/tasks/`

Must not own:

- reminder persistence model
- device registration
- invitation lifecycle

### Subagent 4. Notifications

Primary ownership:

- `backend/src/main/java/com/rocketflow/notifications/`

Allowed narrow-touch areas:

- `backend/src/main/java/com/rocketflow/reminders/`
- `backend/src/main/java/com/rocketflow/accounts/`

Must not own:

- general task CRUD
- calendar visibility rules
- share permission rules

### Test File Guidance

To reduce collisions, each stream should prefer a new test file:

- `SharingIntegrationTest`
- `RecurrenceReminderIntegrationTest`
- `CalendarReschedulePriorityIntegrationTest`
- `NotificationDeliveryIntegrationTest`

Only the backend lead should reconcile shared test fixtures or shared MockMvc helpers if those become necessary.

## 8. Recommended Backend Subagent Count

Recommended count:

- `4` backend implementation subagents
- `1` backend lead acting as integrator and owner of migrations, shared DTO changes, and merge sequencing

Reasoning:

- fewer than `4` will overload individual streams and increase context switching inside a still-small but highly coupled codebase
- more than `4` will create avoidable collisions in `tasks`, migrations, and integration tests

## 9. Risky Coordination Surfaces

The backend lead should treat these as high-risk merge surfaces:

- `backend/src/main/resources/db/migration/`
- `backend/src/main/java/com/rocketflow/tasks/Task.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskController.java`
- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`
- permission service interfaces consumed by goals, tasks, calendar, and scheduling
- owner timezone usage across recurrence, reminders, reschedule, and notifications
- delivery idempotency boundaries between reminders and notifications
- integration test infrastructure under `backend/src/test/java/com/rocketflow/`

Specific coordination risks:

- migration numbering conflicts between streams
- duplicate permission logic reappearing in controllers or services
- DTO drift if recurrence, reminders, and sharing all touch task responses independently
- conflicting interpretations of owner-only reminder delivery for shared tasks
- notification retries causing duplicate spam if reminder eligibility and delivery logging are not aligned

## 10. Explicit Out-Of-Bounds Notes

To prevent scope creep, the remaining backend slice should explicitly exclude:

- folder sharing
- collaborator-specific reminders or collaborator-specific notification subscriptions
- a separate recurring occurrence table or full calendar engine
- message brokers, Redis, or microservice extraction
- outbound email platform work beyond the invitation persistence and API contract already needed for MVP
- web UI or Android UI implementation
- password reset, email verification, rate limiting, or other post-MVP auth hardening unless a later lead documents them as blocking release work
- advanced search, analytics, bulk editing, or notification preference expansion beyond the documented MVP settings
- multi-instance scheduler coordination beyond the current single-backend-instance MVP guardrail

## 11. Recommended Order Of Execution

1. Backend lead locks coordination rules for migrations, shared DTOs, and tests.
2. Subagent 1 starts sharing and authorization.
3. Subagent 2 starts recurrence and reminders in parallel.
4. After those contracts stabilize, Subagent 3 starts calendar, move, quick reschedule, and priority decay.
5. Subagent 4 starts device registration early, then completes notification delivery after reminder eligibility output is stable.
6. Backend lead finishes with integration, regression, and document sync.

## 12. Backend Lead Stop Rule

The backend lead should reject decomposition proposals that:

- reopen frozen MVP product decisions without a contradiction
- split `tasks` ownership across multiple active subagents without a narrow boundary
- introduce new infrastructure that the architecture blueprint explicitly deferred
- mix backend work with web or Android scope in the same implementation brief
