# RocketFlow Architecture Blueprint

## 1. Purpose

This document translates the RocketFlow MVP domain rules into a practical technical architecture.

Its purpose is to define:
- architectural style
- module boundaries
- deployment shape
- data model direction
- API boundaries
- integration flows
- technical decisions and tradeoffs
- implementation guidance for backend, web, Android, QA, and DevOps

This document is not a full implementation spec. It is the stable architectural frame for MVP delivery.

## 2. Architectural Goals

The architecture must optimize for:
- MVP delivery speed
- simplicity
- maintainability
- traceable business rules
- safe extensibility
- low operational overhead

The architecture must avoid:
- premature microservices
- speculative infrastructure complexity
- hidden cross-module coupling
- magical scheduling behavior that is hard to debug

## 3. Architectural Style

RocketFlow should be built as a modular monolith.

Reasoning:
- the MVP domain is rich enough to need strong module boundaries
- the team does not benefit from distributed systems complexity at this stage
- one deployable backend is simpler to run, debug, test, and evolve
- the future system can still be split later if real scaling pressure appears

Chosen style:
- one backend application
- one relational database
- one background scheduling process inside the backend runtime
- one web client
- one Android companion client

## 4. Technology Direction

### Backend

- `Java`
- `Spring Boot`
- `Spring Security`
- `Spring Data JPA` or equivalent persistence abstraction if chosen consistently
- database migrations through a migration tool such as `Flyway` or `Liquibase`

### Database

- `PostgreSQL`

Reasoning:
- relational model fits folders, goals, tasks, sharing, reminders, and settings well
- predictable transactional behavior is important for collaborative edits and scheduling

### Web

- SPA architecture
- strongly typed frontend preferred if the chosen stack supports it cleanly
- localization support required from the start

Recommended direction:
- `React + TypeScript`

### Android

- native Android application
- push notifications through `Firebase Cloud Messaging`

Recommended direction:
- `Kotlin`

### Notifications

- backend computes deliveries
- `Firebase Cloud Messaging` sends Android push notifications

### CI/CD

- build and test automation for backend and web first
- Android build integration added as soon as the app skeleton exists

## 5. System Context

High-level system actors:
- web user
- Android user
- backend service
- PostgreSQL database
- Firebase Cloud Messaging

Core interaction model:
- web and Android authenticate with backend
- backend persists domain state in PostgreSQL
- backend schedules reminders and notification deliveries
- backend sends push notifications through FCM
- Android receives push and opens relevant task details

## 6. Deployment Shape

### MVP Deployment Model

The MVP should deploy as:
- one backend service
- one PostgreSQL instance
- one web frontend deployment
- one Android app build and distribution track

### Recommended Runtime Layout

- backend behind one public API base URL
- PostgreSQL reachable only by backend infrastructure
- web frontend served as static assets or via a lightweight web host/proxy
- Android app talking to the same backend API

### Operational Simplicity Rule

For MVP:
- do not introduce a message broker unless actual load or delivery guarantees require it
- do not introduce Redis unless a specific problem justifies it
- keep background scheduling inside the backend process unless scaling pressure appears

## 7. Backend Module Boundaries

The backend should be organized into explicit business modules.

### `auth`

Responsibilities:
- registration
- login
- token refresh or session renewal
- logout
- password hashing and validation
- authentication guards

Must not own:
- folders, goals, tasks
- scheduling logic

### `accounts`

Responsibilities:
- user profile
- timezone
- display name
- account-level information

Must not own:
- auth secrets
- scheduling execution

### `settings`

Responsibilities:
- interface language preference
- notification preferences
- priority decay settings for `green`
- priority decay settings for `red`

Must not own:
- task recurrence definitions

### `folders`

Responsibilities:
- folder CRUD
- folder ordering if supported
- folder ownership rules

Must not own:
- sharing
- direct task manipulation

### `goals`

Responsibilities:
- goal CRUD
- goal ownership rules
- goal listing within a folder

