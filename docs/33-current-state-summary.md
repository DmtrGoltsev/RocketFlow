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

Project root:

- `C:\Users\hp\Documents\Codex\RocketFlow`

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

- backend full test suite passes with `mvn test`
- backend container baseline now exists via `backend/Dockerfile` and `backend/.dockerignore`
- local `rocketflow-backend:latest` build is proven, and the backend container reaches `/actuator/health = UP` against a temporary `postgres:16` smoke runtime
- backend image registry target is now fixed to GHCR via the planned image family `ghcr.io/<owner>/rocketflow-backend`
- web production build passes with `npm run build`
- Android local `assembleDebug` passes with the installed Gradle distribution and workspace SDK setup
- backend `NotificationDeliveryIntegrationTest` passes after the logical-device upsert repair on `2026-04-27`
- Android `:app:assembleDebug` passes after the same repair follow-up on `2026-04-27`
- local end-to-end notification runtime proof `reminder -> push -> tap -> task open` passed on `2026-04-27` and was reconfirmed as `tap-open proven` by the controlled rerun on `2026-04-28`
- GitHub Actions `backend-verify` now covers `mvn test`, backend image build, and a temporary `postgres:16`-backed `/actuator/health` smoke
- GitHub Actions `backend-image-publish` now exists as the manual GHCR publish lane for backend images
- GitHub Actions `web-verify` and `android-verify` exist in the repository
- web and Android CI lanes remain build-only lanes

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
- Android build is green and covered by a build-only CI lane, and the local Android notification gate is now closed on the owned backend + emulator path
- notification code is now implemented and locally proven end-to-end on both backend and Android
- backend and Android now both support stable logical-device registration through `installationId`
- Android emulator smoke has now proven login, real Firebase token acquisition, post-repair device registration, push receipt, tap-open routing, and task detail open
- Android repair-wave code landed for Firebase bootstrap, session/UI cleanup, notification render stability, and RU-copy recovery
- the shortest repeatable autonomous verification path is documented in `docs/51-agent-notification-runtime-playbook.md`
- repo-backed owned-runtime startup now has a canonical entrypoint in `scripts/Start-NotificationSmokeBackend.ps1`
- repo-backed smoke-task provisioning and backend delivery evidence capture now have a canonical helper in `scripts/Invoke-NotificationSmokeTask.ps1`, and its repo-owned blocker is closed
- the historical `failed_backend_send` and apparent Firebase auth blockers were closed by the dependency-alignment fix documented in `docs/50-notification-runtime-clean-pass.md`
- the next active notification gate is now staging notification certification
- the next active backend delivery gate before staging certification is the first successful remote GHCR image publish
- no active subagents need to be resumed

Known non-blocking note:

- an Android keyboard UX note remains non-blocking and does not reopen the closed local notification gate
- Mockito/JDK dynamic agent warning exists in backend test runs but does not currently break the suite

## Recommended Next Step

The local notification gate is closed. The next active gates are:

- first successful remote publish of the backend image through GHCR
- then staging deployment/runtime wiring plus the notification certification path from `docs/45-notification-staging-smoke-runbook.md`
- keep `docs/51-agent-notification-runtime-playbook.md` as the fallback local re-verification path for future regressions, not as the active gate

If orchestration discipline is needed again, use:

- `docs/19-cross-lead-orchestration-plan.md`

as the baseline and create the next wave documents in sequence.
