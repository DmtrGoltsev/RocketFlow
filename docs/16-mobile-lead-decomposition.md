# RocketFlow Mobile Lead Decomposition

## 1. Purpose

This document decomposes the Android MVP workstream for RocketFlow after the project handoff.

It is based on:

- `docs/01-primary-mvp-plan.md`
- `docs/02-execution-backlog.md`
- `docs/04-architecture-blueprint.md`
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`
- `docs/11-devops-baseline.md`
- `docs/12-lead-handoff-package.md`

The MVP scope remains frozen. No contradiction requiring scope change was found in the reviewed documents.

## 2. Mobile Mission

Android is a companion client for MVP, not a second full product.

The Android app must support only these end-to-end user outcomes:

- authenticate with email and password
- browse owned and shared goals/tasks
- open task details
- register the device for push
- receive reminder notifications
- open the correct task from a notification or deep link

## 3. Android Companion Scope Breakdown

### In Scope

- login using `POST /api/auth/login`
- token refresh handling using `POST /api/auth/refresh`
- basic session persistence and logout cleanup
- current-user bootstrap using `GET /api/me`
- browse owned folders and goals needed to reach tasks
- browse shared goals and tasks through `GET /api/shares/resources`
- browse tasks within a goal using `GET /api/goals/{goalId}/tasks`
- open task detail using `GET /api/tasks/{taskId}`
- register Android device token using `POST /api/devices`
- delete device registration on logout if safe and supported
- receive FCM push payload with at least `type` and `taskId`
- route notification tap into task detail flow
- Russian-first UI with English support for the small Android surface

### Out of Scope

- folder creation or editing
- goal creation or editing
- task creation, editing, completion, cancellation, move, or delete
- calendar screen or calendar editing
- recurrence management
- reminder rule editing
- quick reschedule UI
- priority decay settings
- invitation management UI
- offline mode
- tablet-specific redesign
- background sync beyond notification-triggered fetch

## 4. Recommended Mobile Workstreams

### Workstream A. App Foundation and Session

Objective:
- create the Android shell that can authenticate, persist session state, refresh tokens, and bootstrap the signed-in user

Main tasks:
- define Android module/package structure for `auth`, `browse`, `detail`, `notifications`
- add API client, auth interceptor, token refresh path, and error mapping
- implement login screen and signed-in bootstrap
- implement logout cleanup and device token unregister path if backend behavior is stable

Definition of done:
- user can log in, restart the app, remain signed in, and recover from expired access tokens through refresh

### Workstream B. Browse Flows

Objective:
- let the user reach relevant goals and tasks without turning Android into the main planning surface

Main tasks:
- implement owned-resource browse using `GET /api/folders`, `GET /api/folders/{folderId}/goals`, and `GET /api/goals/{goalId}/tasks`
- implement shared-resource entry using `GET /api/shares/resources`
- design a simple browse IA that separates owned and shared resources clearly
- handle empty, loading, auth-expired, and forbidden states

Definition of done:
- user can navigate from app home to owned tasks and directly discover shared goals/tasks

### Workstream C. Task Detail Flow

Objective:
- render a stable read-only task detail screen that is the target for browse and notification entry

Main tasks:
- implement `GET /api/tasks/{taskId}` integration
- render core fields from `TaskDto`
- render tags, recurrence summary, reminder summary, planned/due times, and shared marker where present
- handle `404`, `403`, and stale-session recovery states

Definition of done:
- user can open any accessible task from browse or notification and understand its current state

### Workstream D. Push and Deep-Link Flow

Objective:
- make Android notification delivery operational and trustworthy

Main tasks:
- integrate Firebase Messaging SDK
- register and refresh FCM token with `POST /api/devices`
- define notification payload parsing for minimum payload contract
- implement notification tap routing into task detail
- support cold start, warm start, and logged-out entry handling

Definition of done:
- a reminder push reaches the device and tapping it opens the correct task flow

## 5. Task Decomposition by MVP Flow

### Auth Flow

Tasks:
- create login screen and validation
- integrate login request/response contract
- persist access and refresh tokens securely
- call `GET /api/me` after login to bootstrap profile, timezone, and language
- implement refresh-token retry path for protected requests
- handle logout and token-clear behavior

Depends on:
- stable auth responses
- stable error model

### Browse Flow

Tasks:
- implement home routing for signed-in users
- load owned folders
- load goals within a folder
- load tasks within a goal
- load shared resources from `/api/shares/resources`
- define simple browse navigation and empty states

Depends on:
- stable folder, goal, and task list DTOs
- sharing discovery endpoint behavior

### Detail Flow

Tasks:
- fetch task by ID
- map `TaskDto` to read-only detail UI
- localize enum labels locally
- handle access loss and deleted-task states

Depends on:
- stable `TaskDto`
- stable access-control behavior for direct task fetch

### Push Flow

Tasks:
- add Firebase app setup and app config wiring
- register device token after successful auth
- refresh backend token registration when FCM token changes
- display local notification when push is received in background as required by app state
- avoid duplicate registration churn

Depends on:
- working `POST /api/devices`
- test/staging FCM configuration
- backend reminder delivery pipeline

### Deep-Link Flow

Tasks:
- define one Android entry path for notification taps
- extract `taskId` from push payload or deep link
- if signed in, open detail directly
- if signed out or token expired, complete auth recovery and then continue to detail
- handle inaccessible or missing task with clear UX

Depends on:
- stable minimum push payload
- task fetch by ID
- reliable session restoration behavior

## 6. Sequential vs Parallel Plan

### Sequential Tasks

These should stay sequential because later tasks depend on them directly:

1. finalize Android package/module boundaries and networking baseline
2. implement auth session and token refresh path
3. implement read-only task detail contract mapping
4. finalize notification routing contract
5. run end-to-end push and deep-link verification in staging

### Parallel Tasks

These can run in parallel after the auth/networking baseline is stable:

- browse UI implementation can run in parallel with task-detail UI
- push SDK integration can run in parallel with browse screens
- localization of the Android surface can run in parallel with browse/detail implementation
- smoke-test scaffolding can run in parallel with push/deep-link wiring once navigation contracts are fixed

### Recommended Execution Order

1. app foundation and auth
2. browse skeleton and task detail in parallel
3. push token registration and FCM wiring in parallel with browse/detail hardening
4. deep-link routing
5. integrated QA pass for auth, browse, detail, push, and notification open flow

## 7. Recommended Mobile Subagent Count

Recommended count:
- `2` mobile implementation subagents

Why `2`:
- Android scope is intentionally small
- a higher count would create coordination overhead around shared navigation, networking, and notification entry points
- one agent can own app/session foundation while one agent owns UI flow assembly, with shared contracts documented in this file

Recommended ownership split:

- Subagent 1: app foundation, auth/session, networking, device registration, FCM integration
- Subagent 2: browse flows, task detail UI, deep-link routing, Android-facing localization strings

Optional temporary QA-focused helper:
- `+1` short-lived validation subagent only after feature wiring exists, for smoke coverage and device-path verification

## 8. Backend Dependencies and Blockers

### Required Backend Dependencies

- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `GET /api/me`
- `GET /api/folders`
- `GET /api/folders/{folderId}/goals`
- `GET /api/goals/{goalId}/tasks`
- `GET /api/tasks/{taskId}`
- `GET /api/shares/resources`
- `POST /api/devices`
- `DELETE /api/devices/{deviceId}` if logout unregister is required

### Required Contract Stability

- auth response structure and token refresh behavior
- `TaskDto` field names and enum values
- shared-resource discovery response shape
- consistent `401`, `403`, `404`, and `409` behavior
- push payload minimum contract:
  - `type`
  - `taskId`

### Current Blockers or Likely Blockers

- device registration is still open in the handoff package
- push delivery integration is still open in the handoff package
- sharing foundation is still open, so shared browse cannot be finished until `/api/shares/resources` behavior is implemented
- reminder delivery pipeline must exist before real push verification can pass
- staging/test FCM configuration is required before mobile can verify notification delivery end to end

### Mobile Start Rule

Android work can start before all notification backend work is done, but only up to:

- auth/session foundation
- browse shell with mocked or stubbed notification entry
- task detail rendering against stable DTOs

End-to-end push validation must wait for:

- device registration endpoint readiness
- backend reminder delivery readiness
- staging FCM credentials/config

## 9. Risks and Mitigations

### Risk 1. Android scope drifts into write flows

Mitigation:
- keep all Android task screens read-only for MVP
- reject requests to add create/edit/calendar actions unless a documented contradiction appears

### Risk 2. Shared-resource UX becomes folder-parity UI

Mitigation:
- use a dedicated shared section sourced from `/api/shares/resources`
- do not invent shared folder ownership concepts on Android

### Risk 3. Push open flow breaks on expired session

Mitigation:
- make notification routing dependent on the same session restoration path used by protected API calls
- verify cold start and expired-token scenarios explicitly

### Risk 4. DTO churn causes rework

Mitigation:
- freeze Android-facing DTO fields before UI polishing
- keep browse/detail mapping thin and explicit

## 10. Strict Anti-Scope-Creep Notes

The following must be treated as hard guardrails for MVP:

- Android is companion-only; web remains the primary place for planning and management
- do not add task edit or quick-reschedule controls on Android
- do not add calendar browsing or drag/move interactions on Android
- do not add invitation acceptance flows on Android unless explicitly re-scoped at product level
- do not add parity settings management beyond what is strictly needed for session consistency
- do not add offline cache/sync architecture
- do not redesign backend contracts for Android convenience if web/back-end documents already froze them
- do not expand push into a general notification center feature

## 11. Mobile Definition of Done for MVP

Android is done for MVP when:

- user can log in and stay signed in
- user can browse owned and shared planning items needed for companion usage
- user can open a read-only task detail screen
- device token registers successfully
- reminder push can be received in staging
- tapping the notification opens the correct task flow
- QA smoke checks for auth, browse, detail, push, and deep-link flow pass
