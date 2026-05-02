# RocketFlow Android Companion

This directory is the repository baseline for the Android companion app.

Current companion scope:

- login and session restore
- browse owned and shared planning data needed to reach tasks
- offline-first CRUD for owned folders, goals, and tasks
- task detail
- device registration and notification-open/deep-link entry foundation
- background planning sync through WorkManager

Current Android runtime contract:

- `google-services` is applied only when `android/app/google-services.json` exists
- manual Firebase bootstrap is supported through the four `ROCKETFLOW_ANDROID_FIREBASE_*` values or matching Gradle properties
- cleartext traffic is enabled only when `ROCKETFLOW_ANDROID_API_BASE_URL` uses `http://`, which keeps the emulator smoke working with `http://10.0.2.2:8080/api` without leaving cleartext always on
- planning data is cached in SQLite and local drafts survive database upgrades
- pending planning changes are queued locally and retried by a bounded WorkManager sync with connected-network constraints and exponential backoff
- planning sync is enqueued on app startup, pending local changes, network restore, and manual Sync

Planning behavior:

- Android can create, edit, and delete owned folders, goals, and tasks while offline
- when connectivity returns, Android pushes pending local changes and pulls folders, goals, and tasks created elsewhere
- folder, goal, and task deletes are soft-deleted remotely through the existing backend API and hidden locally while pending
- shared goals and tasks are read-only on Android

Current limitations:

- Android does not author tags, recurrence rules, or reminders
- task updates preserve known remote tag ids and do not call recurrence or reminder mutation APIs, so Android edits are non-destructive for existing web-authored tags, recurrence, and reminder metadata that has been pulled into the local cache
- manual merge/conflict resolution UI is not implemented; version conflicts remain pending with a sync error marker
- calendar parity
- folder sharing

Implementation should follow `docs/16-mobile-lead-decomposition.md` and `docs/34-wave-c-android-companion-foundation.md`.
