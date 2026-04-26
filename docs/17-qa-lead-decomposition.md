# RocketFlow QA Lead Decomposition

## 1. Purpose

This document turns the existing RocketFlow QA strategy into implementation-time QA execution checkpoints.

It is written to support:
- wave-by-wave validation during implementation
- safe parallel execution with multiple engineering subagents
- clear acceptance gates before downstream teams integrate
- explicit handling of the highest-risk MVP behaviors

Scope rule:
- keep the MVP scope frozen
- do not expand product behavior unless a contradiction is already present in the baseline docs or implemented stage notes

## 2. Baseline Inputs

This decomposition is based on:
- `docs/02-execution-backlog.md`
- `docs/03-domain-specification.md`
- `docs/04-architecture-blueprint.md`
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`
- `docs/10-planning-crud-foundation.md`
- `docs/12-lead-handoff-package.md`

Current implementation baseline from the handoff package:
- backend skeleton exists
- auth and settings foundation exists
- owner-scoped planning CRUD exists
- tags CRUD baseline exists
- optimistic locking exists for mutable planning entities
- soft delete exists for folders, goals, and tasks

## 3. QA Mission For The Next Stage

QA should not wait for a final assembled MVP.

QA must:
- validate each delivery wave before the next dependency-heavy wave builds on it
- turn frozen rules into executable checks as soon as each slice is available
- catch contract drift early, especially in permissions, scheduling, localization, and notification behavior
- separate what can be verified in parallel from what requires integrated environments

## 4. Recommended QA Subagent Model

Recommended count for the current stage:
- `3` QA-oriented subagents

Recommended split:
- `QA-1 Backend/API Validation`
  - owns API contract checks, backend regression design, migration validation, optimistic locking checks
- `QA-2 Web and Localization Validation`
  - owns web smoke, UI journey coverage, localization switching, key-sync checks
- `QA-3 Scheduling and Android Validation`
  - owns recurrence, reminders, quick reschedule, priority decay, device registration, push flow, release smoke support

Why `3` is appropriate:
- the current backend foundation already exists and needs continuous validation
- web and Android concerns are different enough to avoid one broad UI bucket
- scheduling and notifications are risky enough to deserve focused ownership

If staffing is constrained, compress to `2`:
- backend plus scheduling
- web plus Android plus release smoke

## 5. Validation Packs

### Pack A. Foundation and Contract Pack

Focus:
- migrations
- auth
- settings
- API error model
- optimistic locking

Primary targets:
- auth endpoints
- `GET/PATCH /api/me/settings`
- conflict behavior for stale updates
- soft delete visibility rules

Exit signal:
- foundation APIs are stable enough for downstream feature teams

### Pack B. Planning CRUD Pack

Focus:
- folders, goals, tasks, tags
- owner-only access
- archived record behavior
- DTO shape consistency

Primary targets:
- folder CRUD
- goal CRUD
- task CRUD
- tag list/create
- task create/update tag assignment behavior

Exit signal:
- backend planning foundation is safe to build sharing and web flows on top of

### Pack C. Sharing and Permissions Pack

Focus:
- invitation lifecycle
- goal/task access rules
- shared resource discovery
- revoke/expire behavior
- stale concurrent update handling on shared entities

Primary targets:
- invitation create/accept/decline/revoke
- `/api/shares/resources`
- owner vs collaborator visibility
- permission denial on unrelated objects

Exit signal:
- no known permission leak in documented collaboration paths

### Pack D. Scheduling and Calendar Pack

Focus:
- recurrence
- reminders
- task move
- quick reschedule
- reschedule history
- priority decay
- timezone and DST behavior

Primary targets:
- `/api/tasks/{taskId}/move`
- `/api/tasks/{taskId}/recurrence`
- `/api/tasks/{taskId}/reminders`
- `/api/tasks/{taskId}/reschedule`
- owner-policy application for shared-task postponement

Exit signal:
- scheduling logic is predictable enough for web calendar use and notification delivery

### Pack E. Notification and Android Pack

Focus:
- device registration
- delivery logging
- push payload stability
- open-from-notification flow
- owner-only delivery semantics for shared tasks

Primary targets:
- `/api/devices`
- reminder-to-delivery pipeline
- Android auth
- Android task detail open path

Exit signal:
- Android companion scenarios are reliable in the shared test environment

### Pack F. Localization and Release Pack

Focus:
- language switching
- key synchronization
- translated critical flows
- release smoke
- residual risk reporting

Primary targets:
- Russian default flow
- English selection persistence
- web critical journeys in both locales where practical
- final release checklist

Exit signal:
- release recommendation can be made with explicit residual risk

## 6. Implementation-Time QA Checkpoints By Wave

### Wave 0. Project Setup and Documentation

QA checkpoint:
- verify QA strategy and decomposition docs exist and align with the execution backlog
- confirm documentation rule includes updating docs when behavior changes

QA can run in parallel:
- checklist preparation
- initial risk matrix

Gate to pass:
- QA has a tracked validation plan and ownership model before more implementation branches appear

### Wave 1. Domain Freeze

QA checkpoint:
- verify testable invariants exist for sharing, recurrence, reminders, quick reschedule, decay, and localization
- confirm edge cases are explicit enough to convert into tests

Known contradiction to track:
- frozen domain and API allow task status `cancelled`
- current planning CRUD foundation notes a persistence constraint of `todo`, `in_progress`, and `done`

QA can run in parallel:
- acceptance scenario drafting
- contradiction logging

Gate to pass:
- no unresolved rule ambiguity blocks test design for backend or web teams

### Wave 2. Architecture and Contracts

QA checkpoint:
- verify API contracts are testable
- verify permission rules are centralized
- verify time model, owner-only reminder semantics, optimistic locking, and single-instance scheduler guardrail are present

QA can run in parallel:
- API contract test skeleton design
- environment needs definition with DevOps

Waits for integration:
- nothing yet beyond document freeze

Gate to pass:
- contracts are stable enough to create automated checks without expected churn

### Wave 3. Backend Foundation

QA checkpoint:
- run Pack A and Pack B
- verify migration chain, auth, settings, planning CRUD, tags baseline, soft delete, and owner-only access
- verify conflict handling for stale updates

QA can run in parallel:
- backend API regression checks
- negative validation cases

Waits for integration:
- no Android or push verification yet

Gate to pass:
- backend foundation is green for owner-scoped use cases
- no critical migration, auth, CRUD, or conflict defect remains open

### Wave 4. Scheduling and Collaboration

QA checkpoint:
- run Pack C and Pack D
- verify invitation lifecycle, permission resolution, shared resource discovery, recurrence, reminders, quick reschedule, reschedule events, decay, device registration, and notification logging
- verify owner-only reminder delivery and owner-policy decay behavior on shared tasks

QA can run in parallel:
- sharing API validation can run beside recurrence/reminder validation once endpoints are available
- backend-level notification record checks can run before Android UI completion

Waits for integration:
- end-to-end push open flow
- full shared-environment scheduler checks

Gate to pass:
- no permission leak
- no scheduling logic defect that breaks documented rules
- no duplicate-delivery defect under normal single-instance execution

### Wave 5. Web MVP

QA checkpoint:
- run Pack F plus web-facing slices of Packs B, C, and D
- verify auth UI, folders/goals/tasks flows, calendar interaction, quick reschedule UI, settings, sharing UI, and localization behavior

QA can run in parallel:
- shell and localization checks can start as soon as the web shell exists
- journey smoke can grow incrementally as screens land

Waits for integration:
- full sharing UI validation until sharing backend is stable
- full calendar reschedule validation until scheduling backend is stable

Gate to pass:
- main web journeys succeed end to end against the current backend
- language switching and key synchronization checks are green

### Wave 6. Android Companion

QA checkpoint:
- run Pack E
- verify login, browse, task detail rendering, device registration, push receipt, and open-from-notification behavior

QA can run in parallel:
- Android auth and browsing checks after auth and DTO stability
- backend notification delivery validation can continue independently

Waits for integration:
- real push validation requires shared environment plus FCM configuration

Gate to pass:
- Android companion fulfills documented MVP scope without web-parity creep

### Wave 7. QA and Release Readiness

QA checkpoint:
- execute full regression stack
- produce residual risk report
- verify no document-contract mismatch remains untriaged

QA can run in parallel:
- backend regression
- web smoke
- localization checks
- release checklist preparation

Waits for integration:
- final cross-platform release smoke

Gate to pass:
- backend, web, Android, and release gates in Section 8 all pass

## 7. Top High-Risk Areas And When To Test Them

### 1. Permissions and Shared Resource Access

Why high-risk:
- a permission leak is a trust-breaking defect

Start testing:
- immediately when sharing endpoints and permission service land

Must be re-tested:
- before web sharing UI merge
- before release

### 2. Scheduling Semantics

Why high-risk:
- recurrence, reminders, reschedule history, and decay are tightly coupled

Start testing:
- as soon as recurrence and reminder endpoints exist

Must be re-tested:
- after calendar move support
- after notification delivery is wired
- before release

### 3. Owner-Scoped Reminder And Decay Rules On Shared Tasks

Why high-risk:
- easy for implementation to drift from frozen business rules

Start testing:
- when sharing and scheduling both exist

Must be re-tested:
- after Android notification flow
- before release

### 4. Optimistic Locking And Conflict Handling

Why high-risk:
- silent overwrite on shared tasks will create hard-to-debug trust issues

Start testing:
- now, against planning CRUD

Must be re-tested:
- after sharing lands
- before release

### 5. Timezone And DST Behavior

Why high-risk:
- incorrect future scheduling will damage user trust and can be subtle

Start testing:
- when recurrence/reminder behavior is executable

Must be re-tested:
- in shared environment with realistic clock/timezone fixtures
- before release

### 6. Push Delivery Idempotency

Why high-risk:
- duplicate reminders feel like spam

Start testing:
- when notification logging exists

Must be re-tested:
- when Android push handling is integrated
- before release

## 8. Acceptance Gates

### Backend Gate

Must be true:
- migration chain applies cleanly in CI
- auth and settings endpoints pass contract checks
- planning CRUD passes owner-scoped tests
- soft delete behavior matches contract
- optimistic locking returns `409 Conflict` on stale writes
- sharing endpoints enforce documented visibility rules
- recurrence, reminder, reschedule, and decay rules pass matrix checks
- notification delivery records are created predictably

Blockers:
- any permission leak
- any silent stale-write overwrite
- any contract-breaking API drift on a frozen endpoint

### Web Gate

Must be true:
- auth journey works end to end
- folder, goal, and task journeys work end to end
- task create/edit and calendar move flows work
- quick reschedule UI matches backend behavior
- sharing UI reflects actual access outcomes
- Russian default and English switch both work
- key-sync validation passes

Blockers:
- broken main journey
- localization drift on critical screens
- UI behavior that masks backend conflict or permission errors incorrectly

### Android Gate

Must be true:
- login works
- task and goal browsing works for the companion scope
- device registration succeeds
- push receipt is stable
- tapping the notification opens the intended task
- shared-task notifications still target the owner only

Blockers:
- failed open-from-notification path
- unstable push registration
- Android dependency on web-only behavior

### Release Readiness Gate

Must be true:
- backend gate passes
- web gate passes
- Android gate passes
- no open critical defect
- no open high-severity permission or scheduling defect
- residual risks are documented explicitly
- shared environment smoke is green
- localization sync is green
- release checklist is completed

## 9. Parallel QA Work Vs Integration-Dependent QA Work

QA can run in parallel:
- contract review and test case design after architecture and API freeze
- backend validation for auth, settings, CRUD, tags, and optimistic locking
- localization key-sync automation design once web i18n structure is known
- sharing API checks and scheduling API checks as separate backend tracks
- Android smoke design after auth and DTO stability

QA must wait for integration:
- end-to-end sharing UI validation
- calendar move plus decay plus reminder chain validation through the web client
- push delivery from backend through FCM into Android open flow
- final release smoke across backend, web, Android, and environment configuration

Recommended sequencing:
1. run backend/API packs as soon as endpoints land
2. run web shell and localization checks once the SPA shell exists
3. run sharing and scheduling backend packs in parallel when those slices appear
4. run Android notification checks only after backend delivery and Android open flow both exist
5. run final cross-system regression only after all three product surfaces are integrated

## 10. QA Deliverables Expected During Execution

The QA lead function should produce:
- wave-specific checkpoint checklist
- validation pack ownership map
- regression suite inventory
- defect log with severity and affected document reference where relevant
- release readiness recommendation

Minimum expected artifacts by the time implementation scales:
- backend API regression checklist
- permissions matrix checklist
- scheduling matrix checklist
- localization checklist
- Android push smoke checklist
- release gate summary

## 11. Immediate Next QA Actions

Recommended next steps:
1. Convert Pack A and Pack B into executable backend checks against the current foundation.
2. Open a QA-tracked contradiction item for task status drift: frozen docs include `cancelled`, while the current CRUD foundation notes only `todo`, `in_progress`, and `done`.
3. Prepare Pack C and Pack D checklists before sharing and scheduling implementation starts so teams can validate each slice immediately.

