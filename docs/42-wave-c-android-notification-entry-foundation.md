# Wave C Android Notification Entry Foundation

## Scope

This slice continues the Android companion path after auth/session and browse/detail baseline.

Delivered in this step:

- device registration client for `POST /api/devices`
- device deactivation client for `DELETE /api/devices/{deviceId}`
- local storage of the returned `deviceId` for best-effort unregister on logout
- notification / deep-link intent parsing with `taskId`
- task open from `rocketflow://task/{taskId}` inside the existing read-only task detail flow

## Why This Scope

The backend notification foundation already exists, but the current MVP still does not have real end-to-end FCM delivery enabled for staging or production-like validation.

So the right Android step here is not "full push," but a stable entry foundation:

- register the device contract
- keep local registration state
- accept notification/deep-link task entry
- reuse the existing auth/session restore and task-detail fetch path

## Delivered Behavior

### Device Registration

- Android can submit:
  - `platform = android`
  - `pushToken`
  - `deviceName`
- the returned registration is persisted locally
- logout attempts best-effort device deactivation before clearing local session state

### Notification Open / Deep Link

- Android accepts `rocketflow://task/{taskId}`
- Android also accepts notification-style `taskId` extras
- if the user is already signed in, the app opens task detail immediately
- if the user is signed out, the task open is held pending until session restore/login completes
- task open reuses the same protected `GET /api/tasks/{taskId}` path already used by browse/detail

## Guardrails Kept

- Android remains companion-only
- no planning CRUD was added
- no calendar or reminder editing UI was added
- no collaborator-specific notification fan-out assumptions were introduced
- real FCM transport is still not treated as verified

## Code Areas

- `android/app/src/main/java/com/rocketflow/companion/notifications/**`
- `android/app/src/main/java/com/rocketflow/companion/auth/AuthRepository.kt`
- `android/app/src/main/java/com/rocketflow/companion/network/HttpJsonClient.kt`
- `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/rocketflow/companion/RocketFlowCompanionApp.kt`

## Verification State

Verified in this step:

- static code reconciliation of Android repositories and notification entry wiring

Verified later in the current local environment on `2026-04-27`:

- Android SDK was installed and connected to the workspace
- `android/local.properties` now points at the local SDK
- local `assembleDebug` is green
- debug APK is produced at `android/app/build/outputs/apk/debug/app-debug.apk`

Current blocker has moved:

- real FCM token acquisition and refresh are still not wired
- backend sender is still a stub/logging implementation
- notification receive/runtime verification is still pending on a real Firebase path

## Next Planned Step

After this foundation, the next Android step narrows to:

- real FCM/runtime token wiring
- notification receive/runtime handling validation
- staging-oriented delivery verification once Firebase credentials and runtime integration exist
