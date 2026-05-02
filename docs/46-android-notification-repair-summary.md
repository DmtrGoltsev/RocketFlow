# Android Notification Repair Summary

## Purpose

This note records the Android repair wave that followed the first real emulator smoke attempt on `2026-04-27`.

It exists because the earlier Android notification foundation was code-complete enough to start smoke work, but the first runtime pass exposed several Android-side defects and one backend-adjacent contract gap.

Use this together with:

- `docs/42-wave-c-android-notification-entry-foundation.md`
- `docs/44-android-sdk-assembledebug-verification.md`
- `docs/45-notification-staging-smoke-runbook.md`
- `docs/47-device-registration-logical-device-upsert-repair.md`

## What Happened

During the first real local emulator smoke attempt, the team successfully reached all of the following:

- real Firebase project wiring on Android through `google-services.json`
- backend startup with PostgreSQL, scheduler, and Firebase Admin credentials
- Android debug install on the emulator
- backend user registration through `POST /api/auth/register`
- Android login against the local backend
- Android Firebase push token acquisition

The same smoke attempt also exposed Android runtime issues:

- local HTTP traffic was initially blocked by Android cleartext policy
- Firebase Gradle wiring was incomplete for the `google-services.json` path
- the notification-permission / render path produced a runtime UI crash
- Android device-registration sync behavior was too eager and risked duplicate registrations
- Russian Android copy was visibly broken by mojibake

## Repair Wave Applied

The Android repair wave then landed a focused patch set in Android scope:

- fixed Android cleartext handling for the local smoke path
- connected the Google Services Gradle plugin for the current Firebase resource path
- fixed the reused-child UI crash in notification controls
- repaired the Firebase app bootstrap mismatch in `FirebasePushCoordinator`
- tightened Android session/UI behavior after terminal `401` failures
- reduced repeated device re-registration behavior in the Android client
- preserved pending notification-open task targets until successful detail open
- restored readable Russian strings in `AuthCopy.kt`
- updated the runbook to reflect the effective Android Firebase bootstrap behavior

## Current Outcome

At the end of this repair wave, the source-of-truth status is:

Later follow-up note:

- `docs/47-device-registration-logical-device-upsert-repair.md` later re-confirmed Android `:app:assembleDebug` and closed the backend logical-device upsert gap
- the remaining unresolved gap after that follow-up is still the real post-repair smoke path

- Android login and Firebase token acquisition were operationally observed on the emulator before the repair wave finished
- the Android repair patch set is now present in the repository working tree
- the repair worker reported post-repair `:app:assembleDebug` as green
- an independent follow-up Gradle rerun from the orchestrator shell was not confirmed because the local shell hit a `native-platform.dll` initialization failure
- post-repair end-to-end Android smoke was **not yet re-run to completion**
- post-repair device registration success was **not yet re-confirmed**
- post-repair `reminder -> push -> tap -> task open` is still **not proven**

## Backend Follow-Up Status

At the moment this repair note was first written, one backend-adjacent contract issue still remained.

That follow-up has since landed in:

- `docs/47-device-registration-logical-device-upsert-repair.md`

Historical issue from this repair point:

- current device registration semantics still do not provide a true backend upsert / idempotent update path for a logical device

Practical implication:

- the Android client now avoids several unnecessary re-registration cases
- however, real token rotation or registration recovery can still leave orphan registrations without backend-side contract hardening

Recommended backend follow-up from this repair point:

- review `POST /api/devices` semantics for true idempotency / upsert behavior per logical device or token lifecycle
- review unregister / replacement expectations so Android does not need best-effort delete-then-create behavior forever
- confirm the intended FCM payload contract for background / killed-state tap-open behavior

## What Is Proven Vs Not Proven

### Proven enough to continue

- backend can start locally with PostgreSQL and Firebase Admin credentials
- Android can build and install locally
- Android can authenticate against the backend
- Android can acquire an FCM token with real Firebase wiring

### Still not proven

- post-repair Android device registration stability
- post-repair notification permission flow stability on the chosen emulator image
- real backend-triggered push delivery
- background/killed-state tap-open correctness
- full `reminder -> push -> tap -> task open`

## Exact Next Step

The next correct step is not another broad refactor.

It is a narrow re-verification pass:

1. reinstall the current Android debug app
2. re-login if needed
3. re-confirm push token presence
4. re-confirm device registration success
5. only then run the first real `reminder -> push -> tap -> task open` smoke

If the smoke still fails after this repair wave:

- create a short failure note in `docs/`
- classify the failure as Android receive, backend send, or tap-open
- fix only that narrow failing layer next
