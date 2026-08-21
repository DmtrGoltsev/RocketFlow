# RocketFlow Domain Specification

## 1. Purpose

This document defines the business domain for the RocketFlow MVP.

Its goal is to remove ambiguity before architecture and implementation work starts in full. It describes:
- the domain glossary
- core entities
- ownership and access rules
- business invariants
- lifecycle rules
- edge cases that must be handled deliberately

This document is the domain source for:
- architecture design
- API contract design
- backend implementation
- frontend behavior
- QA scenarios

## 2. Domain Glossary

### Folder

A top-level organizational container owned by one user.

Purpose:
- group multiple goals under a broader life or work context

Examples:
- `Work`
- `Family`
- `Health`

Important note:
- a folder is not a goal
- a folder is not shareable in MVP

### Goal

A meaningful medium-term or long-term outcome that belongs to a folder.

Purpose:
- group related tasks around one outcome

Examples:
- `Promotion`
- `Grow the team`
- `Run a half marathon`

Important note:
- a goal may be shared with another user
- tasks belong to goals, not directly to folders

### Task

A concrete action item that belongs to one goal.

Purpose:
- represent work that can be planned, scheduled, completed, postponed, repeated, linked, and shared

Examples:
- `Prepare promotion plan`
- `Schedule 1:1 with manager`
- `Book dentist appointment`

### Green Task

A task that creates positive progress.

Business meaning:
- if completed, it moves the user toward success
- if not completed, life stays mostly as it is

### Red Task

A task that prevents negative outcomes.

Business meaning:
- if not completed, the result is worse than the current state
- if completed, the result is mostly preservation of the current state

### Tag

A label attached to tasks for flexible grouping across goals.

Purpose:
- allow related tasks to be found and grouped

Examples:
- `finance`
- `hiring`
- `urgent`

### Task Link

A logical connection between two tasks.

Purpose:
- show that tasks are related even if they are distinct work items

MVP scope note:
- task links are associative only
- no dependency engine is introduced in MVP

### Planned Time

The date and time when the user intends to work on the task.

### Due Time

The date and time by which the task should ideally be completed or acknowledged.

### Reminder Rule

A rule describing when the application should notify the user about a task.

### Recurrence Rule

A rule describing how a task repeats over time.

### Reschedule Event

A stored record that a task was postponed or moved to a later time.

### Legacy Task Priority Shadow

A deprecated integer retained only for old APK and V20 wire/storage compatibility. It has no current product meaning and must not affect UI, validation, business behavior, settings, or ordering.

### Share Invitation

An invitation sent by email that allows another account to gain edit access to a goal or task.

### Collaborator

A second user with edit access to a shared goal or task.

## 3. Core Entity Definitions

### User

Represents one account in the system.

Minimum business fields:
- id
- email
- display name
- timezone
- created at
- active status

Business rules:
- email must be unique
- a user owns their folders, goals, and tasks unless access is shared

### User Credential

Stores authentication data for the user.

Minimum business fields:
- user id
- password hash
- password updated at

Business rules:
- passwords are never stored in plain text

### User Settings

Stores user preferences and domain-affecting settings.

Minimum business fields:
- user id
- interface language
- notification preferences

Business rules:
- Russian is the default interface language
- English is supported from MVP launch
- legacy green/red priority-decay values may remain in storage and compatibility responses, but are disabled, hidden, and ignored on update
- user timezone is stored once at the account level and is the canonical timezone for scheduling

### Folder

Represents a top-level container for goals.

Minimum business fields:
- id
- owner user id
- name
- description optional
- display order optional
- created at
- updated at
- archived flag optional

Business rules:
- a folder belongs to exactly one owner
- a folder may contain multiple goals
- a folder cannot be shared in MVP

### Goal

Represents an outcome inside a folder.

Minimum business fields:
- id
- folder id
- owner user id
- name
- description optional
- created at
- updated at
- archived flag optional

Business rules:
- a goal belongs to exactly one folder
- a goal belongs to exactly one owner
- a goal may contain multiple tasks
- a goal may be shared

### Task

Represents a concrete unit of planned work.

