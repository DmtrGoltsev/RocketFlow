# RocketFlow Frontend Lead Decomposition

## 1. Purpose

This document decomposes the RocketFlow web MVP into frontend-owned workstreams, implementation tasks, sequencing rules, and subagent boundaries.

It is based on the frozen project inputs:

- `docs/01-primary-mvp-plan.md`
- `docs/02-execution-backlog.md`
- `docs/03-domain-specification.md`
- `docs/04-architecture-blueprint.md`
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`
- `docs/12-lead-handoff-package.md`

This decomposition keeps MVP scope frozen. No product-scope contradiction was found in the source set.

## 2. Frontend Mission and Scope

Frontend owns the primary web client for MVP. The web app must let users complete the main journeys end to end:

- register and log in
- manage folders, goals, and tasks
- schedule tasks and use quick reschedule
- view tasks in a simple calendar
- manage sharing and invitations
- change language and scheduling-related settings

Frontend must preserve these frozen constraints:

- web-first, desktop-first SPA
- retro UI direction, not glossy modern SaaS styling
- Russian-first localization with English kept in lockstep
- no scope expansion into folder sharing, comments, attachments, offline mode, or advanced analytics
- Android remains out of frontend web scope

## 3. Delivery Assumptions

The handoff package states that backend foundation already exists for:

- auth
- settings
- folder CRUD
- goal CRUD
- task CRUD

Frontend should therefore plan around two dependency classes:

- stable-enough contracts already available for shell, auth, settings bootstrap, and planning CRUD
- not-yet-delivered contracts for sharing, recurrence/reminders final behavior, calendar move nuances, quick reschedule, and priority decay presentation

## 4. Web MVP Workstreams

### Workstream A. Shell and Retro Design System

Goal:
- establish the app shell, navigation frame, reusable retro primitives, and layout rules

In scope:
- application frame
- protected and public layout split
- retro design tokens
- buttons, inputs, lists, panels, dialogs, badges, form states
- loading, empty, error, and conflict states

Out of scope:
- feature-specific business logic
- API-specific forms beyond scaffolding

### Workstream B. RU-First i18n Foundation

Goal:
- create localization infrastructure that enforces Russian as source language and English parity

In scope:
- locale bootstrapping
- translation file structure
- language switching integration
- missing-key prevention
- localization sync validation hook or check

Out of scope:
- copywriting beyond MVP features
- third language support

### Workstream C. Auth and Session UX

Goal:
- deliver registration, login, session restore, logout, and protected-route behavior

In scope:
- register and login screens
- token/session handling
- auth bootstrapping on app load
- unauthorized and expired-session UX

Out of scope:
- password reset if not already in frozen scope

### Workstream D. Planning Workspace

Goal:
- deliver the main folders, goals, and tasks workflow

In scope:
- folder list and create/edit/archive UX
- goal list/detail create/edit/archive UX
- task list/detail create/edit/delete UX
- tag and task-link editing if the backend surface is present
- recurrence and reminder editing once the APIs are stable

Out of scope:
- folder sharing
- advanced dependency visualizations for task links

### Workstream E. Calendar and Quick Reschedule

Goal:
- deliver the simple calendar and time-based task operations

In scope:
- calendar query and rendering
- move task interaction
- quick reschedule action using fixed presets
- conflict/error UX for invalid reschedule and missing planned time

Out of scope:
- advanced drag-and-drop scheduler
- complex recurrence authoring UI beyond MVP rule shape

### Workstream F. Sharing and Shared Resource UX

Goal:
- deliver goal/task sharing and collaborator entry points without expanding permissions scope

In scope:
- share dialogs for goals and tasks
- invitation list and accept/decline/revoke UX
- shared resource discovery UX for collaborators
- clear owner-only vs collaborator-visible states

Out of scope:
- folder sharing
- role matrices beyond edit collaboration
- chat or activity feeds

### Workstream G. Settings and Policy UX

Goal:
- expose user preferences required for MVP behavior

In scope:
- language selection
- notification preference state
- green and red priority decay policy editing
- account-facing timezone display if surfaced through `/api/me`

Out of scope:
- notification-center UI
- advanced profile management outside current contracts

### Workstream H. Frontend Quality and Release Hardening

Goal:
- keep the web client releasable while feature work lands

In scope:
- smoke coverage for auth and main flows
- localization regression checks
- conflict-state checks
- calendar and reschedule smoke coverage
- sharing permission-oriented UI checks

Out of scope:
- backend integration ownership
- Android verification ownership

## 5. Ownership Boundaries by Surface

| Surface | Frontend ownership boundary | Must not absorb |
| --- | --- | --- |
| Shell | app frame, route chrome, retro tokens, base components, modal system, global states | feature-specific DTO shaping, business-policy decisions |
| i18n | locale provider, translation structure, switch UX, key sync discipline | API enum translation on backend, third-language expansion |
| Auth | register/login/logout/session restore/protected routing | backend auth semantics, password recovery expansion |
| Planning | folders, goals, tasks CRUD screens, task editor, tags/links UI, recurrence/reminder forms after API stability | sharing logic, notification delivery UI, dependency engine |
| Calendar | simple day/week/month projection rendering, move UX, quick reschedule UI | scheduling-policy computation, advanced calendar product scope |
| Sharing | invite dialogs, invitation list actions, shared resource views | permission policy source of truth, folder sharing |
| Settings | language, notifications-enabled toggle, green/red priority policy forms | account security features outside frozen scope |

## 6. Implementation Task Decomposition

### Phase 0. Frontend Foundation Alignment

1. Confirm route map and screen inventory from frozen MVP journeys.
2. Confirm frontend DTO usage plan against current API contracts.
3. Lock shared UI primitives and directory boundaries before parallel feature work.

### Phase 1. Shell and i18n Base

4. Build app shell with public and protected layout frames.
5. Implement retro token set and base component primitives.
6. Add RU-first i18n infrastructure with `ru` source and mirrored `en`.
7. Implement persisted locale bootstrapping from settings or auth payload.
8. Add localization key parity validation for frontend changes.

### Phase 2. Auth and App Bootstrap

9. Implement register and login screens.
10. Implement auth session store, token lifecycle hooks, and protected route behavior.
11. Implement logout and expired-session recovery UX.

### Phase 3. Planning Core

12. Implement folders list/create/edit/archive interactions.
13. Implement goals list/detail/create/edit/archive interactions.
14. Implement tasks list/detail/create/edit/delete interactions.
15. Implement optimistic concurrency UX around `version` conflicts.
16. Implement tag selection and task-link editing if the API is available when this phase starts.

### Phase 4. Scheduling UI

17. Implement task date/time editing with planned/due fields.
18. Implement recurrence editor against the stable rule shape.
19. Implement reminder editor with anchor-aware validation messaging.
20. Implement simple calendar projections.
21. Implement move-task UX from calendar.
22. Implement quick reschedule preset UX for `30m`, `1h`, `3h`, `24h`.

### Phase 5. Sharing and Settings

23. Implement share-goal and share-task dialogs.
24. Implement invitation inbox actions for accept, decline, and revoke.
25. Implement shared resource entry points and collaborator-safe navigation.
26. Implement settings screen for language, notification preference, and green/red decay policies.

### Phase 6. Hardening

27. Add web smoke coverage for auth, planning CRUD, calendar, settings, and sharing.
28. Add localization regression checks for feature additions.
29. Validate empty, loading, error, forbidden, and conflict states across all MVP screens.

## 7. Sequential vs Parallel Execution

### Sequential Gates

The following must stay sequential:

1. freeze route map, shell boundaries, and DTO usage plan before splitting frontend feature work
2. shell and i18n foundation before broad screen implementation
3. auth bootstrapping before protected planning screens are considered done
4. planning CRUD before calendar, sharing, and settings are considered end-to-end ready
5. backend API stabilization for sharing and scheduling before final UI integration in those surfaces

### Safe Parallel Waves

#### Parallel Wave A

Can run together after Phase 0:

- shell layout and retro primitives
- i18n infrastructure
- auth screen scaffolding

#### Parallel Wave B

Can run together after shell primitives and auth bootstrap are usable:

- folders and goals screens
- task editor and task list flows
- settings screen shell

#### Parallel Wave C

Can run together after planning core DTOs are proven in UI:

- calendar rendering
- quick reschedule UX
- sharing dialogs and invitation views

#### Parallel Wave D

Can run together near release:

- smoke automation
- localization regression hardening
- UX consistency pass across loading/error/conflict states

## 8. Dependency Map on Backend DTO and API Stability

Frontend can start immediately on shell, i18n, and auth scaffolding, but the following surfaces depend on backend stability.

### Already Stable Enough to Unblock Early Frontend Work

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/me`
- `GET /api/me/settings`
- `PATCH /api/me/settings`
- folder, goal, and task CRUD endpoint set

