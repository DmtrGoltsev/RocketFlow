# DevOps Baseline

## 1. Purpose

This document defines the minimum reliable delivery baseline for the RocketFlow MVP.

The goal is not to overbuild infrastructure. The goal is to make parallel implementation safe, testable, and deployable.

This baseline covers:

- environments
- configuration model
- CI expectations
- artifact boundaries
- deployment shape
- secret handling
- operational guardrails

## 2. Delivery Principles

- keep the MVP operational model simple
- prefer repeatable pipelines over manual steps
- keep environment differences explicit
- avoid hidden local-only defaults in production paths
- make backend the first fully reproducible artifact
- treat localization validation and migration validation as first-class checks

## 3. Runtime Topology

The MVP runtime remains:

- one backend service
- one PostgreSQL database
- one web deployment
- one Android build/distribution track

Operational guardrail for the current architecture:

- run exactly one backend instance until DB-backed scheduler claiming is introduced

This avoids duplicate reminder evaluation and duplicate push delivery in the current design.

## 4. Environment Model

Recommended environments:

- `local`
- `test`
- `staging`
- `production`

### Local

Used for:

- feature development
- local backend boot
- local web development
- Android emulator/device integration

Characteristics:

- developer-provided secrets
- optional local PostgreSQL
- optional local web dev server
- no production credentials

### Test

Used for:

- CI verification
- migration checks
- backend integration tests

Characteristics:

- isolated ephemeral database where possible
- mocked or disabled external push delivery
- deterministic test data rules

### Staging

Used for:

- end-to-end verification before release
- Android notification checks with non-production app config
- localization and settings sanity verification

Characteristics:

- production-like configuration
- separate database
- separate FCM project or credentials set

### Production

Used for:

- live user traffic

Characteristics:

- production secrets only
- monitored backend instance
- protected database access

## 5. Configuration Baseline

Configuration should be environment-driven.

Minimum backend environment variables:

- `ROCKETFLOW_DB_URL`
- `ROCKETFLOW_DB_USERNAME`
- `ROCKETFLOW_DB_PASSWORD`
- `ROCKETFLOW_AUTH_ACCESS_TTL`
- `ROCKETFLOW_AUTH_REFRESH_TTL`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED`
- `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED`
- `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID`
- `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON` or secure file mount reference
- `ROCKETFLOW_ALLOWED_ORIGINS`
- `ROCKETFLOW_LOG_LEVEL`

Recommended future additions once notification delivery is implemented:

- `ROCKETFLOW_NOTIFICATION_BATCH_SIZE`
- `ROCKETFLOW_NOTIFICATION_POLL_DELAY`
- `ROCKETFLOW_BASE_URL`

Configuration rules:

- do not hardcode production-like defaults in the main application config
- keep local defaults in `application-local.yml` only
- document every new environment variable in the repository when introduced

## 6. Secret Handling

Secrets include:

- database password
- token signing or auth secret material if introduced later
- FCM credentials
- Android signing credentials

Rules:

- never commit secrets into the repository
- keep local developer secrets outside tracked files
- use environment variables or secure secret stores in CI and deployment
- keep staging and production secrets fully separated

Android-specific rule:

- release signing material must not be stored directly in the repo

## 7. CI Pipeline Baseline

The MVP CI should evolve in layers.

### Phase A. Current mandatory checks

- backend compile
- backend tests
- Flyway migration verification

### Phase B. Add when web skeleton exists

- frontend install
- frontend type check
- frontend build
- localization key sync validation

### Phase C. Add when Android skeleton exists

- Android assemble
- lint
- minimal smoke verification

### Phase D. Pre-release checks

- backend full test suite
- web smoke journeys
- localization switching verification
- Android notification sanity checks in staging

## 8. Suggested CI Jobs

### `backend-verify`

Responsibilities:

- build backend
- run `mvn test`
- fail on migration or integration regressions

### `web-verify`

Responsibilities:

- install dependencies
- build web client

Current repository state:

- this lane is currently build-only
- static checks and `ru/en` parity validation are still future follow-up work

### `android-verify`

Responsibilities:

- assemble Android debug build

Current repository state:

- this lane is currently build-only
- lint and selected Android tests are still future follow-up work

### `docs-consistency`

Responsibilities:

- optional lightweight check for mandatory docs presence
- future markdown linting if the project decides to add it

## 9. Deployment Shape

### Backend

Preferred MVP shape:

- containerized Spring Boot service or equivalent repeatable JVM deployment

Required deployment behaviors:

- run Flyway migrations on startup or in a pre-start step
- expose `/actuator/health`
- fail fast on invalid configuration

### Web

Preferred MVP shape:

- static build served behind a lightweight web host or reverse proxy

Requirements:

- environment-specific API base URL
- reliable cache invalidation strategy for deployments

### Android

Preferred MVP shape:

- internal distribution track first
- public release track after notification flow is stable

## 10. Observability Baseline

Minimum observability:

- structured backend logs
- health endpoint
- error visibility in staging and production logs

Recommended future additions once scheduling is implemented:

- reminder scan counters
- push delivery success/failure counters
- scheduler loop timing

## 11. Data and Migration Safety

Rules:

- every schema change goes through versioned migrations
- migrations must remain forward-only in normal delivery
- destructive schema changes require explicit review
- integration tests should continue validating the migration chain on PostgreSQL-compatible runtime

## 12. Team Working Agreement

Before parallel feature work expands:

- backend must stay green on `mvn test`
- every meaningful stage updates `docs/`
- new external integrations must add configuration notes here or in a linked document
- environment changes must be recorded before rollout

## 13. Current Status

Already true in the repository:

- backend has migration-based startup
- backend tests run against embedded PostgreSQL
- local defaults are split from the main application config
- backend health endpoint support exists through Spring Boot Actuator

Still to implement later:

- actual CI configuration files
- web pipeline
- Android pipeline
- staging deployment descriptors
- FCM credential management in deployment infrastructure

## 14. Handoff Note

This document is intentionally enough to let a DevOps lead turn the MVP baseline into executable pipeline tasks without redefining architecture or changing product scope.
