# DevOps Lead Decomposition

## 1. Purpose

This document turns the current RocketFlow DevOps baseline into an execution-ready decomposition for the next implementation waves.

It stays within the already frozen MVP:

- one backend service
- one PostgreSQL database
- one web deployment
- one Android companion distribution track
- one in-process scheduler inside the backend runtime

This decomposition does not reopen product scope. It only breaks delivery infrastructure into safe workstreams, dependency order, and operational boundaries.

## 2. Current Baseline Assumed

Based on the current repository handoff package, the following are treated as already established:

- backend foundation exists
- PostgreSQL-backed migration chain exists
- auth/settings and owner-scoped planning CRUD foundation exist
- DevOps baseline is documented
- web, Android, sharing, scheduling, and push delivery are still not fully implemented

Operational guardrails already frozen:

- run exactly one backend instance until DB-backed scheduler claiming exists
- keep production-like defaults out of main application config
- validate migrations as part of backend verification
- keep localization validation and migration validation as first-class CI checks

## 3. DevOps Mission For The Next Waves

The DevOps slice has four goals:

1. make backend, web, and Android verification repeatable
2. make environment differences explicit and documented
3. make deployments safe enough for staging and MVP production
4. prevent notification and scheduler rollout from outrunning operational safety

## 4. Recommended DevOps Workstreams

### Workstream A. CI Pipeline Foundation

Scope:

- repository-level CI structure
- backend verify workflow
- future web verify workflow shell
- future Android verify workflow shell
- docs and localization validation hooks where required

Main outputs:

- backend verification pipeline
- web verification pipeline contract
- Android verification pipeline contract
- artifact and cache strategy notes

### Workstream B. Environment and Deployment Foundation

Scope:

- environment inventory for `local`, `test`, `staging`, `production`
- deployment shape for backend and web
- staging topology decisions
- release path definition for Android internal distribution
- operational runbook skeleton

Main outputs:

- environment variable matrix
- deployment descriptors or deployment instructions
- staging and production rollout checklist
- health-check and smoke-check expectations

### Workstream C. Secret and Release Safety

Scope:

- secret classification
- CI secret injection rules
- staging vs production credential separation
- Android signing boundary
- FCM credential handling boundary

Main outputs:

- secret ownership matrix
- secret rotation/update procedure notes
- release gating checklist for production-sensitive assets

## 5. Sequential Vs Parallel Task Breakdown

### Sequential Core Path

These tasks should happen in order because later tasks depend on them:

1. freeze the environment variable map and deployment assumptions from the current docs
2. implement backend CI verification as the first required green pipeline
3. define staging environment shape for backend + PostgreSQL + web hosting
4. define secret injection and secret separation rules for CI, staging, and production
5. add web CI/build validation once the web skeleton exists
6. add Android CI/build validation once the Android skeleton exists
7. add staging release checks for notification delivery before push-enabled builds are promoted

### Parallelizable Tasks

These can run in parallel once the sequential prerequisites above are stable:

- backend pipeline implementation and deployment runbook drafting
- web pipeline scaffolding and localization validation wiring
- Android pipeline scaffolding and signing/release boundary documentation
- staging smoke-check scripting and release checklist drafting
- secret inventory documentation and CI secret-store integration notes

### Tasks That Must Wait On Other Leads

- final web build/deploy wiring waits for frontend skeleton and build commands
- final Android pipeline waits for mobile project structure and signing approach
- final notification delivery rollout waits for backend notification implementation and FCM integration details
- final production release checklist waits for QA release criteria to mature

## 6. Recommended DevOps Subagent Count

Recommended count now:

- `3` DevOps subagents

Reasoning:

- the DevOps slice is wide enough to benefit from parallelization
- the files and concerns can be separated cleanly
- more than three would create coordination overhead without enough implementation surface yet

Recommended ownership split:

### Subagent 1. CI and Verification

Owns:

- backend CI workflow
- web CI workflow shell
- Android CI workflow shell
- caching, build, and test job structure

Must coordinate with:

- backend lead for verify commands
- frontend lead for web build/test commands
- mobile lead for Android build/lint commands
- QA lead for gating checks

### Subagent 2. Environments and Deployment

Owns:

- environment inventory
- staging topology
- backend deployment path
- web deployment path
- smoke-check expectations

Must coordinate with:

- backend lead for runtime configuration
- frontend lead for API base URL handling
- QA lead for staging readiness checks

### Subagent 3. Secrets and Release Controls

Owns:

- secret classification
- CI secret boundaries
- FCM credential boundary
- Android signing boundary
- staging/production promotion guardrails

Must coordinate with:

- backend lead for auth secret material
- mobile lead for signing and Firebase app config
- whoever owns deployment infrastructure access

## 7. Deployment Boundaries

### Backend Boundary

DevOps owns:

- repeatable build and deployment path
- runtime configuration injection
- health-check exposure validation
- startup migration execution policy
- single-instance scheduler guardrail in deployment docs

Backend lead owns:

- application behavior
- migration content
- auth, scheduling, and notification logic

### Web Boundary

DevOps owns:

- build artifact publication path
- environment-specific configuration delivery
- hosting/reverse-proxy deployment procedure
- cache invalidation/redeployment guidance

Frontend lead owns:

- web app code
- localization files
- runtime behavior

### Android Boundary

DevOps owns:

- CI assembly/lint path
- internal distribution path
- release signing boundary handling
- environment-specific app configuration delivery process

Mobile lead owns:

- Android application code
- push handling logic
- notification open-flow behavior

### Notification Delivery Boundary

DevOps owns:

