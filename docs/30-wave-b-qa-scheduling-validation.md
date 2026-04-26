# Wave B QA Scheduling Validation

## 1. Purpose

This document turns the Wave B QA brief into an executable validation package for:

- backend slice `B1`: calendar, move, quick reschedule, reschedule history, and priority decay
- backend slice `B2`: device registration and notification delivery logging

Source alignment:

- `docs/17-qa-lead-decomposition.md`
- `docs/19-cross-lead-orchestration-plan.md`
- supporting frozen rules from `docs/03-domain-specification.md`
- supporting frozen contracts from `docs/05-api-contracts.md`
- backend workstream split from `docs/14-backend-lead-decomposition.md`

Frozen execution rules:

- keep MVP scope frozen
- do not reinterpret documented behavior to make a slice easier to pass
- validate each backend slice as it lands, then rerun the combined Wave B backend suite
- do not require web-calendar UI, Android UI, or real FCM delivery for Wave B backend acceptance
- do not declare Wave B ready if implementation silently changes contracts or owner-only reminder semantics

## 2. Wave B Preconditions and Scope

Working directory for commands:

- `C:\Users\hp\Documents\Codex\RocketFlow\backend`

Wave A prerequisites that must already be green before this pack is used as a merge gate:

- sharing contract is stable enough for clients
- recurrence and reminder DTO shapes are stable enough for clients
- `SharingIntegrationTest` exists and passes
- `RecurrenceReminderIntegrationTest` exists and passes

Wave B backend surfaces under this package:

- `GET /api/calendar`
- `POST /api/tasks/{taskId}/move`
- `POST /api/tasks/{taskId}/reschedule`
- reschedule event persistence and auditability
- priority decay evaluation using owner settings and task type
- `POST /api/devices`
- `DELETE /api/devices/{deviceId}`
- reminder-to-delivery pipeline logging

Wave B explicit non-goals for QA pass:

- no new product scope beyond documented presets, payloads, and owner-only semantics
- no requirement for collaborator-targeted reminders
- no requirement for multi-instance scheduler behavior beyond duplicate protection under the documented single-instance MVP rule
- no requirement for Android open-from-notification validation yet

## 3. Validation Matrix

| Area | Primary targets | Positive checks | Negative and edge checks | Exit evidence |
| --- | --- | --- | --- | --- |
| Calendar move | `POST /api/tasks/{taskId}/move`, `GET /api/calendar` | Later move updates `plannedTime`; earlier move updates `plannedTime`; moved task remains visible in the correct calendar range | moving without access is rejected; invalid timestamp is rejected; move without effective change does not create false postpone history | task read and calendar projection agree on final `plannedTime` |
| Quick reschedule | `POST /api/tasks/{taskId}/reschedule` | supported presets `30m`, `1h`, `3h`, `24h` succeed; alternative minutes shape only passes if implementation keeps the documented contract | missing `plannedTime` is rejected; unsupported preset is rejected; unauthorized caller is rejected | response contains updated task data and a reschedule event when postponement occurs |
| Reschedule history | move and reschedule flows, backing persistence for `task_reschedule_events` | every quick reschedule creates one reschedule event; manual move later also creates a reschedule event; actor identity is retained | moving earlier does not create a postponement event; repeated writes do not duplicate one user action into multiple history rows | audit trail can explain `previousPlannedTime`, `newPlannedTime`, actor, and creation time |
| Priority decay | move and reschedule flows plus owner settings | decay applies only when enabled and threshold conditions are met; green and red policies stay independent; priority never drops below `1` | earlier move does not decay; disabled policy does not decay; collaborator action does not use collaborator policy | response and stored task priority match documented decay policy outcome |
| Device registration | `POST /api/devices`, `DELETE /api/devices/{deviceId}` | Android device registration succeeds with stable contract; unregister removes active registration predictably | duplicate token handling is explicit and idempotent-enough; another user's device id cannot be deleted; invalid payload is rejected | registration rows are stable and owner-scoped |
| Notification logging | reminder eligibility to delivery logging pipeline | eligible owner reminders create delivery attempts; result state is logged; minimal payload includes `type=task_reminder` and `taskId` | ineligible reminders do not produce deliveries; duplicate-delivery protection prevents repeated normal single-instance sends; shared-task reminder does not target collaborator | delivery log records are queryable and correlate to the triggering task/reminder |

## 4. Immediate Validation Checklist for B1 Scheduling

Expected new primary test target:

- `backend/src/test/java/com/rocketflow/CalendarReschedulePriorityIntegrationTest.java`

Commands QA expects to run when B1 lands:

- `mvn -Dtest=FlywayMigrationTest,CalendarReschedulePriorityIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,CalendarReschedulePriorityIntegrationTest test`
- `mvn test`

Immediate checklist:

