# RocketFlow QA Strategy

## 1. Purpose

This document defines the MVP quality strategy for RocketFlow.

Its purpose is to make testing and release confidence part of delivery from the beginning. It describes:
- quality goals
- risk areas
- testing scope
- testing layers
- acceptance criteria direction
- release readiness checks

This document should guide:
- QA planning
- backend and frontend automated testing
- Android verification
- regression discipline
- release decisions

## 2. Quality Goals

The MVP must be:
- functionally coherent
- safe in access control behavior
- predictable in scheduling behavior
- understandable in localization behavior
- stable enough to release without major user trust issues

For RocketFlow, quality is not just UI correctness. It especially includes:
- correct permissions
- correct recurrence and reminder behavior
- correct quick reschedule behavior
- correct task-priority retirement and V20 compatibility behavior
- reliable Android notification flow

## 3. Primary Risk Areas

### Access Control Risk

Why it matters:
- users can share goals and tasks
- accidental permission leaks would be a severe trust failure

High-risk scenarios:
- collaborator can access unrelated resources
- revoked access still works
- task-level sharing and goal-level sharing interact incorrectly
- stale concurrent updates silently overwrite each other

### Scheduling Risk

Why it matters:
- recurrence, reminders, and postponement are central product behaviors

High-risk scenarios:
- reminders fire at the wrong time
- recurring tasks generate incorrect future instances
- moving a task later does not create the correct reschedule trail
- DST or timezone changes shift future reminders incorrectly

### Task Priority Retirement Risk

Why it matters:
- old APK/V20 rollback support still needs legacy fields even though priority has no product meaning

High-risk scenarios:
- task priority leaks back into UI, validation, settings, sorting, or business behavior
- V21 rewrites/drops historical values or rejects old request shapes
- new clients overwrite historical shadows when talking to V20
- technical FCM notification priority is accidentally retired with task priority

### Localization Risk

Why it matters:
- Russian is primary but English must stay synchronized

High-risk scenarios:
- missing translation keys
- untranslated screens
- language preference not applied consistently

### Notification Risk

Why it matters:
- Android reminder delivery is a key MVP promise

High-risk scenarios:
- device token registration fails silently
- push is sent but app cannot open the correct task
- repeated deliveries spam the user
- owner-only reminder semantics for shared tasks drift in implementation

## 4. Test Scope by Layer

### Backend

Must verify:
- authentication
- permissions
- folder, goal, task CRUD
- recurrence
- reminders
- quick reschedule
- ignored legacy task/settings fields, historical-shadow preservation, and deterministic priority-free ordering
- sharing
- device registration
- notification delivery behavior

### Web

Must verify:
- auth flows
- main planning flows
- simple calendar flows
- quick reschedule UI
- settings
- absence of task-priority/policy controls and V20-compatible hidden shadows
- language switching
- shared resource access behavior in UI

### Android

Must verify:
- authentication
- goal and task rendering
- stable Planner anchor/offset restoration and fallbacks
- priority-shadow SQLite/wire compatibility without UI exposure
- push receipt
- open-from-notification flow

### Cross-Cutting

Must verify:
- API contract consistency
- localization key synchronization
- data migration safety
- release smoke checks

## 5. Testing Layers

### Unit Tests

Use unit tests for focused domain logic.

Best candidates:
- recurrence calculations
- reminder eligibility rules
- Planner anchor/offset restoration and priority-shadow normalization
- permission decision helpers

Goal:
- fast, focused, deterministic verification of critical business logic

### Integration Tests

Use integration tests for:
- controller and service interaction
- persistence behavior
- auth and permission enforcement
- sharing flow
- reminder scheduling and delivery records

Goal:
- verify that real application pieces work together correctly

### API Tests

Use API-level tests for:
- request validation
- response shape
- status codes
- business rule enforcement

Goal:
- keep the documented API behavior trustworthy for web and Android clients

### UI Tests

Use web UI tests for:
- authentication smoke
- create folder, goal, task flows
- task editing
- calendar movement
- quick reschedule
- settings language switch

Goal:
- verify the main user journeys end to end through the web interface

For MVP3 hierarchy and links simplification, UI acceptance must also follow:
- `docs/62-mvp3-design-simplification-contract.md`
- `docs/64-mvp3-ba-simple-journeys.md`

### Mobile Verification

Use Android-focused tests for:
- login
- task detail rendering
- push flow
- task deep link opening

Goal:
- verify the companion app fulfills MVP responsibilities reliably

For MVP3, Android verification must include the same simplified quick capture, summary-first detail, compact row, share sheet, dependency wording, private redaction, and DnD/fallback journeys documented in `docs/62-mvp3-design-simplification-contract.md` and `docs/64-mvp3-ba-simple-journeys.md`.

### Manual Exploratory Testing

Manual exploration is still needed for:
- retro UI usability
- awkward edge cases
- timezone-related behavior
- notification timing sanity checks
- collaboration conflict resolution behavior