### Contracts That Must Stay Stable for Planning UI

- `FolderDto`, `GoalDto`, and `TaskDto` field names
- optimistic locking via `version`
- enum values for `type`, `status`, and `language`
- soft-delete and archive semantics exposed through current DTOs

### Contracts That Must Stabilize Before Scheduling UI Is Closed

- `GET /api/calendar`
- `POST /api/tasks/{taskId}/move`
- `PUT /api/tasks/{taskId}/recurrence`
- `PUT /api/tasks/{taskId}/reminders`
- `POST /api/tasks/{taskId}/reschedule`

Frontend especially needs final backend confirmation for:

- whether reminder `PUT` fully replaces the rule set
- exact recurrence payload constraints the form must enforce
- error shape for missing `plannedTime` on quick reschedule
- whether move-task responses always include updated priority after decay evaluation

### Contracts That Must Stabilize Before Sharing UX Is Closed

- `POST /api/goals/{goalId}/share`
- `POST /api/tasks/{taskId}/share`
- `GET /api/shares/invitations`
- `POST /api/shares/invitations/{invitationId}/accept`
- `POST /api/shares/invitations/{invitationId}/decline`
- `POST /api/shares/invitations/{invitationId}/revoke`
- `GET /api/shares/resources`

Frontend needs one implementation clarification here:

