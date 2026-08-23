# RocketFlow

Project documentation lives in [`docs/`](docs/).

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
- `docs/66-weekly-focus-calendar-delivery.md` - Calendar, Weekly Focus, Web Push delivery status and rollout runbook
- `docs/67-weekly-focus-production-rollout-evidence.md` - immutable production rollout evidence for deployed source `910c061de4af9395d9bb682624bd966b2977a738`
- `docs/68-scroll-and-priority-retirement-delivery.md` - V21 delivery contract and rollback gates for Android scroll restoration and task-priority retirement
- `docs/69-v21-production-rollout.md` - canonical V21 production rollout evidence for backend, web, authenticated API smoke, and Android sideload
- `docs/70-native-ios-parity-contract.md` - normative Android/backend parity contract for the native iOS companion
- `docs/71-native-ios-delivery.md` - canonical native iOS implementation, CI, build, and remaining-gates evidence
- `docs/72-native-ios-mac-device-handoff.md` - human Mac/iPhone no-push and optional-push handoff boundaries
- `docs/ios-native-mac-codex-install-prompt.md` - copyable orchestrated Codex prompt for Mac verification and personal iPhone installation

Weekly Focus production checkpoint (`2026-08-10`):

- Calendar and Weekly Focus are implemented for backend, web, and Android.
- Focus notification cadence is server-owned and supports FCM and Web Push.
- Production backend and web are deployed from source SHA `910c061de4af9395d9bb682624bd966b2977a738` as release `sha-910c061de4af`; this documentation follow-up is a separate commit and is not the deployed source.
- GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631) completed successfully, local and public health passed, and production Flyway is at `V20` (`20/20`).
- Focus cadence and Web Push remain disabled. No rollback was used.
- An installable production-API sideload APK was built from source `910c061de4af9395d9bb682624bd966b2977a738`, signed with the existing debug certificate, and verified by reinstall, hash match, cold launch, logcat, and health checks. It has no FCM configuration and is not a Play Store production release.
- Authenticated production smoke remains an explicit evidence gap.
- At this recorded production checkpoint, branch evidence was backend 135 tests, web 54 tests, and Android 77 tests. These historical counts are not permanent suite requirements.

Current V21 production delivery (`2026-08-22`):

- Current evidence is backend 142/142, web 61/61 with production build and dependency audit passing, and Android 90/90 with `assembleDebug`, `lintDebug` (`0` errors, `34` existing warnings), and debug Android-test APK assembly passing. These are checkpoint counts, not permanent suite requirements.
- Android Planner restores a stable resource-row anchor plus pixel offset across re-render, detail return, refresh, and instance-state recreation, with ancestor, absolute-position, and clamped fallbacks.
- Android short-lived SQLite stores are closed by their four runtime owners, and the landscape task editor now uses a compact full-screen dialog with a real scroll viewport and explicit IME/system-bar insets; portrait keeps the existing `AlertDialog`.
- Task priority is retired from product UI, editing, validation, business behavior, sorting, and settings. `LEGACY_TASK_PRIORITY=5` remains an opaque wire/storage shadow until old APK and V20 rollback support explicitly end.
- Flyway V21 changes compatibility defaults only and does not rewrite/drop historical task, reschedule-event, or settings data.
- The production helper jointly promoted the V21 backend and web artifact from source `50a63270ae094fe08ee57b945be0930cb1115dfe`; the web remains compatible with V20 and V21. Application rollback accepts a V20-or-newer database baseline, never decreases the Flyway history count, and uses a V20 artifact that is forward-compatible with V21; database rollback is not part of the app workflow.
- Production is release `sha-50a63270ae09` at Flyway `V21` (`21/21`); GitHub Actions run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905) succeeded. Canonical evidence is in `docs/69-v21-production-rollout.md`; the V20 checkpoint above remains historical context.

Native iOS delivery checkpoint (`2026-08-23`):

