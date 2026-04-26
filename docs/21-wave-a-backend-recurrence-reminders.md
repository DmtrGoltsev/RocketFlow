# Wave A Backend: Recurrence And Reminders

## Implemented

- Added `V5__recurrence_reminders.sql` with `task_recurrence_rules` and `task_reminder_rules`.
- Added recurrence persistence and validation under `backend/src/main/java/com/rocketflow/recurrence/`.
- Added reminder persistence and eligibility validation under `backend/src/main/java/com/rocketflow/reminders/`.
- Expanded task DTOs from placeholder fields to typed recurrence and reminder payloads.
- Added:
  - `PUT /api/tasks/{taskId}/recurrence`
  - `PUT /api/tasks/{taskId}/reminders`
- Added focused integration coverage in `backend/src/test/java/com/rocketflow/RecurrenceReminderIntegrationTest.java`.

## Contract Decisions Frozen By This Slice

- `PUT /api/tasks/{taskId}/reminders` is implemented as full replacement of the rule set.
- Sending `"reminders": []` clears all reminder rules for the task.
- Supported recurrence modes in this slice:
  - `daily`
  - `weekly`
  - `monthly`
- Supported reminder modes in this slice:
  - `before_planned_time`
  - `before_due_time`

## Validation Rules Implemented

- Recurrence requires the task to already have `plannedTime` or `dueTime`.
- Recurrence `startAt` must match the task's `plannedTime` or `dueTime`.
- Weekly recurrence requires at least one weekday.
- Weekly and monthly recurrence validation use the owner's canonical timezone from `users.timezone`.
- `before_planned_time` reminders require `plannedTime`.
- `before_due_time` reminders require `dueTime`.
- Duplicate reminder rules with the same mode and offset are rejected.

## Notes For Follow-On Waves

- No notification delivery or reminder polling was added here.
- No quick reschedule or priority decay behavior was added here.
- `RecurrenceCalculationService` and `ReminderEligibilityService` now provide the domain foundation needed by later scheduling and notification work.
