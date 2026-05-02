# Wave B DevOps Staging And Secrets Boundary

## 1. Purpose

This document prepares the Wave B DevOps slice for:

- staging environment readiness
- secret separation between staging and production
- future notification rollout guardrails
- deployment and smoke-check boundaries for the current single-instance backend scheduler model

It is derived from:

- `docs/11-devops-baseline.md`
- `docs/18-devops-lead-decomposition.md`
- `docs/19-cross-lead-orchestration-plan.md`
- `docs/24-wave-a-devops-backend-ci.md`

This document does not expand MVP scope.

It does not introduce:

- new infrastructure requirements
- CI workflow changes
- architecture changes

## 2. Wave B Boundary

Wave B DevOps work is documentation and readiness work only.

Current hard constraints remain:

- one backend service
- one PostgreSQL database per environment
- one web deployment
- one in-process backend scheduler
- exactly one deployed backend instance in staging and production until scheduler claiming exists

Operational rule:

- notification rollout must not outrun explicit staging configuration, environment-separated secrets, and single-instance deployment enforcement

## 3. Staging Readiness Checklist

Staging is the first production-like verification environment.

Its purpose is:

- end-to-end backend and web validation
- release-candidate smoke checks
- future Android notification verification with non-production credentials

### Backend staging checklist

- [x] A repeatable backend container artifact family exists in the repo via `backend/Dockerfile`, and local image build proof is closed.
- [ ] Staging uses its own PostgreSQL database and credentials.
- [ ] Backend runtime configuration is injected from environment-specific values, not tracked files.
- [ ] The backend deployment path is documented and repeatable.
- [ ] Flyway migrations run successfully during deployment startup or an explicit pre-start step.
- [ ] `/actuator/health` is reachable after deployment.
- [ ] Backend logs are accessible to operators for startup, migration, auth, and reminder troubleshooting.
- [ ] `ROCKETFLOW_ALLOWED_ORIGINS` includes the staging web origin only.
- [ ] `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED` remains disabled until notification rollout preconditions in this document are satisfied.
- [ ] Deployment instructions explicitly confirm that only one backend instance is running.

### Web staging checklist

- [ ] A repeatable web build artifact exists.
- [ ] The staging web deployment serves a build that points to the staging backend API base URL.
- [ ] No production API base URL, tokens, or Firebase assets are baked into the staging web artifact.
- [ ] The hosting path for the web artifact is documented and repeatable.
- [ ] Cache invalidation or equivalent asset freshness steps are documented for redeploys.
- [ ] The staging web origin is aligned with backend CORS configuration.
- [ ] Smoke verification covers login plus core planning flows after deployment.

### Current staging blockers at the present repository stage

Historical blockers below are now outdated and kept only for traceability:

- the earlier web skeleton/build-command blocker is no longer the active repo gate; the remaining gap is the external staging deployment and runtime configuration shape
- device registration, backend notification delivery, and the Android local proof path are now closed on the repo-owned path
- local/internal non-production Firebase artifacts already exist, but they do not replace staging deployment facts or environment-separated staging secrets

Updated status:

- backend container baseline is now present and locally proven via `backend/Dockerfile` plus a temporary `postgres:16` container-backed `/actuator/health` smoke
- backend image publish destination is now fixed to GHCR through the planned image name family `ghcr.io/<github-owner>/rocketflow-backend`
- `.github/workflows/backend-image-publish.yml` now prepares a manual GHCR publish path that reruns backend verification before pushing tags
- active staging blocker is now the still-external first remote publish/deploy/runtime configuration shape, including actual package visibility, staging deployment facts, the staging API URL, operator-visible deployment facts, and environment-separated secrets wiring
- the next notification gate is staging notification certification, not another repo-local implementation proof

## 3.1 Selected backend image publish path

Chosen registry target:

- GitHub Container Registry (`GHCR`)
- image family: `ghcr.io/<github-owner>/rocketflow-backend`

Current repo-backed publish entrypoint:

- `.github/workflows/backend-image-publish.yml`

Current publish behavior:

- manual `workflow_dispatch` only, to avoid accidental package churn on every branch push
- always publishes a `sha-<12 chars>` tag for the exact commit
- optionally publishes an operator-provided extra tag such as `staging-20260428` or `v0.1.0`
- optionally publishes `latest` only when explicitly requested in the manual workflow input
- reruns backend `mvn test`, builds the image, and runs the temporary `postgres:16`-backed `/actuator/health` smoke before pushing

GitHub-side prerequisites before the first real publish:

- Actions on the repository must be allowed to write packages through `GITHUB_TOKEN`
- if the organization restricts package publishing, the repository or org policy must explicitly allow `packages: write`
- if staging infrastructure will pull a private GHCR package, deployment credentials need `read:packages`
- package visibility must be chosen deliberately; do not assume `public` by default

## 4. Secret Inventory And Separation Rules

The MVP secret boundary is strict:

- no secrets in tracked repository files
- no shared secret values between staging and production
- no production secrets used for staging smoke or debug work
- the smallest practical operator group owns production secret access

### Secret inventory