Must not own:
- task recurrence
- notification delivery

### `tasks`

Responsibilities:
- task CRUD
- task status transitions
- task type
- task priority
- task tagging
- task linking
- task planned and due dates

Must not own:
- reminder scheduling execution
- push delivery execution

### `sharing`

Responsibilities:
- share invitation flow
- share acceptance
- goal and task access records
- permission resolution

Must not own:
- folder ownership
- notification scheduling

### `calendar`

Responsibilities:
- time-window task projections
- filtering for day, week, and month views
- simple move operations from calendar interactions

Must not own:
- recurrence rule storage semantics
- access control source of truth

### `recurrence`

Responsibilities:
- recurrence rule definition
- recurrence validation
- next-occurrence calculation
- recurrence lifecycle actions

Must not own:
- reminder delivery
- UI-specific calendar projections

### `reminders`

Responsibilities:
- reminder rule definition
- reminder eligibility calculation
- reminder scheduling records if needed

Must not own:
- FCM integration itself

### `priority-policy`

Responsibilities:
- priority decay policy evaluation
- task-type-specific decay application
- reschedule impact calculation

Must not own:
- generic task persistence outside policy-related updates

### `notifications`

Responsibilities:
- device registration
- push payload preparation
- FCM integration
- notification delivery logging

Must not own:
- reminder business rules
- recurrence rules

## 8. Cross-Module Interaction Rules

To keep the monolith clean:

- `tasks` may depend on `goals` for ownership and containment validation
- `sharing` is the source of truth for collaborative access decisions
- `calendar` reads from `tasks` and time-related task data
- `recurrence` and `reminders` operate on tasks but should not absorb generic task CRUD concerns
- `priority-policy` reacts to reschedule actions and user settings
- `notifications` depends on outputs from `reminders`, not the other way around

Important rule:
- permission resolution should be centralized enough to avoid duplicated access logic across modules

## 9. Data Model Direction

This section gives architectural direction for persistence. It is not a final schema.

### Main Tables or Aggregate Roots

- `users`
- `user_credentials`
- `user_settings`
- `folders`
- `goals`
- `tasks`
- `task_tags`
- `task_tag_links`
- `task_links`
- `goal_shares`
- `task_shares`
- `share_invitations`
- `task_recurrence_rules`
- `task_reminder_rules`
- `task_reschedule_events`
- `device_registrations`
- `notification_deliveries`

### Aggregate Guidance

Suggested aggregate ownership:
- `Folder` aggregate owns folder identity and metadata
- `Goal` aggregate owns goal metadata and relation to folder
- `Task` aggregate owns task core state, tags, links, recurrence association, reminder association, and reschedule history references
- `UserSettings` aggregate owns language and priority decay configuration
- user timezone belongs to the account model and is not duplicated in `UserSettings`

MVP caution:
- do not over-formalize DDD aggregate patterns if they complicate straightforward implementation
- use aggregates as a modeling discipline, not ceremony

## 10. API Boundary Design

The external API should be REST-oriented and simple.

### Auth API

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

### Account and Settings API

- `GET /api/me`
- `GET /api/me/settings`
- `PATCH /api/me/settings`

### Folder API

- `GET /api/folders`
- `POST /api/folders`
- `PATCH /api/folders/{folderId}`
- `DELETE /api/folders/{folderId}`

### Goal API

- `GET /api/folders/{folderId}/goals`
- `POST /api/folders/{folderId}/goals`
- `GET /api/goals/{goalId}`
- `PATCH /api/goals/{goalId}`
- `DELETE /api/goals/{goalId}`

### Task API

- `GET /api/goals/{goalId}/tasks`
- `POST /api/goals/{goalId}/tasks`
- `GET /api/tasks/{taskId}`
- `PATCH /api/tasks/{taskId}`
- `DELETE /api/tasks/{taskId}`
- `POST /api/tasks/{taskId}/complete`
- `POST /api/tasks/{taskId}/cancel`

