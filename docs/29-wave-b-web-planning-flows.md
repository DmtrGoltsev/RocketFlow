# Wave B Web Planning Flows

## Scope

Implemented the Wave B planning workspace in the web client within the existing protected shell:

- folders list, create, edit, archive
- goals list, detail, create, edit, archive
- tasks list, detail, create, edit, delete
- optimistic conflict recovery for stale `version` updates
- RU-first copy inside the planning feature without expanding MVP into calendar or sharing

## Frontend Structure

Added a dedicated planning feature module under `web/src/features/planning/`:

- `planning-api.ts`
  - authorized CRUD requests for folders, goals, and tasks
  - shared parsing for the backend error envelope
- `planning-copy.ts`
  - local RU/EN planning copy bound to the existing locale provider
  - keeps planning copy colocated without broad edits to shared i18n files
- `planning-errors.ts`
  - maps API error codes and field details into route-friendly UI state
- `planning-utils.ts`
  - date formatting and `datetime-local` conversion helpers
- `components/PlanningWorkspace.tsx`
  - reusable split layout, selectable records, meta list, and inline notices
- `routes/FoldersRoute.tsx`
- `routes/GoalsRoute.tsx`
- `routes/TasksRoute.tsx`

## UX Notes

### Folders

- `/app/folders` now renders a two-pane planning surface
- left pane:
  - folder list
  - create action
- right pane:
  - folder detail card
  - inline create/edit form
  - archive action
  - handoff button into goals for the selected folder

### Goals

- `/app/goals` reads `folder` and `goal` from query params
- supports:
  - folder switching
  - goal list loading per folder
  - goal detail fetch by id
  - create/edit/archive actions
  - handoff button into tasks for the selected goal

### Tasks

- `/app/tasks` reads `folder`, `goal`, and `task` from query params
- supports:
  - folder and goal switching
  - task list loading per goal
  - task detail fetch by id
  - create/edit/delete actions
  - type, status, priority, planned time, and due time editing
- recurrence and reminders are intentionally kept read-only with explicit “later wave” messaging

## Conflict Handling

For folder, goal, and task updates:

- update requests send the current `version`
- `409 Conflict` is caught centrally through the planning API error type
- the UI refetches the fresh server copy and shows a conflict notice in the editor
- the user stays on the same entity instead of being dropped back to an empty state

## Route Wiring

Replaced the planning placeholders in `web/src/app/router.tsx` with:

- `FoldersRoute`
- `GoalsRoute`
- `TasksRoute`

No calendar, sharing, or shell redesign work was added in this slice.

## Styling

Added a small planning-specific extension in `web/src/styles/components.css`:

- split workspace grid
- record list buttons
- metadata rows
- inline notices
- form grid
- disabled button styling

This stays inside the existing retro shell language and does not introduce a new design system.