| Secret or sensitive asset | Primary consumer | Staging rule | Production rule | Boundary notes |
| --- | --- | --- | --- | --- |
| `ROCKETFLOW_DB_URL` | Backend runtime | Points only to staging PostgreSQL | Points only to production PostgreSQL | Treat as environment-specific configuration even if not confidential by itself. |
| `ROCKETFLOW_DB_USERNAME` | Backend runtime | Dedicated staging DB user | Dedicated production DB user | Do not reuse service accounts across environments. |
| `ROCKETFLOW_DB_PASSWORD` | Backend runtime | Unique staging value | Unique production value | Rotate independently per environment. |
| Auth signing secret or key material | Backend runtime | Separate staging value set | Separate production value set | Never let staging-issued tokens validate in production or the reverse. |
| `ROCKETFLOW_ALLOWED_ORIGINS` | Backend runtime | Staging web origin only | Production web origin only | Environment-specific and security-sensitive. |
| `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID` | Backend notification runtime | Staging Firebase project only | Production Firebase project only | Keep projects and credentials separate. |
| `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON` or `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH` | Backend notification runtime | Non-production service account only | Production service account only | Do not enable until notification rollout gates are met. |
| Android debug or internal Firebase config | Android internal builds | Allowed for staging/internal testing only | Not used for production release builds | Must not be confused with production mobile assets. |
| Android release signing credentials | Release management only | Not required for staging backend/web validation | Restricted production release asset | Keep out of repo and off general developer machines unless explicitly controlled. |
| Deployment platform credentials | Operators or CI/deployment runner | Separate staging access scope | Separate production access scope | Grant least privilege and avoid shared admin credentials. |

### Separation notes

- Staging and production must use different databases, different backend secret values, and different deployment credentials.
- Staging and production must use different Firebase projects or at minimum different credential sets that cannot cross-send into the other environment.
- Secret names may stay structurally similar across environments, but stored values must be different.
- Secret updates must be documented in operational notes before rollout, especially for auth and FCM material.
- Local developer values remain outside tracked files and must never be promoted as implicit staging defaults.
- Android Firebase config used for internal builds should also remain outside tracked files unless it is an explicitly non-secret placeholder configuration.

## 5. Notification Rollout Preconditions For Future FCM Enablement

FCM enablement is deferred until the backend, mobile, and staging boundaries are ready.

Before staging may enable `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`, all of the following must be true:

- device registration API exists and is verified
- backend reminder and notification delivery logic exists
- backend delivery logging is visible in staging
- staging uses separate Firebase project credentials
- Android internal build is configured against the staging backend
- Android internal build uses non-production Firebase configuration
- QA has a staging smoke path for register-device, trigger-reminder, receive-push, and open-task-from-notification
- a rollback action exists to disable FCM delivery quickly
- the backend deployment remains single-instance

Before production may enable FCM, all of the following must be true:

- staging notification smoke has passed using staging-only credentials
- duplicate-delivery risk under the current scheduler model is accepted by backend and QA leads
- production Firebase credentials are stored separately from staging credentials
- production Android release assets are confirmed to point at production services only
- operators can disable FCM delivery without redeploying unrelated application behavior if emergency mitigation is needed

Default boundary until these conditions are satisfied:

- keep `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED` off outside explicitly approved notification validation

## 6. Deployment And Smoke-Check Boundary

The current MVP architecture keeps reminder scheduling inside the backend runtime.

That creates a non-negotiable deployment boundary:

- deploy exactly one backend instance in staging
- deploy exactly one backend instance in production
- do not scale horizontally while scheduler claiming does not exist

Current mitigation already present in code:

- reminder polling now takes a PostgreSQL advisory transaction lock before each run
- this reduces overlap risk during rollouts or accidental double-start scenarios
- it does not replace deliberate single-instance deployment discipline

### Why this boundary exists

Without scheduler claiming, multiple backend instances can evaluate the same reminder window and create duplicate delivery attempts.

This affects:

- reminder-triggered push delivery
- any future scheduler-driven notification retries
- confidence in staging smoke outcomes

### Required deployment confirmation

Every staging or production backend rollout must explicitly confirm:

- one application instance is deployed
- one instance is receiving scheduler work
- no parallel old and new scheduler-bearing instances remain active after rollout completes

### Minimum backend smoke checks after each staging deployment

- deployment completed with the intended artifact
- migrations applied successfully
- `/actuator/health` returns healthy
- auth flow still works
- planning CRUD still works at a basic level
- logs show no configuration or migration failure
- if FCM is disabled, no notification delivery path is accidentally active
- if FCM is temporarily enabled for approved validation, only one backend instance is active during the full smoke run

### Minimum web smoke checks after each staging deployment

- web assets load from the intended staging host
- web requests target the staging backend API
- login succeeds against staging
- folder, goal, and task views load successfully
- at least one create or update planning action succeeds
- language and settings surfaces do not regress at a basic sanity level once those flows exist

## 7. Release Boundary Summary

Wave B closes the following operational decisions:

- staging is required before MVP production release
- staging and production credentials must be fully separated
- notification rollout stays off until staging-specific FCM and Android preconditions are met
- backend deployment remains single-instance while the scheduler is in-process and unclaimed
- smoke checks must validate both application health and configuration correctness, not only process startup

## 8. Out Of Bounds

This document does not authorize:

- adding new infrastructure platforms
- changing the scheduler architecture
- enabling multi-instance backend deployment
- enabling production FCM ahead of staging validation
- editing application code to satisfy these boundaries

The purpose here is to keep Wave B operationally safe while the MVP remains frozen.
