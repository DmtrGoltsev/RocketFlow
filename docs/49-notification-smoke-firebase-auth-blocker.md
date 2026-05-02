# Notification Smoke Firebase Auth Blocker

Superseded note:

- `docs/50-notification-runtime-clean-pass.md` records the later resolution and final `passed` smoke
- the apparent Firebase Admin auth blocker described here was later proven to be a backend dependency-skew defect, not a bad service-account JSON

## Purpose

This note records the next notification runtime pass executed after:

- the logical-device upsert follow-up in `docs/47-device-registration-logical-device-upsert-repair.md`
- the earlier backend-runtime uncertainty captured in `docs/48-notification-smoke-backend-send-blocker.md`

It closes the remaining unknowns around:

- whether a known-good backend instance can be started with explicit notification env
- whether scheduler polling and delivery persistence really execute
- whether Android `tap -> task open` still works on the repaired runtime path

## Outcome

Outcome state:

- `failed_backend_send`

This is now a much narrower classification than the earlier `docs/48-notification-smoke-backend-send-blocker.md` pass.

The remaining blocker is no longer an unknown live backend process or unknown scheduler wiring.

It is now the external Firebase Admin auth path for the supplied service-account JSON.

## Runtime Shape Used

On `2026-04-27`, the smoke was rerun on a self-owned local runtime instead of the unknown `localhost:8080` instance.

Runtime used:

- temporary PostgreSQL cluster started locally on port `55432`
- isolated database:
  - `rocketflow_smoke`
- isolated backend instance:
  - `http://localhost:18080`
- Android debug build retargeted to:
  - `http://10.0.2.2:18080/api`

Confirmed backend env for that instance:

- `ROCKETFLOW_DB_URL=jdbc:postgresql://localhost:55432/rocketflow_smoke`
- `ROCKETFLOW_DB_USERNAME=rocketflow_smoke`
- `ROCKETFLOW_DB_PASSWORD=<db-password>`
- `ROCKETFLOW_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY=PT15S`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY=PT5S`
- `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID=rocketflowgoltsev`
- `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH=C:\path\to\firebase-service-account.json`
- `ROCKETFLOW_ANDROID_API_BASE_URL=http://10.0.2.2:18080/api`

Smoke preflight from `scripts/Invoke-NotificationSmokePreflight.ps1` passed in the same env.

## Narrow Repo Fixes Landed During This Pass

While bringing up the isolated backend, two repo-backed notification wiring defects were discovered and fixed.

### Fix 1

The backend initially failed to start with `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true` because no `FcmSender` bean was created.

Narrow fix:

- moved `FcmSender` selection into explicit configuration

Files:

- `backend/src/main/java/com/rocketflow/notifications/FcmSenderConfiguration.java`
- `backend/src/main/java/com/rocketflow/notifications/FirebaseAdminFcmSender.java`
- `backend/src/main/java/com/rocketflow/notifications/LoggingFcmSender.java`
- `backend/src/test/java/com/rocketflow/notifications/FcmSenderConfigurationTest.java`

### Fix 2

The first version of that fix still allowed Spring condition ordering to choose the fallback stub sender.

Narrow fix:

- made `FcmSender` selection deterministic through `ObjectProvider<FirebaseMessaging>`
- when `FirebaseMessaging` is present, the backend now uses `FirebaseAdminFcmSender`
- otherwise it falls back to `LoggingFcmSender`

Verification after the fix:

- targeted backend tests passed
- full backend `mvn test` passed
- isolated backend instance started cleanly with FCM env enabled

## What Was Proven In This Pass

### Backend Runtime

Proven:

- explicit notification-enabled backend can be started locally and kept healthy
- `/actuator/health` returned `{"status":"UP"}`
- Flyway migrations applied cleanly against the isolated PostgreSQL runtime
- reminder scheduler executed on the isolated backend
- `notification_deliveries` rows were persisted for due reminders

### Android Runtime

Re-proven against the isolated backend:

- emulator remained healthy and reachable over `adb`
- Android debug app was rebuilt and installed against `http://10.0.2.2:18080/api`
- fresh smoke user login succeeded
- real Firebase push token was present in the app UI
- notification permission was granted
- fresh device registration succeeded against the isolated backend

Observed device-registration evidence:

