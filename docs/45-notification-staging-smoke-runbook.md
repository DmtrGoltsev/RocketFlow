# Notification Staging Smoke Runbook

## Purpose

This runbook turns the current notification gap into an executable operator path.

It does not prove real push by itself.

It defines the exact preflight, config wiring, and smoke sequence required to prove:

- reminder scheduling
- backend FCM send path
- Android receive path
- tap-open task routing

Target proof:

- `reminder -> push -> tap -> task open`

This document is now the canonical repo-backed procedure for the first real notification smoke.

Use it together with:

- `docs/31-wave-b-devops-staging-secrets.md`
- `docs/38-wave-c-devops-verification.md`
- `docs/44-android-sdk-assembledebug-verification.md`

## Scope And Boundaries

This runbook covers:

- backend notification preflight
- Android Firebase config preflight
- one-device staging or local-device smoke
- minimum evidence to capture

This runbook does not cover:

- production rollout
- multi-device fan-out
- horizontal scheduler validation
- release-signing workflow

## Required Preconditions

Before starting the smoke, all of the following must be true:

- backend `mvn test` is green in the intended code state
- Android `assembleDebug` is green in the intended code state
- exactly one backend instance will run with scheduler enabled for the smoke
- backend uses PostgreSQL
- one Android device or Play-services-capable emulator is available
- the Android build points to the same backend environment used for the smoke
- backend and Android use the same non-production Firebase project

## Backend Required Configuration

The backend must receive:

- `ROCKETFLOW_DB_URL`
- `ROCKETFLOW_DB_USERNAME`
- `ROCKETFLOW_DB_PASSWORD`
- `ROCKETFLOW_ALLOWED_ORIGINS`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID`
- either `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON`
- or `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH`

Recommended smoke-only overrides:

- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY=PT15S`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY=PT5S`

Why:

- shorter polling makes the smoke faster without changing code

## Android Required Configuration

The Android build must receive:

- `ROCKETFLOW_ANDROID_API_BASE_URL`
- and one Firebase bootstrap mode

### Mode A: default Firebase resources

Provide:

- `android/app/google-services.json`

This file is gitignored and should stay outside version control.

### Mode B: explicit build-time Firebase values

Provide all four values:

- `ROCKETFLOW_ANDROID_FIREBASE_APPLICATION_ID`
- `ROCKETFLOW_ANDROID_FIREBASE_API_KEY`
- `ROCKETFLOW_ANDROID_FIREBASE_PROJECT_ID`
- `ROCKETFLOW_ANDROID_FIREBASE_GCM_SENDER_ID`

The same values may also be supplied through Gradle properties:

- `rocketflowFirebaseApplicationId`
- `rocketflowFirebaseApiKey`
- `rocketflowFirebaseProjectId`
- `rocketflowFirebaseGcmSenderId`

Use [android/firebase-config.example.properties](C:/Users/hp/Documents/Codex/RocketFlow/android/firebase-config.example.properties) as the non-secret template.

If both `google-services.json` and explicit Firebase values are present, the Android app prefers the explicit values for token fetch.

Keep both sources aligned to the same Firebase project to avoid app/token mismatch during smoke.

## Preferred Preflight Command

Run this before any smoke attempt:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokePreflight.ps1
```

The preflight does not use network calls.

It verifies that the current shell and workspace contain the minimum config needed for the smoke.

## Preferred Owned Backend Startup

When the smoke uses the known-good local shape, prefer this entrypoint:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Start-NotificationSmokeBackend.ps1
```

What it does:

- reuses the current shell env instead of guessing hidden defaults
- runs `scripts/Invoke-NotificationSmokePreflight.ps1` unless explicitly skipped
- defaults the smoke scheduler cadence to `PT15S` and `PT5S` when those overrides are still unset
- requires `ROCKETFLOW_ANDROID_API_BASE_URL` to match the owned backend port
- starts the backend on `http://localhost:18080`
- waits for `/actuator/health` to return `UP`
- writes backend stdout/stderr logs under `tmp/notification-smoke/`

If a different owned port is needed, pass `-BackendPort <port>` and keep Android pointed at the matching `http://10.0.2.2:<port>/api` base URL.

## Preferred Smoke Task Provisioning

Once Android is already signed in against the owned backend and device registration exists, prefer this helper instead of creating the reminder task by hand:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokeTask.ps1 `
  -Email smoke@example.com `
  -Password 'strong-password'
```

Add `-RegisterIfMissing` only when bootstrapping a fresh smoke user for the first time.

Practical staging bootstrap note before DB or log wiring is fully available:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokeTask.ps1 `
  -BackendBaseUrl <staging-api> `
  -Email smoke@example.com `
  -Password 'strong-password' `
  -RegisterIfMissing `
  -SkipDeviceCheck `
  -SkipWaitForDelivery
```

Use this only to bootstrap login, optional register, and near-term task creation against a live staging API.

It does not replace full staging proof for backend send, Android receive, or tap-open task routing.

What it does:

- verifies backend health on the owned runtime
- logs in as the smoke user, or optionally registers it first
- fails fast if `/api/me/settings` has notifications disabled
- confirms an active `device_registrations` row exists for that user unless explicitly skipped
- reuses or creates the `Notification smoke` folder and `Owned runtime verification` goal
- creates one near-term task plus one `before_planned_time` reminder
- optionally waits for the first `notification_deliveries` row and writes a JSON report under `tmp/notification-smoke/`

