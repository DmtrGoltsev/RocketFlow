# Cross-Lead Orchestration Plan

## 1. Purpose

This document synthesizes the lead decomposition outputs into one executable orchestration plan.

It answers:

- whether RocketFlow is ready for multi-lead execution
- how to phase the implementation streams safely
- how many implementation subagents to activate by wave
- which coordination surfaces must remain single-owner
- what must happen before the next delegation wave begins

This is the orchestration layer above:

- `docs/13-cto-lead-decomposition.md`
- `docs/14-backend-lead-decomposition.md`
- `docs/15-frontend-lead-decomposition.md`
- `docs/16-mobile-lead-decomposition.md`
- `docs/17-qa-lead-decomposition.md`
- `docs/18-devops-lead-decomposition.md`

## 2. Executive Verdict

Verdict:

- `GO` for controlled parallel execution

Reason:

- the project has a stable enough planning baseline
- backend foundation exists
- competency leads independently converged on a workable decomposition
- there are no architectural stop-sign blockers

Important nuance:

- the project is ready for parallel execution
- the project is not ready for uncontrolled full fan-out across every area at once

The implementation should scale in waves, not in one burst.

## 3. Lead Consensus Summary

Consensus points across lead outputs:

- sharing, permissions, scheduling, and notifications are the highest-risk backend surfaces
- shell, retro primitives, RU-first i18n, and auth can start on web immediately
- Android should remain companion-only and should not be started as a full-parity client
- QA should validate each wave instead of waiting for the assembled MVP
- DevOps must establish CI, environment, and secret discipline before notifications and staging rollout

Shared coordination warning:

- multiple leads independently flagged the same task-status drift:
  - frozen domain/API docs include `cancelled`
  - the current planning CRUD foundation note lists only `todo`, `in_progress`, and `done`

Orchestrator decision:

- treat this as documentation drift, not product ambiguity
- the frozen task status set remains:
  - `todo`
  - `in_progress`
  - `done`
  - `cancelled`

This must be reconciled once in the next backend integration pass before broader client work assumes the final enum.

## 4. Single-Owner Coordination Surfaces

The following surfaces must have one active owner at a time:

- `docs/05-api-contracts.md`
- backend Flyway migration files
- centralized permission service and its policy semantics
- scheduling service boundaries
- notification payload contract
- shared task DTO shapes
- `ru/en` localization key sets

Operational guardrails:

- run one backend instance only until scheduler claiming exists
- do not split migrations across concurrent subagents without lead integration control
- do not let multiple streams mutate shared DTOs independently

## 5. Recommended Orchestration Model

### Lead Layer

Leads remain responsible for:

- queue ownership
- contract review
- merge sequencing for high-coordination surfaces
- conflict escalation
- documentation sync when scope interpretation changes

### Implementation Layer

Implementation subagents work in bounded write scopes with:

- one clear module or route area
- explicit out-of-bounds rules
- no ownership overlap on migrations, shared DTOs, or localization files

### QA Layer

QA runs continuously by wave:

- backend/API validation starts immediately
- web validation starts once shell exists
- scheduling and Android validation start as those surfaces become executable

### DevOps Layer

DevOps runs as an enabling stream, not as an afterthought:

- backend CI first
- staging/environment definition second
- web and Android verification lanes when those clients exist
- notification rollout guardrails before push is enabled

## 6. Recommended Wave-Based Activation

### Wave A. Start Now

Activate these implementation subagents now:

- Backend:
  - sharing and access
  - recurrence and reminders
- Frontend:
  - shell and retro foundations
  - i18n and auth
- QA:
  - backend/API validation
- DevOps:
  - backend CI and environment baseline

Why now:

- these streams are either already unblocked or depend only on frozen contracts plus existing backend foundation

Recommended active count in Wave A:

- backend `2`
- frontend `2`
- QA `1`
- DevOps `1`

Total active implementation subagents:

- `6`

### Wave B. Start After Wave A Gates

Wave A gates:

- task-status drift is reconciled once
- sharing contract is stable enough for clients
- recurrence and reminder DTO shapes are stable enough for clients
- backend CI baseline is green and repeatable
- frontend shell and i18n foundations are merged

Then activate:

- Backend:
  - calendar, move, quick reschedule, priority decay
  - notifications and device registration
- Frontend:
  - planning flows
- QA:
  - scheduling validation pack
- DevOps:
  - staging shape and secret boundary work

Recommended additional count in Wave B:

- backend `2`
- frontend `1`
- QA `1`
- DevOps `1`

