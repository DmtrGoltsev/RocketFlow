# RocketFlow

Project documentation lives in [`docs/`](C:/Users/hp/Documents/Codex/RocketFlow/docs).

Core documents:
- `docs/01-primary-mvp-plan.md` - primary product, MVP, and architecture plan
- `docs/02-execution-backlog.md` - execution waves, backlog, and subagent task briefs
- `docs/03-domain-specification.md` - frozen domain model and business invariants
- `docs/04-architecture-blueprint.md` - target MVP architecture and module boundaries
- `docs/05-api-contracts.md` - REST and DTO contracts for MVP
- `docs/06-qa-strategy.md` - quality, regression, and release strategy
- `docs/07-fresh-architecture-review.md` - independent review notes before implementation foundation
- `docs/08-backend-foundation.md` - backend skeleton and migration setup stage notes
- `docs/09-auth-settings-foundation.md` - implemented auth and user settings foundation
- `docs/10-planning-crud-foundation.md` - implemented folders, goals, tasks, and tags CRUD foundation
- `docs/11-devops-baseline.md` - MVP delivery pipeline, environments, and secret handling baseline
- `docs/12-lead-handoff-package.md` - prepared handoff package for competency leads and agent orchestration
- `docs/13-cto-lead-decomposition.md` - CTO go/no-go, dependency map, and cross-stream execution guidance
- `docs/14-backend-lead-decomposition.md` - backend workstreams, subagent split, and ownership boundaries
- `docs/15-frontend-lead-decomposition.md` - web MVP workstreams, UI boundaries, and frontend decomposition
- `docs/16-mobile-lead-decomposition.md` - Android companion scope, dependencies, and mobile decomposition
- `docs/17-qa-lead-decomposition.md` - QA checkpoints, validation packs, and release gates
- `docs/18-devops-lead-decomposition.md` - CI/CD, environment, and secret-management decomposition
- `docs/19-cross-lead-orchestration-plan.md` - unified execution and subagent orchestration plan after lead review
- `docs/20-wave-a-backend-sharing.md` - implemented Wave A backend sharing and access foundation
- `docs/21-wave-a-backend-recurrence-reminders.md` - implemented Wave A backend recurrence and reminders foundation
- `docs/22-wave-a-web-shell-foundation.md` - implemented Wave A web shell and retro foundation
- `docs/23-wave-a-qa-backend-api-validation.md` - prepared Wave A backend and API validation packs
- `docs/24-wave-a-devops-backend-ci.md` - implemented Wave A backend CI and environment baseline
- `docs/25-wave-a-web-auth-i18n.md` - implemented Wave A web auth and RU-first i18n foundation
- `docs/26-cancelled-status-reconciliation.md` - reconciled task `cancelled` status across current backend docs
- `docs/32-wave-c-web-collaboration-settings.md` - Wave C web calendar, sharing, and settings integration
- `docs/34-wave-c-android-companion-foundation.md` - Wave C Android companion foundation baseline
- `docs/35-wave-c-android-auth-session.md` - Wave C Android auth and session baseline
- `docs/36-shared-resource-contract-reconciliation.md` - reconciled shared-resource discovery contract and client expectations
- `docs/37-wave-c-qa-validation.md` - Wave C QA gates for web and Android baseline
- `docs/38-wave-c-devops-verification.md` - Wave C delivery and environment verification notes
- `docs/39-wave-c1-web-scheduling-authoring.md` - residual web scheduling authoring scope after current Wave C
- `docs/40-wave-c-android-browse-detail.md` - Wave C Android owned/shared browse and read-only task detail
- `docs/41-wave-c1-web-scheduling-authoring-implementation.md` - implemented Wave C.1 web recurrence and reminder authoring
- `docs/42-wave-c-android-notification-entry-foundation.md` - Android device registration and notification-open/deep-link foundation
- `docs/43-new-chat-transition-instruction.md` - ready-to-use handoff instruction for opening a new clean chat
- `docs/44-android-sdk-assembledebug-verification.md` - Android SDK setup and verified local `assembleDebug` path on 2026-04-27
- `docs/45-notification-staging-smoke-runbook.md` - executable Firebase / Android / backend smoke procedure for real push verification
- `docs/46-android-notification-repair-summary.md` - Android repair-wave summary after the first emulator push smoke attempt
- `docs/47-device-registration-logical-device-upsert-repair.md` - backend and Android follow-up that closes logical-device registration idempotency in the repo
- `docs/48-notification-smoke-backend-send-blocker.md` - first post-repair smoke note proving device registration and narrowing the remaining blocker to backend send/runtime wiring
- `docs/49-notification-smoke-firebase-auth-blocker.md` - historical note for the later-narrowed Firebase auth symptom before the dependency root cause was proven
- `docs/50-notification-runtime-clean-pass.md` - passing end-to-end notification runtime proof on the owned local backend + emulator path
- `docs/51-agent-notification-runtime-playbook.md` - short autonomous verification playbook for repeating the notification smoke without user intervention