## 6. Test Ownership Direction

### Backend Team

Responsible for:
- unit tests for domain logic
- integration tests for backend modules
- API contract tests

### Frontend Team

Responsible for:
- component or screen-level tests where useful
- web journey smoke tests
- localization behavior in web UI

### Mobile Team

Responsible for:
- Android smoke tests
- notification handling checks

### QA Lead

Responsible for:
- test matrix
- risk prioritization
- regression planning
- acceptance criteria mapping
- release readiness recommendation

## 7. Test Environment Strategy

### Local Development

Used for:
- unit tests
- developer integration tests
- fast UI checks

### Shared Test Environment

Used for:
- end-to-end smoke
- sharing flows
- Android push validation
- release candidate validation

### Environment Expectations

The shared test environment should support:
- backend API
- PostgreSQL
- web client
- Android app configuration pointing to the test backend
- FCM test configuration

## 8. Core Acceptance Scenarios

The following scenarios are MVP-critical and must be validated before release.

### Scenario 1. User Registration and Login

Expected result:
- a user can register, log in, refresh session, and access protected resources

### Scenario 2. Folder, Goal, and Task Creation

Expected result:
- a user can create a folder, create a goal inside it, and create tasks inside the goal

### Scenario 3. Task Scheduling

Expected result:
- a user can set planned and due times and see the task in calendar results

### Scenario 4. Quick Reschedule

Expected result:
- a user can postpone a task with a supported preset
- the task planned time updates
- a reschedule event is recorded

### Scenario 5. Task Priority Retirement Compatibility

Expected result:
- task priority and decay settings are absent from product UI and sorting
- old task/settings request fields are accepted and ignored
- new tasks use shadow `5`; existing historical shadows survive update/reschedule
- reschedule records an audit event and reports no decay

### Scenario 6. Recurrence

Expected result:
- recurrence rules can be saved
- future scheduling behavior is consistent with the rule

### Scenario 7. Reminder Rules

Expected result:
- reminders can be configured
- invalid reminder anchors are rejected
- eligible reminders create delivery attempts

### Scenario 8. Goal Sharing

Expected result:
- owner can invite another user to a goal
- collaborator can access and edit the shared goal and its tasks
- unrelated resources remain inaccessible

### Scenario 9. Task Sharing

Expected result:
- owner can share a task directly
- collaborator can edit only the shared task if the parent goal is not shared

### Scenario 10. Language Switching

Expected result:
- user can switch between Russian and English in settings
- UI updates correctly
- translation keys exist in both locales

### Scenario 11. Android Push Notification

Expected result:
- Android device registers successfully
- reminder triggers push delivery
- tapping the notification opens the correct task

## 9. Permission Test Matrix

The permission model must be verified explicitly.

Minimum matrix:

- owner can access own folder
- collaborator cannot access folder through sharing
- owner can access own goal
- goal collaborator can access shared goal
- goal collaborator can access tasks under shared goal
- task collaborator can access directly shared task
- task collaborator cannot access unrelated tasks in the same goal unless goal is shared
- revoked collaborator loses access immediately on the next request
- expired invitation does not grant access
- collaborators can discover shared resources without folder ownership
- stale writes return conflict instead of silently succeeding

## 10. Scheduling Test Matrix

Minimum scheduling verification:

- task with planned time appears in calendar query
- moving a task later records a reschedule event
- moving a task earlier or later does not change the legacy priority shadow
- quick reschedule works for `30m`, `1h`, `3h`, `24h`
- quick reschedule fails when planned time does not exist
- recurrence weekly rule validates required weekdays
- reminder before planned time fails if planned time is absent
- reminder before due time fails if due time is absent
- recurring task completion behavior matches implementation rule
- timezone change affects future calculations only
- DST boundary cases preserve intended owner-local behavior

## 11. Task Priority Retirement Test Matrix

Minimum verification:

- create accepts omitted, `null`, and old `priority` values and returns/stores `5`
- update accepts omitted, `null`, and old values while preserving historical stored shadows
- clone uses `5`; move-to-goal preserves the existing shadow
- task, calendar, and shared lists order deterministically without priority
- settings policy controls are hidden; policy-only payloads are ignored without version/timestamp/data changes
- web/Android default a missing response shadow to `5` and preserve fetched shadows for V20 updates
- V20-to-V21 migration changes defaults only and retains all historical task/event/settings values, columns, constraints, and indexes
- reschedule preserves priority-before/after and returns `priorityDecayApplied=false`
- FCM data-only messages still use technical Android `HIGH` priority

## 12. Localization Test Matrix

Minimum verification:

- Russian is the default language for a new user
- English can be selected in settings
- the selection persists across sessions
- `ru` and `en` files contain the same keys
- no production screen contains raw missing-key output

## 13. Notification Test Matrix

Minimum verification:

- Android device registration succeeds
- duplicate device handling is predictable
- reminder produces a delivery attempt
- failed delivery is logged
- successful delivery can open the target task
- duplicate reminders do not cause repeated spam under normal conditions
- shared-task reminders are delivered to the owner only in MVP

## 14. Automation Priorities

Highest automation priority:
- auth
- permissions
- task CRUD
- recurrence calculations
- reminder rules
- task-priority retirement compatibility and deterministic ordering
- quick reschedule
- localization key synchronization
- migration path verification against PostgreSQL

Medium priority:
- web main-flow smoke tests
- Android notification flow smoke tests

Manual-first if needed in early MVP:
- visual retro styling evaluation
- edge-case UX consistency
- timezone change behavior

## 15. Regression Strategy

Every meaningful feature change should trigger at least:
- backend automated test run
- localization synchronization check if UI strings changed
- web smoke tests if user-facing flows changed

Before release candidate:
- full backend integration suite
- web critical journey smoke
- sharing permission regression
- scheduling regression
- Android notification regression

## 16. Release Readiness Checklist

The MVP should not be considered release-ready unless:
- auth works end to end
- folders, goals, and tasks work end to end
- sharing works without permission leaks
- recurrence rules work in supported scenarios
- reminder rules work in supported scenarios
- quick reschedule works
- task priority stays absent from product behavior while V20 compatibility shadows remain intact
- Android push flow works
- Russian and English localization both work
- localization keys are synchronized
- no critical blocker remains open

## 17. Defect Severity Guidance

### Critical

Examples:
- authentication broken
- permission leak
- notifications sent to the wrong user
- data corruption in core entities

### High

Examples:
- recurrence creates wrong future behavior
- retired priority changes data or affects ordering/settings behavior
- quick reschedule corrupts task timing
- Android push cannot open task

### Medium

Examples:
- incorrect UI state after edit
- one language switch issue on a non-core screen
- duplicate but harmless delivery log behavior

### Low

Examples:
- cosmetic retro styling issue
- minor wording inconsistency

## 18. Reporting and Documentation Rule

Quality findings must be documented with enough detail to reproduce them.

Minimum bug record should contain:
- summary
- environment
- reproduction steps
- expected result
- actual result
- severity

Important rule:
- if behavior differs from the documented domain or API contract, the mismatch must be recorded against the relevant document as well

## 19. Active QA Evidence Documents

- `docs/68-scroll-and-priority-retirement-delivery.md` contains the current V21-candidate scope, evidence, and release gates.
- `docs/67-weekly-focus-production-rollout-evidence.md` remains immutable historical evidence for the deployed V20 rollout.

## 20. Next Step

With the QA strategy documented, the project is ready to begin implementation foundation work.

Recommended next implementation steps:
- backend project skeleton
- database migration setup
- auth and settings foundation
- web shell and localization foundation in parallel

## 21. Calendar, Focus, and Push Regression Gate

Required coverage for this feature includes:

- Calendar date-only ranges, user timezone/DST boundaries, planned/deadline/dual markers, recurring instances, shared descendants, and task navigation.
- one active ISO-week Focus, effort fallback `null/0 -> 1`, completed-weight math, reorder, explicit rollover, history snapshots, archive/delete/access-loss lifecycle, tenant-scoped candidate processing above 5,000 rows, pagination, optimistic conflicts, and idempotent offline retries.
- cadence presets and quiet hours, regular non-overdue notifications, suppression for empty/completed Focus, stable event ids, outbox lease/heartbeat recovery, bounded backoff, retry fairness, FCM typed outcomes/timeouts, stale subscription removal, and Web Push endpoint security.
- Web logout/account switching, service-worker deep links, stale-response guards, keyboard/focus behavior, and responsive layouts.
- Android cold Focus deep link, event deduplication, offline cache/rebase, rotation restoration, terminal `401` handling without session resurrection, and proof that no local repeating Focus alarm is scheduled.

Current feature-branch evidence is backend `142/142`, web `61/61` with production build/audit PASS, and Android `90/90` with debug build, lint (`0` errors, `34` existing warnings), and debug Android-test APK assembly PASS. Coverage includes stable Android Planner anchor/offset restoration, V20/V21 compatibility shadows, no-rewrite V21 migration, hidden policy settings, SQLite lifecycle ownership, compact landscape editor/IME policy, and priority-free deterministic ordering. Dedicated visual QA passed scroll restoration and portrait/landscape editor scenarios; the latest IME rerun did not repeat the earlier anchor/logcat run. These counts describe this checkpoint only. Real-provider FCM and Web Push smoke remains a release-environment gate.

Production remains on V20 until an approved V21 deploy is recorded. Release verification must cover joint backend/web promotion through the existing helper, with Flyway preflight `>=20`, manifest target `=21`, and post-start `>=21`; the new web must remain compatible with both V20 and V21, and Android follows separately. Application rollback requires pre/post Flyway `>=20` with no row-count decrease and treats a V20 target as forward-compatible with schema V21.