Total active implementation subagents in Wave B:

- `11` cumulative if Wave A agents remain active

### Wave C. Start After Backend Scheduling And Sharing Stabilize

Wave B gates:

- calendar, move, quick reschedule, and priority decay APIs are stable
- device registration contract exists
- notification payload minimum contract is stable
- planning web routes are using stable DTOs

Then activate:

- Frontend:
  - calendar, sharing, and settings integration
- Mobile:
  - app foundation and session
  - browse/detail/push flow
- QA:
  - web/localization validation
  - Android plus notification validation
- DevOps:
  - web pipeline and Android pipeline lanes

Recommended additional count in Wave C:

- frontend `1`
- mobile `2`
- QA `1`
- DevOps `1`

### Wave D. Hardening And Release

Focus:

- cross-stream defect burn-down
- full regression
- staging validation
- release-readiness checklist closure

No new implementation subagents should be added here unless they are narrow defect-fix workers.

## 7. Full Recommended Capacity By Competency

Steady-state maximum once all streams are active:

- Backend: `4` implementation subagents plus backend lead integrator
- Frontend: `4` implementation subagents plus frontend lead
- Mobile: `2` implementation subagents plus mobile lead
- QA: `3` QA-oriented subagents plus QA lead
- DevOps: `3` implementation subagents plus DevOps lead

Important orchestration note:

- this is the maximum recommended decomposition
- it is not the recommended day-one activation level

## 8. Immediate Next Delegation Package

The first delegation wave should be created from these lead documents:

- [docs/13-cto-lead-decomposition.md](C:/Users/hp/Documents/Codex/RocketFlow/docs/13-cto-lead-decomposition.md)
- [docs/14-backend-lead-decomposition.md](C:/Users/hp/Documents/Codex/RocketFlow/docs/14-backend-lead-decomposition.md)
- [docs/15-frontend-lead-decomposition.md](C:/Users/hp/Documents/Codex/RocketFlow/docs/15-frontend-lead-decomposition.md)
- [docs/17-qa-lead-decomposition.md](C:/Users/hp/Documents/Codex/RocketFlow/docs/17-qa-lead-decomposition.md)
- [docs/18-devops-lead-decomposition.md](C:/Users/hp/Documents/Codex/RocketFlow/docs/18-devops-lead-decomposition.md)

Wave A implementation package:

1. Backend subagent `A1`
- ownership:
  - sharing and access
- goal:
  - invitations, shares, centralized permission service, shared resource discovery

2. Backend subagent `A2`
- ownership:
  - recurrence and reminders
- goal:
  - recurrence rules, reminder rules, validation, DTO expansion

3. Frontend subagent `F1`
- ownership:
  - shell and retro foundations
- goal:
  - route shell, layout frame, retro primitives, base global states

4. Frontend subagent `F2`
- ownership:
  - i18n and auth
- goal:
  - RU-first localization, EN parity, locale persistence, auth/session UX

5. QA subagent `Q1`
- ownership:
  - backend/API validation
- goal:
  - executable checks for foundation, planning CRUD, and early contract drift

6. DevOps subagent `D1`
- ownership:
  - backend CI and env baseline
- goal:
  - backend verify lane, env var map, secret inventory baseline

## 9. Key Risks To Track Across Waves

Cross-wave risks:

- permission logic duplicated outside the central policy layer
- scheduling logic fragmented across too many owners
- migration numbering conflicts
- DTO drift across backend, web, and Android
- localization drift between `ru` and `en`
- Android starting too deep before notification contracts stabilize
- notification rollout outrunning environment and secret readiness

Risk handling rule:

- if a task touches one of the single-owner coordination surfaces, it must be routed through the relevant lead integrator

## 10. Coordination Cadence

Recommended cadence:

- daily lead sync:
  - blockers
  - ownership collisions
  - contract changes
- twice-weekly contract review:
  - APIs
  - migrations
  - permission model
  - scheduling semantics
  - notification payloads
- weekly readiness review:
  - CTO
  - QA
  - DevOps

Async status format for each lead:

- `done`
- `next`
- `blocked`

## 11. Stop Rule For The Orchestrator

At this point, broad foundation planning is complete.

The orchestrator should now:

- delegate Wave A implementation work using the lead decomposition docs
- keep ownership disjoint
- review returned work against the coordination surfaces
- only then expand into Wave B

The orchestrator should not:

- reopen MVP scope
- start Android feature parity work
- launch all maximum-count subagents at once
- allow contract and migration ownership to diffuse
