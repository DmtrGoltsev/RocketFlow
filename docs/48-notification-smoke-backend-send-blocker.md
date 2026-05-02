# Notification Smoke Backend Send Blocker

## Purpose

This note records the first post-repair smoke pass executed after:

- the Android repair wave
- the logical-device upsert follow-up in `docs/47-device-registration-logical-device-upsert-repair.md`

It exists to separate what is now re-proven on Android from the remaining runtime blocker.

Use this together with:

- `docs/45-notification-staging-smoke-runbook.md`
- `docs/47-device-registration-logical-device-upsert-repair.md`

## Outcome

Outcome state:

- `failed_backend_send`

This classification is an inference from the evidence below:

- Android receive-side showed no RocketFlow notification
- Android logcat showed no `RocketFlowMessagingService` or Firebase receive evidence
- the same device/session path had already proven login, push token, and device registration

## What Was Re-Proven In This Pass

On `2026-04-27`, in the current local environment:

- backend `http://localhost:8080/actuator/health` returned `UP`
- Play-services-capable emulator was running
- `com.rocketflow.companion` was installed and launchable
- a fresh smoke backend user was created
- Android login was completed successfully for that smoke user
- Android produced a fresh push token for that smoke user session
- Android notification permission was granted
- Android device registration was re-confirmed end-to-end for the fresh smoke user

Observed smoke-user device registration evidence:

- user email:
  - `smoke0427161534@example.com`
- device registration id shown in the Android UI:
  - `0ac4e55b-baf5-4bd8-aea5-b0884b8f9a4a`
- push token was visible in the Android UI after login

This closes the earlier uncertainty around post-repair Android device registration stability.

## Smoke Attempts Executed

Two reminder attempts were created against the fresh runtime path.

Attempt artifacts:

1. first reminder task
- task id:
  - `ff0cb6d2-0489-436b-9ea8-3e508a472f25`
- title:
  - `Smoke push 20260427-161733`

2. traced reminder task
- task id:
  - `e7a44801-180a-407c-b6f1-a1a9a60f51a6`
- title:
  - `Smoke traced 20260427-162110`

For both attempts:

- the task was created for the same smoke user whose Android session was active
- the reminder rule was `before_planned_time`
- `offsetMinutes = 1`
- the reminder was already due or effectively due at creation time
- the Android app was backgrounded to the launcher before the traced attempt

## Evidence Captured

### Android UI Evidence

Confirmed on-device:

- active smoke-user session
- fresh push token
- active device registration
- app backgrounding to launcher before the traced attempt

### Notification-Shade Evidence

After the traced attempt:

- the notification shade opened successfully
- no RocketFlow notification row was present
- no row with the traced task title was present

### Logcat Evidence

After the traced attempt:

- no `RocketFlowMessagingService` receive trace was present
- no Firebase message-receive trace for RocketFlow was present

## Best Current Interpretation

The remaining blocker is now narrower than before.

What is no longer the blocker:

- Android login
- Android Firebase token acquisition
- Android notification permission
- Android device registration
- Android background state during the traced attempt

What is still the likely blocker:

- the currently running backend process on `localhost:8080` was not proven to be running with the intended notification scheduler and FCM runtime wiring for this smoke

Most likely sub-cases:

1. scheduler is disabled on the live backend instance
2. scheduler is enabled but FCM delivery is disabled or not wired on that live backend instance
3. backend send failed before any Android receive-side event occurred

The current session could not distinguish those sub-cases from repository-visible evidence alone because:

- the live backend process launch env was not inspectable enough
- PostgreSQL access credentials for direct `notification_deliveries` inspection were not recoverable from local repo context
- no backend notification-delivery endpoint exists

## Exact Next Step

The next correct step is now backend-runtime-specific:

1. start or restart the intended smoke backend instance with explicit env wiring, not with an unknown inherited shell state
2. ensure all of the following are set for that process:
   - `ROCKETFLOW_DB_URL`
   - `ROCKETFLOW_DB_USERNAME`
   - `ROCKETFLOW_DB_PASSWORD`
   - `ROCKETFLOW_ALLOWED_ORIGINS`
   - `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
   - `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
   - `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID=rocketflowgoltsev`
   - `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH` pointing to the non-repo Firebase Admin JSON
3. rerun `scripts/Invoke-NotificationSmokePreflight.ps1` in that exact shell
4. keep the already-registered smoke Android user/device path and rerun the traced reminder smoke

## Practical Handoff Note

The next operator does not need to rediscover Android viability.

That part is now re-proven.

The unresolved gate is specifically:

- prove the live backend send path on an explicitly configured notification-enabled backend instance

Later note:

- `docs/49-notification-smoke-firebase-auth-blocker.md` resolves the unknown-backend-runtime uncertainty from this note
- `docs/50-notification-runtime-clean-pass.md` closes the remaining path and records the final `passed` smoke
