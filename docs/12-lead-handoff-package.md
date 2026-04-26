# Lead Handoff Package

## 1. Purpose

This document marks the point where the RocketFlow project is ready to be handed to competency leads for decomposition into implementation workstreams and subagent-sized tasks.

The intent of this handoff is:

- preserve the already frozen product and architecture decisions
- avoid re-opening settled MVP scope
- let each lead split work inside their own area safely
- keep cross-team dependencies explicit before parallel execution

## 2. What Is Already Frozen

The following are already defined and should be treated as baseline unless a lead finds a serious contradiction:

- primary MVP scope
- domain rules
- architecture boundaries
- API direction
- QA baseline
- DevOps baseline
- backend foundation
- auth and settings foundation
- folders / goals / tasks CRUD foundation

Reference set:

- `docs/01-primary-mvp-plan.md`
- `docs/02-execution-backlog.md`
- `docs/03-domain-specification.md`
- `docs/04-architecture-blueprint.md`
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`
- `docs/07-fresh-architecture-review.md`
- `docs/08-backend-foundation.md`
- `docs/09-auth-settings-foundation.md`
- `docs/10-planning-crud-foundation.md`
- `docs/11-devops-baseline.md`

## 3. Current Implementation Status

Completed in code:

- Spring Boot backend skeleton
- PostgreSQL-backed migration chain
- auth endpoints
- user settings endpoints
- owner-scoped folder CRUD
- owner-scoped goal CRUD
- owner-scoped task CRUD
- owner-scoped tag CRUD baseline
- integration tests for auth/settings and planning CRUD

Still open:

- sharing foundation
- recurrence and reminder logic
- quick reschedule and reschedule history
- priority decay application
- device registration
- push delivery integration
- web client
- Android companion client
- pipeline implementation
- release hardening

## 4. Exact Point of Handoff

The project is now at the boundary between:

- centralized planning and architecture ownership
- competency-led decomposition and parallel delivery design

This means the next action should not be ad hoc coding across all areas by one generalist thread.

The next action should be:

- hand the current package to competency leads
- ask each lead to propose decomposition inside their slice
- ask each lead to recommend how many implementation subagents are needed
- ask each lead to identify risky dependency edges before execution begins

## 5. Leads To Engage

The recommended lead roles are:

- CTO / Solution Architect lead
- Backend lead
- Frontend lead
- Mobile lead
- QA lead
- DevOps lead

Optional additional review role if needed:

- Security lead

## 6. Questions Each Lead Must Answer

Each lead should answer the following inside their area:

1. What is the cleanest implementation breakdown for this slice?
2. Which tasks are sequential and which can run in parallel?
3. What are the main technical risks?
4. What interfaces or contracts must stay stable?
5. How many subagents are appropriate for this slice right now?
6. What should be the ownership boundary of each subagent?
7. What should be explicitly out of bounds to avoid scope creep?

## 7. Required Inputs For All Leads

Every lead should receive:

- the repository path
- the current docs baseline
- the implemented backend status
- the execution backlog
- the rule that all decisions must be documented back into `docs/`

Shared instruction:

- do not redesign the product from scratch
- preserve the frozen MVP decisions unless a contradiction is found
- propose decomposition, not philosophical alternatives
- keep tasks small enough for safe parallel execution
- surface hidden dependency edges early

## 8. Recommended Handoff Scope By Lead

### CTO / Solution Architect Lead

Focus:

- validate that the project is ready for multi-lead parallelization
- confirm the sequencing between backend, web, Android, QA, and DevOps
- identify any remaining architectural blockers
- recommend the orchestration pattern for subagents

Expected output:

- go/no-go for parallelization
- cross-stream dependency map
- escalation notes if any blocking contradictions remain

### Backend Lead

Focus:

- split the remaining backend work into clean vertical slices
- propose decomposition for sharing, scheduling, notifications, and calendar-related APIs

Expected output:

- backend work packages
- recommended number of backend subagents
- ownership map by module/file area

### Frontend Lead

Focus:

- split the web MVP into shell, i18n, auth flows, planning screens, settings, and collaboration UI

Expected output:

- frontend work packages
- dependency map on backend DTO stability
- recommended number of frontend subagents

### Mobile Lead

Focus:

- define the Android companion implementation slices
- keep scope constrained to companion responsibilities

Expected output:

- Android work packages
- push integration dependencies
- recommended number of mobile subagents

### QA Lead

Focus:

- turn the current QA strategy into implementation-time validation tasks
- propose where QA can run in parallel with active development

Expected output:

- QA checkpoints by wave
- high-risk verification packs
- recommended number of QA-oriented subagents if useful

### DevOps Lead

Focus:

- turn the DevOps baseline into executable pipeline and environment tasks
- identify the minimum reliable CI/CD path for the next implementation waves

Expected output:

- pipeline work packages
- environment setup tasks
- secret and deployment readiness checklist

## 9. Recommended Decomposition Guardrails

For all leads:

- prefer disjoint write scopes
- avoid multiple subagents editing the same files at once
- keep shared contract changes centralized
- treat migration files, API contracts, and i18n keys as high-coordination surfaces
- do not let Android expand into web-parity scope
- do not split scheduling logic into arbitrary fragments without a clear owner

## 10. Suggested First Delegation Wave

Once leads approve decomposition, the most sensible first parallel wave is:

- Backend lead decomposes `sharing`
- Backend lead decomposes `scheduling engine`
- Frontend lead decomposes `web retro shell + i18n foundation`
- DevOps lead decomposes `pipeline baseline`
- QA lead decomposes `implementation-time verification checkpoints`

Android lead can start after:

- auth and task DTO stability are confirmed for the remaining MVP flows

## 11. Expected Deliverables From Leads

Each lead should return:

- recommended workstreams
- numbered task list
- dependencies between tasks
- proposed subagent count
- ownership boundary per subagent
- expected documentation updates
- top risks and mitigation notes

## 12. Stop Rule

At this point the repository is prepared enough that the next coordination step should be lead-led decomposition rather than additional broad foundation work by the current thread.

This is the intentional stopping point before multi-lead task delegation.
