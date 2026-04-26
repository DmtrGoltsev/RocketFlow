# RocketFlow CTO Lead Decomposition

## 1. Executive Decision

### Go / No-Go for Parallelization

Decision:
- `GO`, with controlled parallelization starting now.

Reasoning:
- MVP scope, domain rules, architecture direction, API direction, QA baseline, DevOps baseline, and the first backend foundation slice are already documented and sufficiently stable.
- The remaining work splits into mostly clean streams: backend collaboration and scheduling, web shell and flows, Android companion work, QA verification packs, and pipeline setup.
- The project is ready for multiple leads and implementation subagents as long as high-coordination surfaces stay centralized.

Parallelization guardrails:
- API contracts stay owned by backend lead with CTO review on material changes.
- database migrations stay single-owner per migration file
- localization key sets stay synchronized in the same change set
- permission logic stays centralized and is not reimplemented separately in each module
- scheduling logic stays under one backend owner group and is not fragmented across unrelated agents

Scope position:
- keep the MVP scope frozen
- do not reopen product boundaries unless a contradiction threatens implementation correctness

## 2. Current Delivery Baseline

Confirmed stable baseline:
- modular monolith with Spring Boot, PostgreSQL, REST, SPA web, Kotlin Android companion, and FCM push
- auth and settings foundation implemented
- owner-scoped folders, goals, tasks, and tags CRUD implemented
- optimistic locking and soft delete semantics already in place for planning entities

Open implementation streams:
- sharing and permission resolution
- recurrence, reminders, quick reschedule, reschedule history, priority decay, and calendar move behavior
- device registration and FCM delivery
- web client
- Android companion client
- CI/CD and staging baseline
- release hardening

## 3. Cross-Stream Dependency Map

### Stream Dependency Summary

1. `Backend contracts and shared rules`
- Depends on: frozen docs baseline
- Unlocks: frontend integration, Android DTO usage, QA API verification
- Notes: this is the highest-coordination surface and should not be edited independently by multiple streams

2. `Backend sharing and permission layer`
- Depends on: auth foundation, planning CRUD foundation, domain sharing rules
- Unlocks: web sharing UI, QA permission matrix, shared-resource discovery flows
- Notes: must become the single source of truth for collaborative access

3. `Backend scheduling domain`
- Depends on: task CRUD foundation, settings, canonical timezone rule
- Unlocks: calendar move behavior, quick reschedule UI, reminder delivery, priority decay verification
- Notes: recurrence, reminders, reschedule, and decay must be designed and implemented as one coherent slice

4. `Backend notifications and device registration`
- Depends on: scheduling reminder eligibility, device API contract, DevOps secret/config setup
- Unlocks: Android push flow, QA notification matrix, staging reminder validation
- Notes: keep idempotency and owner-only reminder semantics stable

5. `Web shell, auth, and localization foundation`
- Depends on: auth/settings contracts already mostly stable
- Unlocks: later web planning, sharing, settings, and calendar integration
- Notes: safe to start in parallel immediately

6. `Web planning and calendar flows`
- Depends on: folder/goal/task DTO stability, calendar and reschedule contract stability
- Unlocks: end-to-end primary user journey on web
- Notes: can start on existing CRUD paths, but calendar move and quick reschedule must not be guessed

7. `Web sharing and advanced settings`
- Depends on: sharing API, priority decay settings shape, reminder settings shape
- Unlocks: collaboration completion on web

8. `Android companion`
- Depends on: stable auth contract, stable task detail DTO, device registration contract, push payload shape
- Unlocks: MVP notification consumption on mobile
- Notes: should start after reminder and notification contracts are stable enough to avoid churn

9. `QA verification packs`
- Depends on: frozen docs now, testable environments later
- Unlocks: safe parallel delivery and release confidence
- Notes: QA can prepare matrices and automation scaffolding immediately, then execute against each wave

10. `DevOps baseline execution`
- Depends on: architecture and runtime shape already frozen
- Unlocks: safe CI, shared test environment, secret handling for notifications, release readiness

### High-Coordination Surfaces

The following surfaces require explicit single-thread ownership at any moment:
- `docs/05-api-contracts.md`
- backend migration files
- permission service and shared authorization rules
- scheduling service boundaries
- notification payload contract
- `ru/en` localization key sets

## 4. Recommended Execution Waves From Here

### Wave 1. Stabilize Shared Interfaces and Start Non-Blocking Work

Run in parallel:
- backend lead locks remaining contract details for sharing, reminders, recurrence, reschedule, and device APIs
- frontend lead starts web shell, auth screens, and localization infrastructure
- DevOps lead implements backend CI baseline and environment variable documentation enforcement
- QA lead converts the documented matrices into executable verification checkpoints

Wave 1 gate:
- resolve the current contract drift on task status support before web and Android assume final enum behavior

### Wave 2. Build the Core Backend Heart in Parallel

Run in parallel:
- backend stream A: sharing, invitations, shared-resource discovery, centralized permission checks
- backend stream B: recurrence, reminders, reschedule events, priority decay, calendar move semantics
- DevOps stream: test/staging environment preparation and secret handling path for FCM
- QA stream: API, permission, and scheduling automation for completed backend slices

