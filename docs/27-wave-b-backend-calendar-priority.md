# Wave B Backend: Calendar, Reschedule, and Priority

## Scope Delivered

This backend slice implements:

- `GET /api/calendar`
- `POST /api/tasks/{taskId}/move`
- `POST /api/tasks/{taskId}/reschedule`
- `task_reschedule_events` persistence
- owner-policy-based priority decay for `green` and `red` tasks
- collaborator postponement audit with actor identity preserved
- focused integration coverage for calendar visibility and scheduling behavior

## Persistence

Added Flyway migration:

- `backend/src/main/resources/db/migration/V6__calendar_reschedule_priority.sql`

It creates `task_reschedule_events` with:

- task reference
- rescheduled-by user reference
- previous and new planned times
- optional reason
- priority before and after
- whether decay was applied
- creation timestamp

This supports the MVP audit requirement to explain when a postponement happened, who did it, what changed, and whether priority changed.

## Calendar API

`GET /api/calendar?from=...&to=...` now returns planned tasks visible to the caller within the requested time window.

Visibility rules implemented:

- owners see their own planned, non-archived tasks in range
- collaborators see tasks from accepted goal shares
- collaborators also see directly shared tasks even when the parent goal is not shared
- duplicate visibility paths are de-duplicated before response assembly

Sorting is deterministic:

- `plannedTime` ascending
- `priority` descending
- `createdAt` ascending

## Move and Quick Reschedule

### `POST /api/tasks/{taskId}/move`

- updates `plannedTime`
- records a reschedule event only when the move postpones the task to a later instant
- evaluates priority decay only for postponements

### `POST /api/tasks/{taskId}/reschedule`

- supports presets `30m`, `1h`, `3h`, and `24h`
- also accepts equivalent `minutes` values for the same preset set
- requires an existing `plannedTime`
- always records a reschedule event because the operation is defined as a postpone

## Priority Decay

Implemented under `prioritypolicy` using owner settings and task type:

- `green` tasks use the owner’s green policy
- `red` tasks use the owner’s red policy
- collaborator-triggered postponements still use the owner’s policy
- priority never drops below `1`

MVP accumulation rule used here:

- positive postponement durations are summed across stored reschedule events for the task
- decay applies when cumulative postponed duration crosses threshold boundaries
- thresholds map to:
  - `day` = 24 hours
  - `week` = 7 days
  - `month` = 30 days

This keeps the behavior auditable without introducing extra hidden counters.

## Test Coverage

Added:

- `backend/src/test/java/com/rocketflow/CalendarReschedulePriorityIntegrationTest.java`

Covered scenarios:

- calendar projection includes owner-visible and collaborator-visible tasks correctly
- moving later records audit history
- repeated postponement crosses the threshold and decays priority
- quick reschedule rejects tasks without `plannedTime`
- collaborator postpone records collaborator identity while applying owner policy
