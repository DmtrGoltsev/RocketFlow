# Android SDK AssembleDebug Verification

## Purpose

This note records the Android build-verification path after the notification-entry handoff and freezes the exact state reached on `2026-04-27`.

It supersedes the earlier "SDK is still missing" assumption that existed before the local environment was fully configured.

## Verification Date

- `2026-04-27`

## Context

Current Android baseline already includes:

- auth and session restore
- owned/shared browse flow
- read-only task detail
- device registration
- notification-open and deep-link entry
- Firebase token acquisition and refresh persistence
- FCM receive handler and local notification rendering

The required gate from the handoff packet was:

- confirm local Android build readiness with `assembleDebug`

## Commands Run

Inside `C:\Users\hp\Documents\Codex\RocketFlow\android`:

1. wrapper attempt:
   - `.\gradlew.bat assembleDebug`
2. fallback with local Gradle distribution:
   - `C:\Gradle\gradle-9.4.1-bin\gradle-9.4.1\bin\gradle.bat assembleDebug`
3. final successful local verification path:
   - workspace-local `GRADLE_USER_HOME`
   - Android Studio JBR
   - local SDK wired through `android/local.properties`
   - `C:\Gradle\gradle-9.4.1-bin\gradle-9.4.1\bin\gradle.bat assembleDebug --no-daemon`

## Observed Results

### Wrapper Attempt

The wrapper was not a reliable signal in this environment.

Observed limits:

- wrapper attempted to write under `C:\Users\CodexSandboxOffline\.gradle\wrapper\...`
- the first run failed on parent directory creation for the lock file
- the retry with workspace-local `GRADLE_USER_HOME` then failed on sandboxed network access while downloading `gradle-9.4.1-bin.zip`

Implication:

- wrapper-based verification should not be treated as the canonical local path in this environment
- the installed Gradle distribution is the correct fallback path here

### Local Gradle Verification

The local Gradle distribution first exposed the expected `SDK location not found` blocker.

After Android Studio SDK installation and local wiring, the same path completed successfully.

Verified result:

- Android local `assembleDebug` is green
- debug APK was produced at:
  - `android/app/build/outputs/apk/debug/app-debug.apk`

## Confirmed Environment State After Fix

At the time of the successful verification:

- Android SDK exists at:
  - `C:\Users\hp\AppData\Local\Android\Sdk`
- `android/local.properties` is present and points to that SDK
- local Gradle distribution exists at:
  - `C:\Gradle\gradle-9.4.1-bin\gradle-9.4.1\bin\gradle.bat`
- Android Studio JBR is available and works for the build

## Project Requirements Confirmed From Gradle Files

From the current Android build configuration:

- Android Gradle Plugin: `8.5.2`
- Kotlin Android plugin: `1.9.24`
- `compileSdk = 34`
- `targetSdk = 34`
- `minSdk = 26`
- Java/Kotlin target: `17`

## Current Conclusion

The Android build gate is now closed for the local environment.

What this verification does prove:

- the Android workspace builds locally
- SDK/tooling setup is now sufficient for `assembleDebug`
- recent Android companion code changes remain build-valid

What this verification does not prove:

- real Firebase project wiring
- real FCM delivery on staging or a physical device
- notification permission/channel UX on device
- end-to-end reminder smoke

## Exact Next Step After This Verification

The next correct step is no longer SDK setup.

It is now:

1. wire real Firebase assets and backend credentials
   - either through default Firebase app resources
   - or through explicit Android build-time Firebase fields
2. run `reminder -> push -> tap -> task open` smoke validation
3. keep Android build passing while runtime notification verification lands

## Follow-Up Note

If this environment is used again, the preferred local verification path remains:

- use the installed Gradle distribution
- keep SDK wired through `android/local.properties`
- use Android Studio JBR or another known-compatible JDK 17 runtime
