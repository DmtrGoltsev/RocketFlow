# Wave C Web: Calendar, Sharing, and Settings

## Scope

This wave opens the next protected web surfaces after planning:

- calendar read view using the existing backend projection API
- move and quick-reschedule actions from the calendar surface
- sharing workspace for invitations and shared-resource discovery
- settings screen for language, notifications, and priority decay policies

The web client remains the primary planning and management surface for MVP.

## Delivery Notes

### Calendar

- replace the `/app/calendar` placeholder with a real route
- load `GET /api/calendar`
- support simple range presets for short-horizon planning views
- allow task move through `POST /api/tasks/{taskId}/move`
- allow quick postpone through `POST /api/tasks/{taskId}/reschedule`

### Sharing

- replace the `/app/sharing` placeholder with a real route
- support goal and task invitation creation
- show invitation list with accept, decline, and revoke actions
- show shared goals and tasks from `GET /api/shares/resources`
- keep shared-resource presentation separate from folder ownership semantics
- treat persisted `folderId` as canonical and avoid depending on a synthetic `virtual-shared` value

### Settings

- replace the `/app/settings` placeholder with a real route
- load and update `GET/PATCH /api/me/settings`
- keep Russian primary while allowing English parity
- synchronize the saved language with the active web locale

### Localization Operating Rule

- shared shell copy remains anchored in `web/src/i18n/**`
- feature-local copy is acceptable for bounded feature text when RU and EN are added together
- Wave C must not weaken the RU-primary / EN-sync rule just because some text lives near the feature

## UX Guardrails

- keep the existing retro shell and panel language
- reuse loading, error, empty, and conflict states already established in planning
- do not add recurrence/reminder editing in this slice
- do not introduce folder sharing
- do not move Android-only concerns into the web UI

## Residual Scope After This Slice

This Wave C slice does not close all remaining web scheduling authoring scope.

Still tracked after this slice:

- recurrence editor UI
- reminder editor UI

Those follow-up surfaces remain part of the web MVP path and are explicitly preserved in:

- `docs/39-wave-c1-web-scheduling-authoring.md`

## Contract Assumptions Used

- canonical task statuses remain `todo`, `in_progress`, `done`, `cancelled`
- `/api/calendar` returns already-visible tasks only
- move and quick-reschedule responses include updated priority after backend policy evaluation
- `/api/shares/resources` remains discovery-oriented, not ownership-oriented
- settings updates remain optimistic through `version`

## Done Criteria For This Slice

- `/app/calendar`, `/app/sharing`, and `/app/settings` are no longer placeholders
- the routes are wired to the current backend APIs
- RU/EN copy exists for new user-facing texts
- web production build stays green
- the residual recurrence/reminder authoring scope remains explicitly tracked instead of disappearing from planning