This helper talks to the host-owned backend URL such as `http://localhost:18080/api`.

Keep the Android app pointed at the matching emulator/device URL such as `http://10.0.2.2:18080/api`.

## Build And Runtime Sequence

### 1. Start backend in smoke mode

Run the backend with notification scheduler and FCM enabled in the target environment.

Preferred local-owned path:

- `powershell -ExecutionPolicy Bypass -File .\scripts\Start-NotificationSmokeBackend.ps1`

Minimum intent:

- one backend instance only
- migrations applied
- health endpoint healthy
- logs visible

Expected backend behavior:

- startup does not fail on missing FCM credentials
- reminder polling starts
- no duplicate scheduler workers exist
- health reaches `UP` before Android smoke continues

### 2. Build and install Android debug app

Point Android to the same backend environment.

Example build intent:

- local device build with `ROCKETFLOW_ANDROID_API_BASE_URL`
- Firebase configured either by `google-services.json` or manual build fields

Install the debug APK on the smoke device.

### 3. Sign in on Android

On the Android companion:

- log in with a real smoke user
- confirm the app reaches browse flow
- open the notification section in the current shell

Expected result:

- Firebase is shown as configured
- a push token is present or can be refreshed
- device registration succeeds

### 4. Confirm backend device registration

The smoke is not valid unless Android has registered a device against the backend.

At minimum confirm one of:

- backend logs show successful `POST /api/devices`
- database contains an active `device_registrations` row for the smoke user

### 5. Create a near-term reminder

Preferred repo-backed path:

- `powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokeTask.ps1 -Email <smoke-user> -Password <password>`

If first-time smoke-user bootstrap is still needed:

- add `-RegisterIfMissing`

What the helper creates by default:

- task remains active
- owner notifications enabled
- reminder due in the next few minutes

Prefer a simple case:

- one reminder rule
- no collaborator dependency
- no archived goal/folder

### 6. Wait for scheduler poll

Observe backend logs during the due window.

If the helper is used without `-SkipWaitForDelivery`, it also polls PostgreSQL for the matching `notification_deliveries` row and writes the current backend evidence snapshot to `tmp/notification-smoke/smoke-task-*.json`.

Expected success signal:

- one delivery attempt for the smoke device
- no duplicate sends for the same scheduled occurrence

Expected failure signals to capture:

- `skipped_no_active_device`
- `skipped_notifications_disabled`
- Firebase sender error details

### 7. Confirm device receive

On Android:

- push notification appears while app is backgrounded or foregrounded

Expected receive path:

- `RocketFlowMessagingService` receives payload
- notification contains `taskId`
- local notification is shown

### 8. Tap notification

Tap the delivered notification.

Expected result:

- app opens
- task detail route resolves
- intended task opens through existing protected detail fetch

This is the smoke success condition.

## Evidence To Capture

A successful smoke should capture all of:

- backend startup config evidence showing scheduler and FCM enabled
- backend log line or trace for device registration
- backend log line or persisted row for notification delivery attempt
- JSON smoke-task report from `tmp/notification-smoke/` when `Invoke-NotificationSmokeTask.ps1` was used
- screenshot of Android push notification
- screenshot of task detail opened after tap

If the smoke fails, capture:

- exact backend error or skip reason
- whether Android had a token
- whether device registration existed
- whether Firebase was configured by resource file or manual fields

## Fast Failure Matrix

If preflight fails on backend FCM credentials:

- provide either credentials JSON or credentials path
- keep only one of them if operator clarity matters

If preflight fails on Android Firebase config:

- add `google-services.json`
- or fill the manual Firebase properties/env vars completely

If Android signs in but has no token:

- verify Play services availability
- verify Firebase project matches package/application id

If token exists but backend logs `skipped_no_active_device`:

- confirm Android registration call succeeded for the same signed-in user

If backend sends but device receives nothing:

- verify backend and Android use the same Firebase project
- verify token was freshly registered
- verify device notification permission/channel state

If backend records a failed delivery with a provider response similar to:

- `Unknown error while making a remote service call: Unexpected error refreshing access token`
- treat scheduler polling, due reminder selection, and Android registration as already proven
- confirm the Firebase Admin service account can still mint OAuth access tokens for `https://oauth2.googleapis.com/token`
- if manual OAuth token minting succeeds but backend still fails, inspect backend dependency alignment before reopening Android receive debugging
- in particular, verify `com.google.auth:google-auth-library-credentials` is not older than the resolved `google-auth-library-oauth2-http`
- a `NoClassDefFoundError` for `com.google.auth.CredentialTypeForMetrics` means the failure is a backend classpath defect, not a bad Firebase JSON

If notification arrives but tap does not open task:

- inspect payload `taskId`
- inspect Android deep-link and intent handling path

## Recommended Smoke Outcome States

Use exactly one of these outcomes in the follow-up note:

- `passed`
- `blocked_external_config`
- `failed_backend_send`
- `failed_android_receive`
- `failed_tap_open`

## Next Step After First Real Smoke

If the smoke passes:

- create a short verification note in `docs/`
- record the exact environment shape used
- keep FCM rollout limited to approved non-production scope until a separate hardening decision

If the smoke does not pass:

- create a short reconciliation or failure note in `docs/`
- fix the narrow failing layer only
- rerun the same smoke path instead of widening scope
