# RocketFlow Current State Summary

## Purpose

This file is the short handoff summary for starting a new thread without carrying the full historical conversation.

Use this together with:

- `README.md`
- `docs/19-cross-lead-orchestration-plan.md`
- `docs/43-new-chat-transition-instruction.md`
- `docs/46-android-notification-repair-summary.md`
- `docs/47-device-registration-logical-device-upsert-repair.md`
- `docs/50-notification-runtime-clean-pass.md`
- `docs/51-agent-notification-runtime-playbook.md`

## Project Status

Weekly Focus production checkpoint (`2026-08-10`):

- branch: `codex/weekly-focus-calendar-web-push`
- Calendar, Weekly Focus, server Focus cadence, Android FCM handling, and full Web Push lifecycle are implemented and tested in the feature working tree
- schema additions are Flyway `V19__weekly_focus.sql` and `V20__focus_notifications.sql`
- current evidence: backend 135 tests, web 54 tests, Android 77 tests, including final mobile accessibility, deep-link, tenant-scoping, and terminal-auth regression fixes; these are checkpoint counts, not permanent suite requirements
- web requires Node `>=22.12 <23`; CI runs tests, low-threshold dependency audit, and production build
- production backend and web are deployed from source SHA `910c061de4af9395d9bb682624bd966b2977a738` as release `sha-910c061de4af`; the later documentation commit is not the deployed source
- GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631) completed successfully; Flyway reached `V20` (`20/20`), local/public health passed, and the captured post-deploy evidence reported zero application errors, HTTP `5xx` responses, or service restarts
- backup `rocketflow_prod_20260810T045958Z.dump` was verified at `223191` bytes with SHA-256 `783590b8fa26f6d2882aab0a5cf670b483be5895fd80b6a915cd4c9946841b39`; `pg_restore -l` listed `238` entries and passed
- rollback workflow ID `330828165` is active and was not used for this rollout
- Focus cadence and Web Push remain disabled
- unsigned APK SHA-256 `1763de390dd587c686fe84152c521a2d92e65b747fb2689ec2076c0560c576d7` is not installable and has no Firebase configuration; Android is not deployed by this rollout
- authenticated production smoke remains an open evidence gap; health success is not a substitute for auth verification
- canonical feature delivery and rollout notes: `docs/66-weekly-focus-calendar-delivery.md`
- canonical rollout evidence: `docs/67-weekly-focus-production-rollout-evidence.md`

The older `MVP3` facts below remain historical production/baseline context and must not be read as the feature branch deployment state.

Project root:

- `C:\Users\style\Documents\Codex\RocketFlow`

Current checkpoint:

- Status timestamp: `2026-06-13`
- `MVP3` points at HEAD `21f95c1` (`Fix Android goal and task creation flow`)
- full HEAD: `21f95c15166b9c41de4279c4209d00da429688f3`
- `origin/MVP3` is synced with local `MVP3`
- `MVP2..MVP3` contains 23 commits
- DB was not re-inspected in this documentation pass; user confirmed DB works

Completed:

- planning and documentation baseline
- architecture and API contract baseline
- backend foundation
- auth and settings foundation
- folders / goals / tasks CRUD foundation
- `Wave A`
- `Wave B`
- `Wave C` documentation and stabilization baseline
- `Wave C.1` web scheduling authoring follow-up

Verified:

These items are last recorded evidence unless explicitly tied to HEAD `21f95c1`; fresh evidence is required for current HEAD gates that were not rerun in this pass.

- backend full test suite passes with `mvn test`
- backend container baseline now exists via `backend/Dockerfile` and `backend/.dockerignore`
- local `rocketflow-backend:latest` build is proven, and the backend container reaches `/actuator/health = UP` against a temporary `postgres:16` smoke runtime
- current HexCore production deploy truth is jar/systemd for backend plus web archive promotion through `.github/workflows/backend-hexcore-prod-deploy.yml`
- Docker/GHCR publishing remains an open gate; no GHCR publish workflow is present in `.github/workflows/`
- web production build passes with `npm run build`
- Android local `assembleDebug` passes with the installed Gradle distribution and workspace SDK setup
- backend `NotificationDeliveryIntegrationTest` passes after the logical-device upsert repair on `2026-04-27`
- Android `:app:assembleDebug` passes after the same repair follow-up on `2026-04-27`
- local end-to-end notification runtime proof `reminder -> push -> tap -> task open` passed on `2026-04-27` and was reconfirmed as `tap-open proven` by the controlled rerun on `2026-04-28`
- GitHub Actions `backend-verify` now covers `mvn test`, backend image build, and a temporary `postgres:16`-backed `/actuator/health` smoke
- GitHub Actions `web-verify` and `android-verify` exist in the repository
- GitHub Actions `android-verify` runs Android unit, build and lint gates: `:app:testDebugUnitTest`, `:app:assembleDebug`, `:app:lintDebug`
- web CI remains a build-only lane

## Most Important Docs

Core:

- `README.md`
- `docs/19-cross-lead-orchestration-plan.md`

Wave A:

- `docs/20-wave-a-backend-sharing.md`
- `docs/21-wave-a-backend-recurrence-reminders.md`
- `docs/22-wave-a-web-shell-foundation.md`
- `docs/23-wave-a-qa-backend-api-validation.md`
- `docs/24-wave-a-devops-backend-ci.md`
- `docs/25-wave-a-web-auth-i18n.md`

