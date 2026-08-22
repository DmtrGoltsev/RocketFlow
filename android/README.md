# RocketFlow Android Companion

This directory is the repository baseline for the Android companion app.

Current companion scope:

- login and session restore
- browse owned and shared planning data needed to reach tasks
- offline-first CRUD for owned folders, goals, and tasks
- task detail
- Calendar tab with planned-date and deadline markers, selected-day tasks, recurrence projections, and task-detail navigation
- Weekly Focus tab with weighted progress, history, explicit rollover, task picker/search, notification settings, and offline cache/pending mutations
- device registration and notification-open/deep-link entry foundation
- background planning sync through WorkManager

Current Android runtime contract:

- `google-services` is applied only when `android/app/google-services.json` exists
- manual Firebase bootstrap is supported through the four `ROCKETFLOW_ANDROID_FIREBASE_*` values or matching Gradle properties
- debug and release builds default to the reachable production API at `http://45.10.110.42/rocket-api`
- API base URL overrides are supported through `rocketflowApiBaseUrl` / `ROCKETFLOW_ANDROID_API_BASE_URL`, or build-type-specific `rocketflowDebugApiBaseUrl`, `rocketflowReleaseApiBaseUrl`, `ROCKETFLOW_ANDROID_DEBUG_API_BASE_URL`, and `ROCKETFLOW_ANDROID_RELEASE_API_BASE_URL`
- use `rocketflowDebugApiBaseUrl` or `ROCKETFLOW_ANDROID_DEBUG_API_BASE_URL` for emulator-only smoke tests such as `http://10.0.2.2:8081/api`; release tasks reject local-only URLs
- cleartext traffic is enabled only when the selected API base URL uses `http://`
- planning data is cached in SQLite and local drafts survive database upgrades
- short-lived `PlanningLocalStore` instances owned by planning sync, Focus sync, reminder delivery, and acceptance seeding are closed deterministically; lifecycle regressions are covered by tests
- pending planning changes are queued locally and retried by a bounded WorkManager sync with connected-network constraints and exponential backoff
- planning sync is enqueued on app startup, pending local changes, network restore, and manual Sync
- Focus notification cadence is owned by the backend. Android handles data-only FCM delivery and opens `rocketflow://focus`; it must not schedule a second local Focus cadence.
- Focus notification event ids are deduplicated locally, and a cold Focus deep link performs one initial load.

Planning behavior:

- Android can create, edit, and delete owned folders, goals, and tasks while offline
- when connectivity returns, Android pushes pending local changes and pulls folders, goals, and tasks created elsewhere
- folder, goal, and task deletes are soft-deleted remotely through the existing backend API and hidden locally while pending
- shared goals and tasks are read-only on Android
- accessible shared tasks may be selected into the user's Focus while access remains valid
- Planner re-renders restore the first visible stable resource row plus its pixel offset; if that row disappears, restoration falls back to its nearest surviving ancestor, then the clamped absolute scroll position
- Planner scroll state survives detail return, refresh, and Android instance-state recreation; explicit top-level tab switches, sign-out, and planner-state clearing reset it
- task priority is absent from Android UI and business behavior; the local `priority` column/value is an opaque compatibility shadow only, defaulting to `5` when V21 responses omit it and preserved on V20-compatible updates
- hidden green/red priority-decay policy JSON is preserved only so settings updates remain compatible with V20; it is not editable or interpreted by Android
- local task ordering is deterministic without priority: scheduled tasks by `plannedTime`, then `createdAt`, then `id`, with missing `plannedTime` last
- task editing keeps the existing portrait `AlertDialog`; compact landscape below `600dp` uses a full-screen dialog with a real `ScrollView`, persistent Save/Cancel actions, and explicit IME/system-bar insets so focused Title and Details remain reachable with the keyboard open

Current limitations:

- Android does not author tags, recurrence rules, or reminders
- task updates preserve known remote tag ids and do not call recurrence or reminder mutation APIs, so Android edits are non-destructive for existing web-authored tags, recurrence, and reminder metadata that has been pulled into the local cache
- manual merge/conflict resolution UI is not implemented; version conflicts remain pending with a sync error marker
- folder sharing

Feature-branch verification evidence:

- `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug :app:assembleDebugAndroidTest --no-daemon`
- 90 Android debug unit tests passed for the current feature checkpoint. `assembleDebug`, `lintDebug` (`0` errors, `34` existing warnings), and `assembleDebugAndroidTest` also passed. Coverage includes stable anchor/offset restoration fallbacks, priority-shadow migration/compatibility, hidden settings-policy preservation, SQLite-store lifecycle ownership, compact landscape form policy, and terminal `401` handling without session resurrection; this number is evidence, not a fixed contract.
- Device QA passed portrait editing plus landscape Title and Details editing with IME open. The latest IME rerun did not repeat the earlier anchor/logcat scenarios; the prior dedicated anchor QA remains passing, and the compact-form change did not touch anchor code.
- Personal production APK `0.1.1` (`versionCode 2`) was built and installed with `adb install -r` against the production backend release `sha-50a63270ae09` at Flyway `V21`; emulator cold launch reached the Login screen with no captured crash or ANR. Artifact and rollout evidence is recorded in `docs/69-v21-production-rollout.md`; this personal sideload is not a Play Store release.

Implementation should follow `docs/16-mobile-lead-decomposition.md` and `docs/34-wave-c-android-companion-foundation.md`.