- `/api/shares/resources` uses shared-resource discovery instead of folder ownership
- shared goals keep their persisted `folderId`; frontend must not assume a synthetic `virtual-shared` identifier
- if product presentation groups shared resources separately, that grouping is a client concern rather than an API contract

### Cross-Cutting API Guarantees Frontend Depends On

- consistent error envelope with `error.code`, `message`, `details`, and `traceId`
- `409 Conflict` for stale writes
- locale-independent enums in API payloads
- owner-only reminder delivery semantics for shared tasks in MVP

## 9. Recommended Frontend Subagent Count

Recommended count right now:
- `4` frontend subagents

Reasoning:

- fewer than `4` slows parallel delivery because shell, i18n/auth, planning, and advanced surfaces all compete for the same lead bandwidth
- more than `4` increases conflict risk in a single SPA codebase before the component and route boundaries exist

Recommended split:

1. `Shell + Retro Foundations`
   - owns app shell, layout primitives, retro tokens, shared components, and global UX states
2. `i18n + Auth`
   - owns localization plumbing, locale persistence, register/login/logout/session UX, and protected routes
3. `Planning`
   - owns folders, goals, tasks, task editor, optimistic conflict UX, and task-level form composition
4. `Calendar + Sharing + Settings`
   - owns calendar views, quick reschedule UX, share flows, invitation views, and settings integration after planning primitives exist

Scaling rule:

- do not split to a fifth frontend subagent unless the shell primitives are already merged and the calendar/sharing/settings route areas have physically separate write scopes

## 10. Recommended Task Order

Recommended execution order:

1. route map, component boundary, and DTO usage alignment
2. shell and retro primitives
3. RU-first i18n foundation
4. auth and session bootstrap
5. folders and goals flows
6. task CRUD and task editor
7. settings screen baseline
8. calendar read view
9. quick reschedule and move-task UX
10. sharing dialogs and shared-resource views
11. recurrence and reminder editors after API stability check
   - if they are deferred from the main Wave C slice, they must stay explicitly tracked as residual web MVP scope
12. smoke, localization, and conflict-state hardening

## 11. Retro UI Guardrails

The frontend team must preserve the visual direction already frozen in the handoff docs.

Required guardrails:

- dense layouts over oversized marketing-style spacing
- gray and blue system-like palette
- hard borders, bevel-like controls, and clear panel separation
- desktop-first information density
- functional forms and tables before decorative flourishes
- empty states and dialogs should feel like product tools, not lifestyle SaaS panels

Must avoid:

- glossy gradients that turn the app into generic modern SaaS
- glassmorphism, floating-card excess, and oversized rounded surfaces
- redesigning the product into mobile-first navigation
- introducing dark mode or theme expansion in MVP

## 12. RU-First i18n Guardrails

Localization is an engineering constraint, not a cleanup task.

Required guardrails:

- Russian copy is authored first
- English keys and values are added in the same change set
- no production component ships with hardcoded UI strings
- API enums stay untranslated in data models and are localized only in presentation
- feature namespaces should be stable and predictable
- layouts must be checked with Russian text first, then English overflow sanity-checked
- missing translation output must be treated as a defect, not acceptable fallback behavior

Operational rule:

- any frontend task that adds user-facing text is incomplete until both `ru` and `en` resources are synchronized

## 13. Risks and Mitigations

### Risk 1. DTO Drift During Parallel UI Work

Mitigation:
- keep API-adapter types centralized
- do not duplicate DTO assumptions across routes
- gate scheduling and sharing UI closure on backend contract confirmation

### Risk 2. Too Many Subagents Editing Shared App Scaffolding

Mitigation:
- merge shell, route, and component primitives first
- assign each subagent clear route or module ownership
- keep shared primitives under one owning subagent during the first wave

### Risk 3. RU/EN Key Drift

Mitigation:
- enforce localization parity check
- require both locales in every frontend feature change

### Risk 4. Scope Creep Through Polished but Non-MVP UI Work

Mitigation:
- treat retro shell as a constraint system, not a redesign exercise
- reject work that adds folder sharing, comments, attachment affordances, or non-MVP analytics

### Risk 5. Confusing Shared Resource Navigation

Mitigation:
- keep shared resources visually distinct from owned folders
- do not imply collaborator folder ownership anywhere in navigation

## 14. Explicit Out of Bounds

The following remain out of bounds for frontend MVP work:

- folder sharing
- comments, chat, and activity feeds
- file attachments
- offline mode
- web push or browser notification center
- advanced recurring-rule builders beyond documented contract shape
- live collaborative editing
- Android feature work
- dark mode, theming system expansion, or design-system gold plating

## 15. Definition of Done for Frontend MVP

Frontend MVP is done when:

- a user can authenticate and restore session in the web app
- a user can manage folders, goals, and tasks end to end
- a user can edit scheduling fields and use quick reschedule
- a user can view tasks in the simple calendar and move a task
- a user can manage sharing and invitation actions supported by the API
- a user can change language and policy settings in settings
- Russian and English are both complete and synchronized
- core web smoke coverage exists for critical user journeys
- conflict, forbidden, loading, empty, and validation states are implemented for the main screens