- FCM credential handling
- environment separation for test vs production Firebase assets
- rollout and smoke-check procedure
- operational logging/monitoring expectations

Backend lead owns:

- notification scheduling logic
- idempotency behavior
- delivery persistence and retry behavior

## 8. Secret-Management Boundaries

Secrets in MVP:

- database credentials
- auth signing secret or key material once introduced
- FCM service credentials
- Android signing credentials
- deployment platform credentials

Rules:

- no secrets in tracked repository files
- no shared secret values between staging and production
- no Android release signing material on developer machines unless explicitly required and controlled
- FCM credentials for staging and production must be separate
- CI must inject secrets through a secure secret store or equivalent protected mechanism

Handling boundary by secret type:

- database and backend auth secrets belong to backend runtime operations
- FCM credentials belong to notification delivery operations and mobile release coordination
- Android signing credentials belong to release management only
- deployment platform credentials belong to the smallest possible operator/admin group

## 9. Pipeline Task List

### Phase 1. Immediate DevOps Tasks

- document the authoritative environment variable map
- implement `backend-verify`
- ensure PostgreSQL-backed migration verification is mandatory in CI
- publish backend artifact expectations
- define CI failure ownership and response path

### Phase 2. When Web Skeleton Exists

- implement `web-verify`
- enforce frontend build success in CI
- enforce localization key parity validation
- define web artifact publication and staging deployment steps

### Phase 3. When Android Skeleton Exists

- implement `android-verify`
- define debug/internal distribution artifact handling
- separate debug/test Firebase config from production config
- document signing and release boundaries

### Phase 4. Pre-Notification Rollout

- add staging smoke path for device registration and reminder-triggered push
- document FCM credential provisioning and validation
- define rollback path if reminder delivery misbehaves
- require single-backend-instance deployment confirmation before enabling scheduler-driven notification jobs

## 10. Staging Readiness Blockers

Staging is not ready until all of the following exist:

- repeatable backend deployment path
- isolated staging PostgreSQL instance
- CI path that produces a tested backend artifact
- environment-specific secret injection path
- web deployment path with staging API base URL
- staging health and smoke checks
- documented rollback/redeploy procedure

Additional blockers before staging can validate notifications:

- separate staging FCM credentials
- Android internal build configured for staging backend
- backend notification logging visible in staging
- QA-owned notification verification steps

## 11. Production Readiness Blockers

Production is blocked until all of the following are true:

- staging has already validated the full backend + web flow
- migrations are proven repeatable and forward-only in delivery
- auth secrets are provisioned securely outside the repo
- production DB access is restricted to backend infrastructure/operators
- backend health monitoring and log access exist
- rollback or restore procedure is documented
- release ownership is explicit for backend, web, and Android

Additional blockers before production push delivery:

- notification flow has passed staging smoke and regression checks
- FCM production credentials are stored separately from staging
- single-instance backend deployment is enforced
- duplicate delivery risk is judged acceptable by backend + QA leads

## 12. What Must Exist Before Web Can Ship Safely

- backend auth and planning APIs are deployed in a stable environment
- web CI verifies build and localization parity
- environment-specific API base URL handling is implemented
- staging web deployment exists
- smoke checks cover login and core planning flows
- release process includes cache invalidation or equivalent client asset freshness handling

## 13. What Must Exist Before Android Can Ship Safely

- stable auth and task APIs
- Android CI can assemble and lint the app
- internal distribution track exists
- signing boundary is documented and secured
- environment-specific backend and Firebase configuration exists
- staging or internal test path proves login and task detail flows
- release process includes app configuration verification for the target environment

## 14. What Must Exist Before Notification Delivery Can Ship Safely

- backend reminder and notification logic is implemented and tested
- device registration endpoint exists and is verified
- single-instance backend deployment is enforced
- separate staging and production FCM credentials exist
- Android app can receive and open task reminder notifications
- delivery logging is visible in staging
- duplicate-delivery and failure-handling behavior are validated in staging
- rollback switch or disable flag for FCM delivery exists

## 15. Cross-Team Dependency Map

DevOps depends on backend for:

- final runtime config keys
- health endpoint behavior
- migration policy
- notification runtime flags

DevOps depends on frontend for:

- build command
- localization validation command
- runtime config injection pattern

DevOps depends on mobile for:

- Gradle build/lint/test commands
- Firebase config requirements
- internal distribution artifact format

DevOps depends on QA for:

- smoke gate definition
- staging verification checklist
- release blocker escalation rules

## 16. Recommended Execution Order

Recommended order for the DevOps slice:

1. finalize DevOps decomposition
2. implement backend CI verification
3. freeze environment variable and secret inventory
4. define staging deployment shape
5. add web CI/deploy path when the web skeleton is ready
6. add Android CI/internal distribution path when the Android skeleton is ready
7. add notification-delivery operational guardrails before push rollout
8. assemble staging and production readiness checklist with QA

## 17. Out Of Bounds

The following are explicitly out of bounds for this DevOps decomposition:

- redesigning the app architecture
- introducing microservices
- introducing Redis, a message broker, or a separate scheduler worker without a new architecture decision
- changing MVP product scope
- redefining notification business semantics
- taking ownership of application feature code from backend, frontend, or mobile leads

## 18. Delivery Verdict

The DevOps slice is ready for parallel execution with three subagents once ownership is kept disjoint.

Best immediate DevOps focus:

- backend CI as the first hard gate
- environment and secret inventory as the first stability layer
- staging deployment shape before web, Android, and push delivery mature further

The main safety principle is simple:

- do not let web, Android, or notification rollout outrun repeatable verification, explicit configuration, and environment-separated secrets
