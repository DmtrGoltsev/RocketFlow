# Device Registration Logical Device Upsert Repair

## Purpose

This note records the backend and Android follow-up that closes the logical-device registration gap called out in `docs/46-android-notification-repair-summary.md`.

It also records the immediate verification state reached on `2026-04-27`.

Use this together with:

- `docs/45-notification-staging-smoke-runbook.md`
- `docs/46-android-notification-repair-summary.md`
- `docs/48-notification-smoke-backend-send-blocker.md`

## Why This Follow-Up Happened

The Android repair wave reduced duplicate-registration risk in the client, but the backend still treated `POST /api/devices` as effectively idempotent only on `pushToken`.

That left one important gap:

- a real token rotation or registration recovery could still create or preserve stale rows unless the client successfully cleaned up the previous registration first

## Preflight Result Before Further Smoke

Before changing the contract, the repo-backed smoke preflight from `docs/45-notification-staging-smoke-runbook.md` was re-run in the current shell.

Observed result:

- Android local prerequisites were present enough for smoke preparation:
  - `android/local.properties` existed
  - `android/app/google-services.json` existed
- the current shell was still missing the backend/runtime env wiring needed for a real smoke:
  - `ROCKETFLOW_DB_URL`
  - `ROCKETFLOW_DB_USERNAME`
  - `ROCKETFLOW_DB_PASSWORD`
  - `ROCKETFLOW_ALLOWED_ORIGINS`
  - `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
  - `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
  - `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID`
  - FCM credentials env or credentials path
  - `ROCKETFLOW_ANDROID_API_BASE_URL`

Current smoke outcome state for this shell:

- `blocked_external_config`

This means the next useful repo change was no longer another Android runtime workaround.

## What Landed

### Backend

- added Flyway migration `V8__device_registration_logical_device_upsert.sql`
- added nullable `installation_id` to `device_registrations`
- added a unique partial index on `installation_id`
- extended `POST /api/devices` to accept optional `installationId`
- updated device registration resolution so the backend can:
  - match the current row by `installationId`
  - match the current row by `pushToken`
  - prefer the current token row when both match different rows
  - retire the superseded logical-installation row by clearing its `installationId` and deactivating it

### Android

- the Android companion now persists a stable UUID-like installation id locally
- unregister and logout clear the stored registration state without deleting that installation id
- device registration requests now send `installationId` automatically

## Verification Performed

Verified on `2026-04-27`:

- backend full `mvn test` passed after this follow-up
- backend `mvn -Dtest=NotificationDeliveryIntegrationTest test` passed
- that test now covers:
  - duplicate-token reuse
  - token rotation for one logical installation
  - conflict reconciliation between a current token row and an older logical-installation row
- Android `:app:assembleDebug --no-daemon` passed after the Android-side installation-id change

## What This Does And Does Not Prove

What this change now proves:

- the repo no longer depends only on client-side delete-then-create behavior for logical-device idempotency
- the in-repo Android client and backend agree on a stable logical-device registration contract
- the targeted backend notification/device slice still passes after the contract change
- the Android companion still builds after the client-side change

What this still does not prove:

- post-repair device registration has been re-observed on emulator/device after this follow-up
- real Firebase push delivery has been re-observed after this follow-up
- `reminder -> push -> tap -> task open` has been proven end-to-end

Later note:

- post-repair device registration was subsequently re-proven in `docs/48-notification-smoke-backend-send-blocker.md`

## Exact Next Step

The next correct step is now operational, not architectural:

1. export the missing smoke env vars required by `docs/45-notification-staging-smoke-runbook.md`
2. rerun `scripts/Invoke-NotificationSmokePreflight.ps1`
3. reinstall or relaunch the current Android debug app if needed
4. re-confirm push token presence and backend device registration
5. run the real `reminder -> push -> tap -> task open` smoke