Wave 2 gate:
- permission and scheduling APIs are stable enough for frontend integration

### Wave 3. Client Integration Wave

Run in parallel:
- web stream A: folders, goals, tasks, and calendar flows on top of stable APIs
- web stream B: sharing UI, settings UI, priority decay settings, reminder settings
- backend stream C: device registration and notification delivery hardening
- mobile stream: Android auth, browse, detail, push registration, open-from-notification

Wave 3 gate:
- push payload, task detail response, and device registration contract are stable

### Wave 4. End-to-End Hardening and Release Readiness

Run in parallel:
- QA full regression across permissions, scheduling, localization, and notification flows
- DevOps staging hardening, deployment checklist, observability baseline
- backend/frontend/mobile defect burn-down

Exit criteria:
- no critical permission, scheduling, notification, or localization defects remain open

## 5. Architectural Blockers

Architectural blockers:
- none that justify stopping parallel execution

Required alignment items before deeper client integration:
- task status contract drift must be resolved: domain and API docs include `cancelled`, while the current planning CRUD foundation notes backend status support as `todo`, `in_progress`, and `done`
- single-backend-instance operational guardrail must remain in force until DB-backed scheduler claiming exists
- permission logic must remain centralized; if access checks start being copied into controllers or feature services, parallelization risk rises sharply

Assessment:
- these are coordination constraints, not architecture redesign blockers

## 6. Recommended Lead Coordination Cadence

Recommended cadence:
- `daily` 15-minute lead sync focused only on blockers, dependency changes, and ownership collisions
- `twice weekly` architecture and contract review for API changes, migration plans, scheduling semantics, and notification payload changes
- `weekly` release-readiness review across CTO, QA, and DevOps leads

Working agreement:
- every stream posts async status with `done / next / blocked`
- any proposed change to contracts, migrations, permission rules, or scheduler behavior gets documented before or with implementation
- no lead assigns two subagents to the same file cluster unless one is explicitly read-only

## 7. Recommended Implementation Subagents By Competency Area

Recommended active subagent count from this point:

- `Backend`: `3`
- `Frontend`: `3`
- `Mobile`: `1`
- `QA`: `2`
- `DevOps`: `1`

Recommended ownership split:

### Backend

1. `Sharing and Access`
- invitations
- goal/task shares
- shared resource discovery
- centralized permission service

2. `Scheduling and Calendar Semantics`
- recurrence
- reminders
- calendar move behavior
- quick reschedule
- reschedule history
- priority decay

3. `Notifications and Integration Hardening`
- device registration
- FCM delivery
- notification logging and retry discipline
- integration tests for notification flow

### Frontend

1. `Shell and Localization`
- app shell
- auth entry flow
- Russian-first i18n structure
- English key parity support

2. `Planning and Calendar`
- folder/goal/task screens
- task forms
- calendar projection and move flows
- quick reschedule UI

3. `Sharing and Settings`
- sharing dialogs and invitation flows
- settings screens
- priority decay controls
- reminder settings UX

### Mobile

1. `Android Companion`
- auth
- goal/task browse
- task detail
- device registration
- push receipt
- open-from-notification

### QA

1. `API and Permission Verification`
- auth
- CRUD
- sharing
- optimistic locking
- contract checks

2. `Scheduling, Localization, and Release`
- recurrence
- reminders
- quick reschedule
- priority decay
- localization sync
- Android notification flow

### DevOps

1. `Pipeline and Environment Baseline`
- backend CI
- web and Android pipeline scaffolding as each client appears
- staging/test environment setup
- secret handling and deployment checklist

## 8. Risks To Watch During Delegation

Primary delegation risks:

- contract churn across backend, web, and Android if API ownership is not centralized
- duplicated permission logic causing hidden access leaks
- scheduling work being split too finely, producing inconsistent recurrence, reminder, and reschedule behavior
- migration collisions if multiple backend agents try to author schema changes simultaneously
- localization drift if `ru` and `en` files are updated in separate change sets
- Android starting too early on unstable reminder or notification contracts
- QA getting pulled too late, which would hide cross-stream regressions until release hardening
- operational drift if scheduler assumptions are violated and more than one backend instance runs before claim-based coordination exists
- implementation drift from frozen scope, especially around folder sharing, advanced permissions, chat/comments, or Android feature parity

Mitigation posture:
- keep owners explicit
- keep write scopes disjoint
- review high-coordination surfaces on a fixed cadence
- prefer contract-first changes before client integration

## 9. CTO Recommendation

Recommendation:
- proceed with multi-lead decomposition immediately
- start frontend shell, QA checkpoint design, and DevOps baseline work now
- run backend sharing and backend scheduling as the primary parallel engineering wave
- bring Android into active implementation once notification and task-detail contracts are stable

Final CTO position:
- RocketFlow is ready for controlled parallel execution
- there are no architectural stop-sign blockers
- success now depends more on coordination discipline than on further central planning
