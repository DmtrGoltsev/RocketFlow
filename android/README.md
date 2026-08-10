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

Current limitations:

- Android does not author tags, recurrence rules, or reminders
- task updates preserve known remote tag ids and do not call recurrence or reminder mutation APIs, so Android edits are non-destructive for existing web-authored tags, recurrence, and reminder metadata that has been pulled into the local cache
- manual merge/conflict resolution UI is not implemented; version conflicts remain pending with a sync error marker
- folder sharing

Feature-branch verification evidence:

- `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug --no-daemon`
- 77 Android unit tests passed for the current feature checkpoint, including terminal `401` handling without session resurrection; this number is evidence, not a fixed contract.
- Production APK and backend rollout are outside this checkpoint and have not been performed.

Implementation should follow `docs/16-mobile-lead-decomposition.md` and `docs/34-wave-c-android-companion-foundation.md`.