Current verification status:
- backend `mvn test` is green in the current documented state
- web `npm run build` is green in the current documented state
- Android local `assembleDebug` is green in the current documented state
- backend `NotificationDeliveryIntegrationTest` is green after the logical-device upsert repair on `2026-04-27`
- backend container baseline now exists via `backend/Dockerfile` and `backend/.dockerignore`
- local `rocketflow-backend:latest` build is proven, and the backend container reaches `/actuator/health = UP` against a temporary `postgres:16` smoke runtime
- backend publish destination is now fixed to `GHCR`, and `.github/workflows/backend-image-publish.yml` prepares a manual `ghcr.io/<owner>/rocketflow-backend` publish path
- local end-to-end notification runtime proof `reminder -> push -> tap -> task open` is green on the owned backend + emulator path from `docs/50-notification-runtime-clean-pass.md`
- GitHub Actions `backend-verify` now runs backend tests, backend image build, and a temporary `postgres:16`-backed container health smoke
- GitHub Actions `web-verify` and `android-verify` exist as repository gates
- web and Android lanes are still build-only gates, not runtime or release certification

Current notification/runtime status:
- backend now contains a real Firebase Admin sender path plus a fallback stub sender when Firebase is not configured
- backend device registration now supports logical-device upsert when clients provide a stable `installationId`
- Android now contains Firebase token acquisition, token refresh persistence, message receive handling, and tap-open routing code
- Android Firebase bootstrap can now work either through default app resources or explicit build-time Firebase fields
- Android repair-wave changes have landed for Firebase bootstrap, session/UI handling, notification rendering stability, and RU copy recovery
- Android companion now persists a stable installation id for device registration across unregister/logout cycles
- post-repair Android device registration is now re-proven on a fresh smoke user in the local emulator flow
- scheduler safety is stronger than the original MVP baseline because reminder polling now uses a PostgreSQL advisory transaction lock
- end-to-end push is now proven on a self-owned local runtime with explicit backend env and a Play-services-capable emulator
- the shortest repeatable operatorless verification path is now documented in `docs/51-agent-notification-runtime-playbook.md`
- repo-backed owned-runtime startup now has a canonical entrypoint in `scripts/Start-NotificationSmokeBackend.ps1`
- repo-backed smoke-task provisioning and backend outcome capture now have a canonical helper in `scripts/Invoke-NotificationSmokeTask.ps1`
- repo-backed backend container smoke now also has a canonical helper in `scripts/Invoke-BackendDockerRuntimeSmoke.ps1`, reused by CI/publish automation
- Yandex Cloud production infrastructure baseline is documented in `docs/57-yandex-cloud-prod-infra.md`
- GitHub CI/CD policy and required branch protection checks are documented in `docs/58-github-cicd-policy.md`

Known readiness limits:
- Android runtime path is now locally proven, but not yet formalized as CI or staging certification
- backend notification rollout still depends on correctly provisioned Firebase credentials and environment wiring outside version control
- the default `localhost:8080` process should still not be trusted for notification verification unless its env wiring is explicitly proven
- scheduler safety is improved, but notification rollout should still not be treated as horizontally hardened
- web and Android CI lanes are build-only and should not be read as runtime or release verification
- staging/release readiness still needs executable, repo-backed verification assets and smoke procedures
- web scheduling authoring is more honest about partial-save failures, but the save path is still not transactional

Project structure:
- `backend/` - Spring Boot backend
- `web/` - React web client
- `android/` - Android companion workspace