Reconciliation:

- `docs/26-cancelled-status-reconciliation.md`

Wave B:

- `docs/27-wave-b-backend-calendar-priority.md`
- `docs/28-wave-b-backend-notifications.md`
- `docs/29-wave-b-web-planning-flows.md`
- `docs/30-wave-b-qa-scheduling-validation.md`
- `docs/31-wave-b-devops-staging-secrets.md`

Wave C:

- `docs/32-wave-c-web-collaboration-settings.md`
- `docs/34-wave-c-android-companion-foundation.md`
- `docs/35-wave-c-android-auth-session.md`
- `docs/36-shared-resource-contract-reconciliation.md`
- `docs/37-wave-c-qa-validation.md`
- `docs/38-wave-c-devops-verification.md`
- `docs/39-wave-c1-web-scheduling-authoring.md`
- `docs/40-wave-c-android-browse-detail.md`
- `docs/41-wave-c1-web-scheduling-authoring-implementation.md`
- `docs/42-wave-c-android-notification-entry-foundation.md`
- `docs/43-new-chat-transition-instruction.md`
- `docs/44-android-sdk-assembledebug-verification.md`
- `docs/45-notification-staging-smoke-runbook.md`
- `docs/46-android-notification-repair-summary.md`
- `docs/47-device-registration-logical-device-upsert-repair.md`
- `docs/48-notification-smoke-backend-send-blocker.md`
- `docs/49-notification-smoke-firebase-auth-blocker.md`
- `docs/50-notification-runtime-clean-pass.md`
- `docs/51-agent-notification-runtime-playbook.md`

## Implemented Backend Scope

- auth
- user settings
- folders / goals / tasks CRUD
- sharing and access
- recurrence and reminders
- calendar projection
- move and quick reschedule
- priority decay
- device registration
- notification delivery
- Firebase Admin sender integration path

## Implemented Web Scope

- retro shell foundation
- RU-first i18n foundation
- auth foundation
- folders / goals / tasks planning flows
- calendar / sharing / settings routes
- recurrence and reminder authoring inside task create/edit
- partial-save warning path for recurrence/reminder follow-up failures

## Implemented Android Scope

- auth and session restore
- owned/shared browse flow
- read-only task detail
- device registration
- notification-open and deep-link routing
- Firebase token acquisition and token refresh persistence
- message receive handler and local notification rendering
- best-effort automatic device re-registration after token/session restore

## Important Product / Technical Rules

- Russian is primary, English must be kept in sync
- all meaningful stages are documented in `docs/`
- canonical task statuses are:
  - `todo`
  - `in_progress`
  - `done`
  - `cancelled`
- backend remains a modular monolith
- scheduler safety now has a PostgreSQL advisory transaction lock, but notification rollout should still be treated cautiously and not as horizontally hardened

## Current Quality State

- backend is the strongest verified surface
- backend CI now proves both the Maven suite and the tracked container artifact baseline
- web build is green and covered by a build-only CI lane, but still lightly tested
- Android build is green and covered by unit/build/lint CI gates, and the local Android notification gate is now closed on the owned backend + emulator path
- notification code is now implemented and locally proven end-to-end on both backend and Android
- backend and Android now both support stable logical-device registration through `installationId`
- Android emulator smoke has now proven login, real Firebase token acquisition, post-repair device registration, push receipt, tap-open routing, and task detail open
- Android repair-wave code landed for Firebase bootstrap, session/UI cleanup, notification render stability, and RU-copy recovery
- the shortest repeatable autonomous verification path is documented in `docs/51-agent-notification-runtime-playbook.md`
- repo-backed owned-runtime startup now has a canonical entrypoint in `scripts/Start-NotificationSmokeBackend.ps1`
- repo-backed smoke-task provisioning and backend delivery evidence capture now have a canonical helper in `scripts/Invoke-NotificationSmokeTask.ps1`, and its repo-owned blocker is closed
- the historical `failed_backend_send` and apparent Firebase auth blockers were closed by the dependency-alignment fix documented in `docs/50-notification-runtime-clean-pass.md`
- production backend/web rollout is recorded at release `sha-910c061de4af`, while Focus cadence and Web Push remain disabled
- production notification certification is still open; no provider delivery is claimed
- authenticated production smoke is still missing
- no active subagents need to be resumed

Known non-blocking note:

- an Android keyboard UX note remains non-blocking and does not reopen the closed local notification gate
- Mockito/JDK dynamic agent warning exists in backend test runs but does not currently break the suite

## Recommended Next Step

The backend/web production deploy is complete. The next active gates are:

- complete authenticated production smoke and attach sanitized evidence
- prepare an installable, correctly configured Android release artifact before claiming Android production delivery
- keep Focus cadence and Web Push disabled until controlled production provider smoke and notification certification pass
- keep `docs/51-agent-notification-runtime-playbook.md` as the fallback local re-verification path for future regressions, not as the active gate

If orchestration discipline is needed again, use:

- `docs/19-cross-lead-orchestration-plan.md`

as the baseline and create the next wave documents in sequence.