### Task Tag and Link API

- `PUT /api/tasks/{taskId}/tags`
- `POST /api/tasks/{taskId}/links`
- `DELETE /api/tasks/{taskId}/links/{linkId}`

### Calendar API

- `GET /api/calendar?from=...&to=...`
- `POST /api/tasks/{taskId}/move`

### Recurrence and Reminder API

- `PUT /api/tasks/{taskId}/recurrence`
- `PUT /api/tasks/{taskId}/reminders`

### Quick Reschedule API

- `POST /api/tasks/{taskId}/reschedule`

Recommended request shape:
- requested preset or explicit duration
- actor identity from auth context

### Sharing API

- `POST /api/goals/{goalId}/share`
- `POST /api/tasks/{taskId}/share`
- `GET /api/shares/invitations`
- `POST /api/shares/invitations/{invitationId}/accept`
- `POST /api/shares/invitations/{invitationId}/decline`

### Device API

- `POST /api/devices`
- `DELETE /api/devices/{deviceId}`

## 11. Authentication and Authorization Direction

### Authentication

The MVP uses:
- email
- password

Recommended session model:
- short-lived access token
- refresh token

Reasoning:
- supports both web and Android cleanly
- keeps API interaction consistent

### Authorization

Authorization must check:
- ownership
- explicit collaboration access

Central rule:
- all goal and task access decisions should go through a consistent permission service or policy layer
- concurrent updates on mutable entities should use optimistic locking with version-based conflict detection

This avoids:
- controller-by-controller custom logic
- drift between web-exposed behaviors
- accidental access leaks

## 12. Scheduling Architecture

Scheduling is a high-risk part of the MVP and must stay explicit.

### Scheduling Concerns

There are four distinct concerns:
- task planned time and due time
- recurrence
- reminders
- reschedule and priority decay

Canonical time model for MVP:
- user account stores one IANA timezone identifier
- planned and due timestamps are stored as timezone-aware instants
- recurrence and reminder calculations use the owner's current canonical timezone
- changing timezone affects future calculations only

They are related but should not be collapsed into one vague service.

### Recommended Internal Services

- `TaskSchedulingService`
  - validates planned and due time changes
  - coordinates task move operations

- `RecurrenceService`
  - validates and computes recurrence

- `ReminderService`
  - determines when reminders should fire

- `RescheduleService`
  - records postpone events
  - triggers policy evaluation

- `PriorityDecayService`
  - calculates priority changes based on policy and event history

### Architectural Rule

Do not hide business meaning behind generic names like:
- `SchedulerManager`
- `UtilityService`
- `CommonTaskProcessor`

Use specific services that match the domain.

## 13. Notification Flow

### High-Level Flow

1. a task has reminder rules
2. reminder eligibility is calculated by backend
3. backend determines a delivery should happen
4. backend resolves target devices for the user
5. backend sends push through FCM
6. backend stores delivery result
7. Android receives push and opens the task detail flow

### Delivery Rule

Notification sending must be idempotent enough to avoid duplicate spam in normal retry conditions.

MVP ownership rule:
- reminder deliveries for shared goals and shared tasks target the owner only

### Failure Handling

The MVP should:
- log failed deliveries
- tolerate transient provider failures
- support retry strategy if it can be done simply

Avoid:
- overengineering a distributed retry platform in MVP

## 14. Quick Reschedule and Priority Decay Flow

### Quick Reschedule Flow

1. user requests quick postpone on a task
2. backend verifies access
3. backend verifies planned time exists
4. backend computes new planned time from preset
5. backend stores reschedule event
6. backend updates task planned time
7. backend evaluates priority decay based on user policy and task type
8. backend stores the updated priority if decay applies
9. backend returns the updated task state

### Priority Decay Rule

For MVP:
- use policy presets `day`, `week`, `month`
- use separate settings for `green` and `red`
- keep the default decay amount at `1`
- apply the owner's policy even when a collaborator performs the postponement