- smoke user:
  - `smoke18080-20260427164652@example.com`
- device registration id:
  - `0abf2c67-51a3-48e7-8016-8095ded99c97`
- installation id:
  - `ca7f6fd7-fce6-46f9-b057-adb53ee5696b`

### Android Open Path

Because the real push send remained blocked externally, the downstream open path was proven separately through the same deep-link intent route used by notification taps.

Proven:

- `adb shell am start -a android.intent.action.VIEW -d "rocketflow://task/d7d47048-89c0-4b4f-840f-17da018db781" com.rocketflow.companion`
- app returned to `MainActivity`
- UI showed a task-open notice containing `d7d47048-89c0-4b4f-840f-17da018db781`
- task detail section rendered the intended task:
  - `Smoke push retry 20260427-165301`

This means the unresolved gate is now upstream of Android receive/tap-open behavior.

## Reminder Attempts Executed

### Attempt 1

Task:

- `6d5fffa3-2cf7-4e9c-a591-bf324091eac7`
- title:
  - `Smoke push 20260427-164856`

Observed delivery row:

- status:
  - `failed`
- provider response:
  - `FCM is enabled, but no real Firebase sender is configured.`

Interpretation:

- this captured the second repo-backed wiring defect before the deterministic sender-selection fix landed

### Attempt 2

Task:

- `d7d47048-89c0-4b4f-840f-17da018db781`
- title:
  - `Smoke push retry 20260427-165301`

Observed delivery row after the fix:

- status:
  - `failed`
- scheduled at:
  - `2026-04-27 16:54:01.965067+03`
- attempted at:
  - `2026-04-27 16:54:10.445897+03`
- provider response:
  - `UNKNOWN:Unknown error while making a remote service call: Unexpected error refreshing access token`

Backend log evidence:

- no fallback stub sender line was emitted for this attempt
- scheduler still logged:
  - `Reminder delivery run sent=0 failed=1 skipped=0`

Android receive evidence for this attempt:

- app was backgrounded to launcher before the due window
- notification shade contained no RocketFlow notification row
- logcat contained no RocketFlow receive trace

## External Evidence Around The Remaining Blocker

Confirmed locally:

- TCP connectivity to `oauth2.googleapis.com:443` succeeded
- TCP connectivity to `fcm.googleapis.com:443` succeeded
- supplied Firebase Admin JSON parsed as:
  - `type=service_account`
  - `project_id=rocketflowgoltsev`
  - `client_email=<firebase-service-account-email>`
  - `token_uri=https://oauth2.googleapis.com/token`

This means the blocker is narrower than generic network reachability.

The failing surface is specifically:

- OAuth access-token refresh for the supplied Firebase Admin service-account JSON on this machine/runtime path

## Best Current Interpretation

What is now proven and should not be reopened first:

- explicit backend env wiring
- scheduler enablement
- reminder polling
- due-delivery persistence
- Android login
- Android push token acquisition
- Android device registration
- Android task-open path after notification-style intent

What is still blocked:

- Google access-token minting for the supplied Firebase Admin service-account JSON
- therefore real FCM send cannot complete yet
- therefore real Android receive cannot be re-proven yet

## Exact Next Step

One exact external input is now required:

- provide a Firebase Admin JSON for `rocketflowgoltsev` whose service account can successfully refresh an OAuth access token on this machine/runtime path

Equivalent operator action:

1. replace or repair `C:\path\to\firebase-service-account.json`
2. verify the referenced service account still exists and can mint access tokens for `https://oauth2.googleapis.com/token`
3. rerun the same isolated smoke path on port `18080` without changing Android/device setup

At that point the next pass should be able to reopen only the final step:

- real `push -> receive -> tap -> task open`

## Later Resolution

The root cause described in this note was later corrected without changing Android runtime logic.

Later evidence proved:

- the refreshed Firebase Admin JSON could mint OAuth tokens successfully on this machine
- backend failure persisted only because Maven resolved:
  - `google-auth-library-oauth2-http:1.29.0`
  - with `google-auth-library-credentials:1.23.0`
- that mismatch caused Java-side `NoClassDefFoundError: com/google/auth/CredentialTypeForMetrics`

The final repair and clean pass are recorded in:

- `docs/50-notification-runtime-clean-pass.md`
