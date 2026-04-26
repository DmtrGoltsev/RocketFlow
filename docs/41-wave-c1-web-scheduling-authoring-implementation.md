# Wave C.1 Web Scheduling Authoring Implementation

## Scope

This document records the completed implementation of the residual web scheduling authoring slice preserved in:

- `docs/39-wave-c1-web-scheduling-authoring.md`

The delivered surface stays inside the existing planning shell and extends task create/edit flows rather than introducing a new route family.

## Delivered

- task create/edit now supports recurrence authoring in the existing task dialog
- task create/edit now supports reminder list authoring in the same dialog
- web planning API now calls:
  - `PUT /api/tasks/{taskId}/recurrence`
  - `PUT /api/tasks/{taskId}/reminders`
- task detail cards now render actual recurrence/reminder summaries instead of later-wave placeholders
- RU and EN copy was updated together for the new controls, notices, and validation states

## Implementation Notes

### UI Integration

The safest path from the planning review was used:

- no new route was added
- no separate scheduling shell was introduced
- recurrence/reminder editing lives inside `TasksRoute`
- the existing task draft pipeline remains the source of truth for create, edit, and conflict recovery

### API Behavior

Task base fields are still saved through task CRUD first, then scheduling is synchronized through dedicated scheduling endpoints.

This keeps the web client aligned with the backend contract where recurrence and reminders are not embedded in standard task create/update writes.

### Validation And Guardrails

The web client now adds guardrails for the most important backend rules:

- recurrence requires `plannedTime` or `dueTime`
- recurrence interval must be `>= 1`
- weekly recurrence must include the anchor weekday
- recurrence end time must be later than the anchor time
- reminder offsets must be `>= 1`
- duplicate reminder `mode + offset` pairs are blocked
- reminder mode must match available `plannedTime` / `dueTime`

These checks are intentionally client-side complements, not replacements for backend validation.

## Verification

Verified in this wave:

- `web npm run build`

## Outcome

The residual web scheduling authoring slice tracked in `docs/39-wave-c1-web-scheduling-authoring.md` is now implemented for the current MVP web shell.

This means the next recommended plan step narrows back to Android companion continuation:

- push registration
- notification-open / deep-link flow
- notification-driven task entry path