### Auditability Requirement

The backend must retain enough information to answer:
- when was the task postponed
- by whom
- from what time to what time
- whether priority changed as a result

## 15. Localization Architecture

Localization is a first-class architecture concern for MVP.

### Localization Rules

- Russian is the primary language
- English is the secondary language
- all user-facing strings must be externalized
- no hardcoded UI strings in production components

### Source of Truth Rule

- `ru` language file is primary
- `en` language file must mirror the same keys

### Technical Recommendation

Store localization files in a dedicated frontend structure such as:
- `src/i18n/ru.json`
- `src/i18n/en.json`

Add validation:
- CI or pre-merge check to verify identical key sets

### User Preference Integration

- backend stores the selected language in user settings
- web loads and persists the selected locale
- Android may adopt the same preference when supported in MVP

## 16. Web Client Architecture Direction

The web client is the primary product interface and should remain simple.

Recommended structure:
- app shell
- auth area
- folders and goals navigation
- task workspace
- calendar view
- settings area
- sharing dialogs

UI architecture principles:
- retro visual system, not random one-off styling
- clear state transitions
- dense layouts
- explicit forms
- predictable modals and dialogs

Avoid:
- overabstracted component systems too early
- advanced client-side state machinery unless the project actually needs it

## 17. Android Client Architecture Direction

Android is a companion client for MVP.

Primary responsibilities:
- authentication
- browse goals and tasks
- view task details
- receive push notifications
- open task context from notifications

Architectural constraint:
- do not build web-parity complexity into Android during MVP

Recommended structure:
- auth module
- task list and detail module
- notification handling module
- settings support only if needed for basic consistency

## 18. Testing and Verification Architecture

Testing should align to architecture, not be bolted on later.

### Backend Verification

- unit tests for recurrence, reminder eligibility, and priority decay
- integration tests for auth, permissions, CRUD flows, sharing, and notifications
- migration tests

### Web Verification

- smoke tests
- key user journey tests
- localization switching tests
- calendar move and quick reschedule tests

### Android Verification

- login smoke
- push handling
- open-from-notification flow
- task rendering sanity checks

### Cross-Cutting Verification

- localization key synchronization validation
- permission leak tests
- reminder duplication checks

## 19. Key Technical Tradeoffs

### Modular Monolith vs Microservices

Chosen:
- modular monolith

Tradeoff:
- less distribution complexity now
- possible future extraction later if justified

### PostgreSQL vs More Flexible Storage Mix

Chosen:
- PostgreSQL only for MVP core state

Tradeoff:
- simpler operations and transactions
- fewer moving parts

### Background Scheduling In-Process vs Dedicated Worker Platform

Chosen:
- in-process scheduling inside the backend runtime

Tradeoff:
- simpler deployment
- acceptable for MVP scale
- may need refactoring later if load grows

Operational guardrail:
- MVP deployment must run a single backend instance until DB-backed scheduler claiming is introduced

### Web-First vs Equal Web/Android Feature Parity

Chosen:
- web-first

Tradeoff:
- faster MVP delivery
- Android remains useful without doubling implementation scope

## 20. Architecture Risks

Main risks:
- recurrence can expand into calendar-engine complexity
- access control can become inconsistent if permission checks are scattered
- reminder delivery can duplicate if scheduling is not idempotent enough
- priority decay can feel arbitrary if event history is not retained
- localization can drift without automated checks

## 21. Architecture Decisions to Keep Stable

These decisions should stay stable unless a strong reason appears:

- backend remains a modular monolith for MVP
- PostgreSQL is the primary data store
- web is the primary client
- Android remains a companion client
- sharing is only for goals and tasks
- Russian is the primary UI language
- localization key synchronization is mandatory
- scheduling logic is explicit and decomposed into named services

## 22. Next Documents

The next recommended documents are:
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`

The next implementation-facing step after this blueprint is to turn architecture into stable API and DTO contracts.