- Branch `codex/native-ios-companion` contains the native iOS 16+ companion; canonical app-code/build evidence is pinned to `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`, independently of later docs-only commits. It has Planner, Calendar, and Focus tabs; native details/editors/sharing; GRDB offline sync and conflict recovery; local reminders; RU/EN localization; deep-link/process restoration; and account-scoped persistence leases.
- Manual [iOS Verify run 32655691351](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32655691351) passed XcodeGen parity, package resolution/lock parity, no-sign simulator build, `540/540` unit tests, and `2/2` UI tests (`542` total). Canonical evidence and artifact IDs are recorded in `docs/71-native-ios-delivery.md`.
- `ios/RocketFlow.xcodeproj` and its SwiftPM `Package.resolved` are committed and verified against XcodeGen `2.46.0`; the app uses Firebase `12.17.0` and GRDB `6.29.3`.
- The Mac handoff uses tooling commit A `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149`, proven by manual [iOS Verify run 32669924719](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32669924719), job `97269056380`, then a later docs commit B records immutable A/run A without self-pinning. Run A passed Mac contracts `174/174` with `0` skipped, XcodeGen/project/package/build gates, unit `540`/`0` failed, UI `2`/`0` failed, total `542`/`0` failed; artifacts are `RocketFlow-xcresult` ID `9501177125` (`1,317,064` bytes) and `RocketFlow-xcodeproj-xcodegen-2.46.0` ID `9501179599` (`25,070` bytes). A includes `.github/workflows/ios-verify.yml`, `.gitignore`, `ios/Config/Device.xcconfig.example`, every current Mac handoff script/test listed in `docs/72-native-ios-mac-device-handoff.md`, and the workflow validation step. A Mac uses the latest candidate/docs HEAD, proves A is an ancestor, and verifies no identity-path changes after A; docs HEAD is not required to equal A.
- The repository is GO for clone/build/continue on a Mac and simulator verification. Device/App Store readiness still requires an Apple Team and signing, a local `GoogleService-Info.plist` outside the repository or proven ignored and untracked, APNs/Firebase credentials, production deployment of the candidate V22 iOS device-registration migration/backend, HTTPS, and device/manual accessibility evidence.
- Production remains backend/web source `50a63270ae094fe08ee57b945be0930cb1115dfe` at Flyway `V21`; candidate V22 is not deployed and production DB state was not re-inspected for this documentation checkpoint.

Current verification status:
- backend `mvn test` is green in the current documented state
- web `npm run build` is green in the current documented state
- Android local `assembleDebug` is green in the current documented state
- backend `NotificationDeliveryIntegrationTest` is green after the logical-device upsert repair on `2026-04-27`
- backend container baseline now exists via `backend/Dockerfile` and `backend/.dockerignore`
- local `rocketflow-backend:latest` build is proven, and the backend container reaches `/actuator/health = UP` against a temporary `postgres:16` smoke runtime
- local end-to-end notification runtime proof `reminder -> push -> tap -> task open` is green on the owned backend + emulator path from `docs/50-notification-runtime-clean-pass.md`
- GitHub Actions `backend-verify` now runs backend tests, backend image build, and a temporary `postgres:16`-backed container health smoke
- GitHub Actions `web-verify` and `android-verify` exist as repository gates
- GitHub Actions `ios-verify` is separately green for canonical behavior SHA/run `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`/`32655691351` and Mac tooling SHA/run `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149`/`32669924719`; the latter also verifies the expanded handoff contracts
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
- Production baseline для HexCore описан в `docs/60-hexcore-prod-runbook.md`
- Candidate GitHub CI/CD behavior and optional recommended branch-protection settings are described in `docs/58-github-cicd-policy.md`; they are not evidence that protection is configured on `master`

Known readiness limits:
- Android runtime path is now locally proven, but not yet formalized as CI or staging certification
- production Focus cadence and Web Push are disabled; no production provider-delivery claim is made
- the prior unsigned APK is superseded after Android rejected it as damaged/not installable; the current debug-cert APK is verified for direct sideloading, but is not Play Store production-signing evidence and has no FCM configuration
- authenticated production API smoke is complete for the V21 rollout; iOS device/push production smoke remains gated by signing, provider credentials, V22 deployment, and HTTPS
- the default `localhost:8080` process should still not be trusted for notification verification unless its env wiring is explicitly proven
- scheduler safety is improved, but notification rollout should still not be treated as horizontally hardened
- web and Android CI lanes are build-only and should not be read as runtime or release verification
- web scheduling authoring is more honest about partial-save failures, but the save path is still not transactional

Project structure:
- `backend/` - Spring Boot backend
- `web/` - React web client
- `android/` - Android companion workspace
- `ios/` - native iOS 16+ companion workspace generated with XcodeGen