Minimum business fields:
- id
- goal id
- owner user id
- title
- description optional
- type: `green` or `red`
- status
- planned time optional
- due time optional
- completed at optional
- created at
- updated at
- archived flag optional

Recommended MVP task statuses:
- `todo`
- `in_progress`
- `done`
- `cancelled`

Business rules:
- a task belongs to exactly one goal
- a task belongs to exactly one owner
- a task type must be either `green` or `red`
- a deprecated priority shadow may remain in storage and legacy responses; new tasks use compatibility value `5`
- a task may be shared
- a task may have reminders
- a task may have one recurrence rule in MVP
- a task may have many tags
- a task may have many task links

### Tag

Represents a reusable task label.

Minimum business fields:
- id
- owner user id
- name
- color optional

Business rules:
- tags are user-scoped in MVP
- the same tag may be used by many tasks

### Task Link

Represents a relationship between two tasks.

Minimum business fields:
- id
- source task id
- target task id
- link type optional

Business rules:
- task links do not create execution blocking behavior in MVP
- task links are used for grouping and navigation only

### Goal Share

Represents granted access to a goal.

Minimum business fields:
- id
- goal id
- owner user id
- collaborator user id
- created at
- status

Business rules:
- goal sharing grants collaborative edit access
- folder sharing does not exist in MVP

### Task Share

Represents granted access to a task.

Minimum business fields:
- id
- task id
- owner user id
- collaborator user id
- created at
- status

Business rules:
- task sharing grants collaborative edit access
- task sharing may exist even when the goal is not shared

### Share Invitation

Represents a pending or resolved email-based invitation.

Minimum business fields:
- id
- target email
- inviter user id
- target type: `goal` or `task`
- target id
- status
- created at
- expires at optional

Recommended statuses:
- `pending`
- `accepted`
- `declined`
- `revoked`
- `expired`

### Recurrence Rule

Represents how a task repeats.

Minimum business fields:
- id
- task id
- recurrence mode
- interval value
- unit
- days of week optional
- day of month optional
- start at
- end at optional
- active flag

Business rules:
- a task has at most one recurrence rule in MVP
- recurrence must be flexible but understandable
- recurrence rules must avoid unsupported complexity

### Reminder Rule

Represents when reminders should fire for a task.

Minimum business fields:
- id
- task id
- offset or absolute reminder mode
- reminder timing configuration
- active flag

Business rules:
- a task may have multiple reminder rules
- reminders must work with planned time and due time where relevant

### Reschedule Event

Represents a recorded postponement of a task.

Minimum business fields:
- id
- task id
- previous planned time
- new planned time
- reschedule reason optional
- rescheduled by user id
- created at

Business rules:
- every quick postpone creates a reschedule event
- manual date/time movement that postpones a task should also create a reschedule event if it moves the task later

### Legacy Priority Decay Policy Shadow

Deprecated green/red policy columns and DTO objects are retained only through the old APK/V20 rollback compatibility window.

Business rules:
- policy controls are hidden from product settings
- backend update ignores supplied policy objects and does not rewrite stored historical threshold/amount values
- compatibility responses report policies disabled while retaining historical threshold/amount values
- no reschedule operation evaluates or applies priority decay

### Device Registration

Represents a registered Android device capable of receiving notifications.

Minimum business fields:
- id
- user id
- push token
- device name optional
- platform
- created at
- updated at
- active flag

### Notification Delivery

Represents a reminder delivery attempt or result.

Minimum business fields:
- id
- task id
- reminder rule id
- device registration id optional
- scheduled at
- attempted at optional
- status
- provider response optional

## 4. Ownership and Access Rules

### Ownership

- every folder has exactly one owner
- every goal has exactly one owner
- every task has exactly one owner
- sharing does not transfer ownership

### Collaboration

- a collaborator may edit a shared goal or task
- a collaborator is not allowed to reassign ownership
- a collaborator may see and edit only what is explicitly shared
- reminders remain owner-scoped in MVP unless a later version introduces collaborator-specific reminder subscriptions

### Sharing Scope

- folders are not shareable in MVP
- goals are shareable
- tasks are shareable

### Access Resolution Rules

Access is granted when one of the following is true:
- the user is the owner
- the user is an accepted collaborator on the goal
- the user is an accepted collaborator on the task

