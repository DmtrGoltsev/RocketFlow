# Wave A DevOps Backend CI

## Purpose

This document freezes the Wave A DevOps baseline for backend verification only.

It implements the current direction from:

- `docs/18-devops-lead-decomposition.md`
- `docs/19-cross-lead-orchestration-plan.md`

The scope here is intentionally narrow:

- one backend CI lane
- current backend environment-variable baseline
- current CI assumptions for the repository stage that exists now

It does not introduce new infrastructure or expand MVP scope.

Note for the current repository state:

- backend image publish is now handled separately by `.github/workflows/backend-image-publish.yml`
- `backend-verify` remains the verification gate and does not push artifacts remotely

## Implemented CI Gate

Repository CI now includes `.github/workflows/backend-verify.yml`.

Active gate:

- `backend-verify`

What it does:

- runs on `push`, `pull_request`, and manual dispatch
- checks out the repository
- sets up Temurin Java `21`
- uses Maven dependency caching through `actions/setup-java`
- runs `mvn test` from `backend/`
- builds the backend Docker image from `backend/Dockerfile`
- boots the image against a temporary `postgres:16` container and waits for `/actuator/health = UP`
- treats the full backend test suite as the required gate
- uploads Maven Surefire reports if the job fails
- uploads backend/postgres container logs if the Docker smoke fails

Why this is the main gate right now:

- the backend is the only implemented application lane in the repository today
- the existing Maven test suite already covers backend regressions and Flyway migration verification
- this keeps backend tests and schema safety ahead of any future web or Android automation

## Backend Verify Contract

For the current repository stage, `backend-verify` means:

- backend compilation must succeed as part of `mvn test`
- all Spring Boot tests must pass
- the Flyway migration chain must apply successfully in tests
- PostgreSQL-backed verification remains mandatory through the existing embedded PostgreSQL test path
- the backend image must build successfully from the tracked Dockerfile
- the built image must reach `/actuator/health = UP` against a temporary `postgres:16` runtime with notifications disabled

Current test coverage already includes:

- application startup coverage
- auth and settings integration coverage
- planning CRUD integration coverage
- Flyway migration verification

This matches the DevOps requirement that backend tests and migration verification stay the first hard CI gate.

## Current Environment Variable Baseline

### Runtime variables explicitly required by the backend application

The current non-local backend configuration directly requires these environment variables:

- `ROCKETFLOW_DB_URL`
- `ROCKETFLOW_DB_USERNAME`
- `ROCKETFLOW_DB_PASSWORD`

These are required by `backend/src/main/resources/application.yml`.

### Local-only defaults

`backend/src/main/resources/application-local.yml` keeps local development defaults for:

- `ROCKETFLOW_DB_URL`
- `ROCKETFLOW_DB_USERNAME`
- `ROCKETFLOW_DB_PASSWORD`

This preserves the existing rule that production-like defaults do not live in the main application config.

### Additional backend configuration already present

The backend also has auth TTL properties in code through Spring configuration properties:

- `rocketflow.auth.access-token-ttl`
- `rocketflow.auth.refresh-token-ttl`

At the current stage, these are not frozen in this Wave A doc as dedicated CI-managed `ROCKETFLOW_*` variables because the repo does not yet expose or document exact environment-variable names for them in application config.

### Not active yet

These are intentionally not part of the active backend CI baseline yet:

- FCM credentials and notification flags
- web environment variables
- Android signing or distribution variables
- staging and production deployment-secret inventories

Those remain later-phase DevOps work once the corresponding product lanes exist.

## CI Assumptions For The Current Backend Stage

Current CI assumptions:

- the repository backend lives in `backend/`
- Maven is the build tool
- Java `21` is the required CI runtime
- the backend test suite is self-contained for CI and does not require an external PostgreSQL service
- migration verification happens inside the Maven test suite via embedded PostgreSQL
- no backend secrets are required for the current CI test run
- `/actuator/health` remains the expected health endpoint for later deployment smoke checks
- Docker is available on the runner for backend image build and temporary container smoke
- the operational guardrail stays unchanged: deploy one backend instance only until scheduler claiming exists

## Deferred Notes

Deferred until later waves:

- separate `web-verify` workflow activation
- separate `android-verify` workflow activation
- staging deployment descriptors
- CI secret injection rules for notification and mobile release assets

If future lanes are added, they should be separate jobs or separate workflows and must not weaken `backend-verify` as the primary required gate.