- [ ] New scheduling migrations, including `task_reschedule_events`, apply cleanly from `V1` to the newest version.
- [ ] `GET /api/calendar` returns owner-visible and collaborator-visible tasks correctly for accepted shares only.
- [ ] Calendar projection excludes unrelated tasks for collaborators and never expands folder ownership semantics.
- [ ] `POST /api/tasks/{taskId}/move` accepts a valid later `plannedTime` and returns a stable task shape.
- [ ] `POST /api/tasks/{taskId}/move` accepts an earlier `plannedTime` without creating a false postponement event.
- [ ] A manual move later records a reschedule event with correct `previousPlannedTime`, `newPlannedTime`, `createdAt`, and actor identity.
- [ ] `POST /api/tasks/{taskId}/reschedule` supports `30m`, `1h`, `3h`, and `24h`.
- [ ] Quick reschedule without an existing `plannedTime` is rejected.
- [ ] Unsupported reschedule presets are rejected.
- [ ] If the implementation supports the alternative `minutes` request shape, it behaves consistently with the documented preset path; if not, the rejection is explicit and documented.
- [ ] Every quick reschedule creates exactly one reschedule event.
- [ ] Priority decay is evaluated only when the task is postponed later, not when it is moved earlier.
- [ ] Priority decay honors the owner's task-type policy and never uses collaborator-specific policy.
- [ ] Green and red task decay policies remain independent.
- [ ] Priority never drops below `1`.
- [ ] Scheduling writes continue to honor optimistic locking and reject stale updates with `409 Conflict`.
- [ ] Task detail reads and calendar projection reads agree on the final task `plannedTime` and `priority`.
- [ ] Scheduling calculations continue to use the owner's canonical timezone.

B1 blockers:

- any scheduling API drift on a frozen endpoint
- any missing or duplicated reschedule history for a single user action
- any collaborator visibility leak in calendar projection
- any decay decision that ignores the owner's policy or task type
- any stale-write overwrite on scheduling paths

## 5. Immediate Validation Checklist for B2 Notifications

Expected new primary test target:

- `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`

Commands QA expects to run when B2 lands:

- `mvn -Dtest=FlywayMigrationTest,NotificationDeliveryIntegrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest,RecurrenceReminderIntegrationTest,NotificationDeliveryIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,NotificationDeliveryIntegrationTest test`
- `mvn test`

Immediate checklist:

- [ ] New notification migrations, including `device_registrations` and `notification_deliveries`, apply cleanly from `V1` to the newest version.
- [ ] `POST /api/devices` creates an owner-scoped Android device registration with a stable contract.
- [ ] `DELETE /api/devices/{deviceId}` removes the caller's registration predictably and returns the documented success semantics.
- [ ] Duplicate device token registration is handled predictably without creating uncontrolled duplicates.
- [ ] One user cannot delete or mutate another user's device registration.
- [ ] Eligible reminder evaluation creates delivery attempts for owner reminders.
- [ ] Delivery attempts persist enough state to distinguish success, failure, and repeated-attempt behavior if retries exist.
- [ ] Logged deliveries retain task correlation and payload minimum contract stability.
- [ ] Shared-task reminder delivery still targets the owner only in MVP.
- [ ] Collaborators do not receive notification deliveries for shared tasks.
- [ ] Reminder rules that are ineligible because of missing anchors do not create delivery attempts.
- [ ] Timezone changes affect future reminder delivery scheduling only and do not rewrite historical delivery logs.
- [ ] Normal single-instance execution does not emit duplicate deliveries for one eligible reminder occurrence.

B2 blockers:

- any drift in the device registration contract
- any collaborator-targeted reminder delivery in MVP
- any missing delivery logging for attempted sends
- any uncontrolled duplicate registrations or duplicate deliveries
- any notification behavior that depends on unfinished Android UI work to verify backend correctness

## 6. Owner-Only Reminder Semantics Checklist for Shared Tasks

This checklist is mandatory for both B1 and B2 because shared-task postponement and reminder delivery are coupled.

- [ ] A shared goal or shared task can be visible to a collaborator without granting collaborator reminder ownership.
- [ ] A collaborator may postpone a shared task if the share grants edit access, but the owner's decay policy still applies.
- [ ] The reschedule event records the collaborator as the actor when the collaborator performs the postponement.
- [ ] Reminder eligibility is evaluated from the task owner's canonical timezone and owner-owned reminder rules.
- [ ] Reminder delivery targets the owner only, even when the collaborator performed the reschedule.
- [ ] No collaborator-specific reminder settings, device targeting, or notification fan-out is introduced in Wave B.
- [ ] Shared-task notification logging shows owner-targeted delivery behavior only.
- [ ] Any branch that introduces collaborator-targeted reminders, collaborator-specific decay policy, or folder-level sharing semantics automatically fails QA for MVP drift.

## 7. Timezone and Duplicate-Delivery Checks

Timezone checks:

- [ ] All new scheduling and notification timestamps are ISO 8601 with timezone awareness.
- [ ] Calendar projection and task reads remain stable when the owner timezone is an IANA zone such as `Europe/Moscow`.
- [ ] Recurrence, reminder, reschedule, and notification calculations use the owner's canonical timezone consistently.
- [ ] A user timezone change affects future recurrence/reminder/delivery evaluation only.
- [ ] Historical reschedule events and notification delivery logs remain unchanged after timezone updates.
- [ ] DST-sensitive cases do not shift future reminder eligibility in a way that contradicts owner-timezone rules.

Duplicate-delivery checks:

- [ ] One eligible reminder occurrence creates at most one normal delivery attempt in the documented single-instance MVP path.
- [ ] Re-reading the same reminder candidate does not create duplicate delivery logs under normal execution.
- [ ] Re-registering the same device token does not multiply delivery fan-out for a single reminder.
- [ ] Retried delivery behavior, if implemented, is distinguishable from accidental duplicate sends in the log model.
- [ ] QA does not require multi-node deduplication in Wave B, but any duplicate-delivery defect under single-instance execution is a blocker.

## 8. Exact Commands and Test Targets QA Expects

Current prerequisite targets already in the repo:

- `mvn -Dtest=FlywayMigrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest test`
- `mvn -Dtest=SharingIntegrationTest test`
- `mvn -Dtest=RecurrenceReminderIntegrationTest test`
- `mvn -Dtest=RocketFlowApplicationTests test`
- `mvn test`

Expected Wave B landing targets:

- `mvn -Dtest=FlywayMigrationTest,SchedulingIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,SchedulingIntegrationTest test`
- `mvn -Dtest=FlywayMigrationTest,NotificationIntegrationTest test`
- `mvn -Dtest=AuthSettingsIntegrationTest,RecurrenceReminderIntegrationTest,NotificationIntegrationTest test`
- `mvn -Dtest=PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,NotificationIntegrationTest test`
- `mvn -Dtest=FlywayMigrationTest,AuthSettingsIntegrationTest,PlanningCrudIntegrationTest,SharingIntegrationTest,RecurrenceReminderIntegrationTest,SchedulingIntegrationTest,NotificationIntegrationTest,RocketFlowApplicationTests test`
- `mvn test`

Expected dedicated test files as slices land:

- `backend/src/test/java/com/rocketflow/SchedulingIntegrationTest.java`
- `backend/src/test/java/com/rocketflow/NotificationIntegrationTest.java`

QA enforcement rule:

- if B1 lands without `SchedulingIntegrationTest`, QA marks the slice incomplete
- if B2 lands without `NotificationIntegrationTest`, QA marks the slice incomplete
- if either slice adds migrations without rerunnable Flyway coverage from empty DB, QA marks the slice incomplete
- if either slice changes a frozen contract shape without documentation sync, QA marks the slice incomplete

## 9. Integration-Ready Gate Rules for Wave B Backend Slices

### B1 Slice Gate

Must be true:

- scheduling migrations apply cleanly in focused and full test runs
- calendar projection respects accepted-share visibility only
- move and quick reschedule endpoints honor documented validation and response shapes
- postponement history is auditably correct for manual later moves and quick reschedule
- priority decay applies only under documented owner-policy conditions
- timezone handling is stable for future-facing calculations
- no stale-write overwrite exists on scheduling paths

Blockers:

- any missing reschedule event where one is required
- any extra reschedule event where one is not required
- any calendar permission leak
- any decay outcome that cannot be explained from stored policy and history

### B2 Slice Gate

Must be true:

- device registration migrations apply cleanly in focused and full test runs
- device registration and unregister flows are owner-scoped and stable
- eligible reminders produce delivery log records predictably
- shared-task reminder deliveries remain owner-only
- duplicate-device and duplicate-delivery behavior is controlled enough for single-instance MVP execution
- notification payload minimum contract remains stable for future Android consumption

Blockers:

- any delivery attempt with no durable log record
- any collaborator-targeted reminder delivery
- any duplicate-delivery defect under normal single-instance execution
- any device ownership or deletion leak

### Combined Wave B Backend Gate

Wave B backend is integration-ready only when all of the following are true:

- B1 slice gate passes
- B2 slice gate passes
- calendar, move, quick reschedule, and priority decay APIs are stable enough for web integration
- device registration contract exists and is stable enough for Android integration
- notification payload minimum contract is stable enough for Android integration
- no open high-severity scheduling, permission, or duplicate-delivery defect remains
- no frozen-contract drift is left undocumented

Wave B backend is not integration-ready if any of the following is still true:

- QA must infer undocumented scheduling semantics from implementation details
- owner-only reminder semantics are ambiguous in code or logs
- delivery logging exists but cannot prove whether duplicates occurred
- slice behavior depends on web or Android UI completion to validate backend correctness