MVP simplification:
- if a goal is shared, all tasks under that goal become visible and editable to the collaborator
- if a task is shared directly, only that task is visible and editable through the task share
- goal and task reminder deliveries still target the owner only in MVP
- if a collaborator postpones a shared task, the actor is recorded and the task's legacy priority shadow remains unchanged

### Sharing Constraints

- the same user should not receive duplicate active access records for the same object
- invitations should not create duplicate effective permissions
- revoked or expired invitations must not grant access

## 5. Lifecycle Rules

### Folder Lifecycle

Allowed operations:
- create
- edit
- archive
- delete if empty, or soft-delete strategy if chosen by architecture

Business expectation:
- deleting a folder is a soft-delete operation in MVP
- physical deletion is deferred and should not be part of normal user-facing flows

### Goal Lifecycle

Allowed operations:
- create
- edit
- archive
- share
- unshare
- delete

Business expectation:
- deleting a goal is a soft-delete operation in MVP
- child task visibility and editability must follow the archived state rules

### Task Lifecycle

Allowed operations:
- create
- edit
- complete
- cancel
- archive
- reschedule
- repeat
- share
- unshare
- delete

Important rule:
- completion status and recurrence behavior must be defined so users are not surprised
- deleting a task is a soft-delete operation in MVP

Recommended MVP behavior:
- a recurring task keeps its recurrence definition
- a recurring task represents the next active occurrence in MVP
- completing it advances its scheduling fields to the next occurrence on the same task record
- recurring behavior does not create a separate occurrence table in MVP

### Share Invitation Lifecycle

Allowed operations:
- create
- accept
- decline
- revoke
- expire

Business rules:
- only accepted invitations produce active collaboration access
- invitations are tied to the target email
- invitation acceptance requires a matching account identity

### Reminder Lifecycle

Allowed operations:
- create
- update
- deactivate
- fire
- log delivery outcome

Business rules:
- reminders should not keep firing after task completion unless explicitly supported

### Recurrence Lifecycle

Allowed operations:
- create
- update
- pause
- resume
- stop

Business rules:
- recurrence must remain traceable to the originating task definition

### Reschedule Lifecycle

Allowed operations:
- create event

Business rules:
- moving a task later records an audit event without changing the legacy priority shadow
- historical priority-before/after and decay-applied values remain retained

## 6. Scheduling Rules

### Planned Time and Due Time

A task may have:
- only planned time
- only due time
- both planned time and due time
- neither, if the product later allows backlog-style tasks

MVP recommendation:
- allow planned time to be optional
- allow due time to be optional
- do not require both

### Calendar Behavior

The MVP calendar is simple.

Expected behaviors:
- show tasks in day, week, or month projections
- allow moving a task to another date/time
- allow editing and deletion

### Quick Reschedule Presets

Supported MVP presets:
- `+30 minutes`
- `+1 hour`
- `+3 hours`
- `+24 hours`

Behavior:
- the action applies to the planned time
- if planned time is missing, UI and API behavior must be defined clearly

Recommended MVP rule:
- quick reschedule requires an existing planned time
- if no planned time exists, the user must set one first

## 7. Task Priority Retirement Rules

### Product Rule

- task priority is not a user-facing or business domain concept
- task create/edit/detail, settings, validation, sorting, sharing, calendar, and reschedule behavior must not consult it
- technical FCM/Android notification priority remains a separate transport concern

### Compatibility Rule

- `LEGACY_TASK_PRIORITY=5` is the default opaque shadow for new tasks and missing client fields
- old request fields are accepted and ignored
- updates preserve an existing historical task shadow; clones use `5`; move-to-goal preserves the moved task's shadow
- legacy fields may remain in responses for old clients
- removing the fields or historical values requires explicit end of old APK and V20 rollback support

### Historical Data Rule

- historical task priority, reschedule priority-before/after, decay-applied, and policy values remain stored
- V21 changes defaults only; it does not rewrite/drop rows, columns, constraints, or indexes
- reschedule events remain auditable, but current behavior records no priority change and reports no decay

### Ordering Rule

- task lists and shared task lists use `createdAt ASC`, then `id ASC`
- calendar ties use `plannedTime ASC`, then `createdAt ASC`, then `id ASC`
- web plan projection uses `dueTime ASC` with missing values last, then `createdAt ASC`, then `id ASC`
- Android local Planner uses `plannedTime ASC` with missing values last, then `createdAt ASC`, then `id ASC`
- no ordering may use the compatibility shadow

## 8. Localization Rules

### Language Model

- Russian is the primary product language
- English is the secondary language

### Source of Truth

- Russian localization keys and values are primary
- English must remain synchronized to the same key set

### Operating Rule

Whenever new UI text is added:
- Russian file must be updated first
- English file must be updated in the same change set or immediately after

### Settings Rule

- language switching must exist in user settings
- the saved language preference belongs to user settings
- timezone belongs to the user account and is the canonical zone for recurrence and reminder evaluation

## 9. Domain Invariants

The following conditions must always hold:

- folder ownership is singular
- goal ownership is singular
- task ownership is singular
- folder sharing does not exist in MVP
- a goal belongs to one folder
- a task belongs to one goal
- task type is always `green` or `red`
- task priority has no product/business effect; compatibility shadow `5` remains only during old APK/V20 rollback support
- legacy green/red priority-decay values remain disabled and hidden without historical rewrite
- every active share comes from accepted access, not just a pending invitation
- every quick postpone creates a reschedule record
- localization key sets for Russian and English must match

## 10. Edge Cases That Must Be Designed Carefully

- what happens when a shared goal is unshared after the collaborator edited tasks inside it
- what happens when a task is directly shared and later moved to another goal
- what happens when a recurring task is completed early
- what happens when a recurring task is overdue and the next recurrence should be generated
- what happens when reminders exist but neither planned time nor due time exists
- what happens when a quick reschedule is requested for a task without planned time
- what happens when a user changes timezone after many future reminders already exist
- what happens when a collaborator loses access while using the UI
- what happens when a stale update races with a collaborator's newer update

## 11. Recommended MVP Decisions for Open Edge Cases

To keep the MVP simple and predictable, the following recommendations are proposed:

- direct task sharing stays valid even if the parent goal is not shared
- quick reschedule is allowed only when planned time exists
- reminder rules require either planned time or due time
- recurrence is based on explicit task scheduling data, not inferred behavior
- changing timezone should affect future reminder scheduling, not rewrite historical events
- removing access should take effect immediately on the next authorized request
- shared-task reminder delivery remains owner-only in MVP
- optimistic locking should reject stale updates instead of silently overwriting them

## 12. Calendar and Weekly Focus Addendum

### Calendar Projection

- Calendar day boundaries are evaluated in the requesting user's IANA timezone.
- A task contributes a `planned` marker for its planned work date and a `deadline` marker for its due date; both markers may exist on one day.
- UI semantics are green for `planned` and red for `deadline`.
- Recurring occurrences are expanded by the server in timezone-aware date ranges. Clients do not independently invent recurrence instances.
- Owned tasks and accessible shared descendants are visible. Loss of access removes future visibility on the next authorized read.

### Weekly Focus

- A user has at most one active Focus period.
- Periods follow ISO weeks in the user's timezone. The period stores timezone and task snapshots so history remains interpretable after later changes.
- Progress is weighted by task effort. Missing or zero effort has effective weight `1`; only `done` contributes completed weight.
- Completed items remain in the current period until week end. Incomplete items require explicit rollover into the new week.
- Completed periods remain available as history.
- A deleted task is removed from active Focus. An archived task becomes history-only. An accessible shared task may participate while access remains valid and is removed from active Focus when access is lost.
- Focus mutations use optimistic versions and idempotency keys so offline clients can safely rebase and retry.

### Focus Notification Policy

- Cadence presets are off, 30 minutes, 1 hour, 2 hours, or 4 hours, with an optional paired quiet-hours interval.
- The server owns cadence and delivers regular reminders while an active period is non-empty and unfinished; reminders are not limited to overdue tasks.
- Android receives Focus pushes but does not create local repeating Focus alarms.

## 13. Next Document

The next document after this one should be:
- `docs/04-architecture-blueprint.md`

That document should translate these domain rules into:
- module boundaries
- data model direction
- API boundaries
- integration flows
- technical tradeoffs
