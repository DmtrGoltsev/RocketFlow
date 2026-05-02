# Agent Notification Runtime Playbook

## Purpose

This is the shortest reliable playbook for an agent chat to re-prove RocketFlow notification runtime without asking the user for operational steps.

Target proof:

- `reminder -> push -> tap -> task open`

Use this together with:

- `README.md`
- `docs/33-current-state-summary.md`
- `docs/45-notification-staging-smoke-runbook.md`
- `docs/50-notification-runtime-clean-pass.md`

## Hard Rules

- do not trust an unknown backend already running on `localhost:8080`
- prefer a self-owned backend runtime with explicit env
- run preflight in the same shell context that launches backend
- keep the final login, push receive, and tap proof on the same runtime without restarting backend between those steps
- treat `notification_deliveries` as the primary source of truth for backend send outcome

## Known-Good Runtime Shape

The path proven on `2026-04-27` used:

- PostgreSQL on `localhost:55432`
- backend on `http://localhost:18080`
- Android API base:
  - `http://10.0.2.2:18080/api`
- scheduler overrides:
  - `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY=PT15S`
  - `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY=PT5S`

## Verification Sequence

1. Read the current state first.
   - `README.md`
   - `docs/33-current-state-summary.md`
   - `docs/45-notification-staging-smoke-runbook.md`
   - `docs/50-notification-runtime-clean-pass.md`

2. Verify local tool paths before debugging app code.
   - locate `adb.exe`
   - locate `psql.exe`
   - locate the Firebase Admin JSON outside version control

3. If backend notification code or dependencies changed, run backend verification first.
   - `mvn test`
   - if the change is narrow, run a targeted test first and the full suite after the fix

4. Start an owned backend runtime with explicit env.
   - set DB env
   - set `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
   - set `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
   - set `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID=rocketflowgoltsev`
   - set `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH=<absolute-json-path>`
   - set `ROCKETFLOW_ANDROID_API_BASE_URL=http://10.0.2.2:18080/api`
   - do not reuse an inherited shell state you did not prove
   - preferred command:
     - `powershell -ExecutionPolicy Bypass -File .\scripts\Start-NotificationSmokeBackend.ps1`

5. Keep preflight and startup in that same env.
   - `Start-NotificationSmokeBackend.ps1` already runs `Invoke-NotificationSmokePreflight.ps1` by default
   - only call the preflight directly when you are debugging config before backend startup

6. Confirm backend health before touching Android.
   - `/actuator/health` must return `UP`
   - the startup script should wait for this automatically unless `-SkipHealthWait` was used

7. Install the Android debug app against the owned backend.
   - use the same `ROCKETFLOW_ANDROID_API_BASE_URL`
   - grant notification permission if needed

8. Log in or restore a smoke user session on Android.
   - confirm session is active
   - confirm a real Firebase token is visible
   - confirm active device registration exists

9. Prefer the repo-backed smoke-task helper over manual API calls.
   - `powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokeTask.ps1 -Email <smoke-user> -Password <password>`
   - add `-RegisterIfMissing` only for first-time smoke-user bootstrap
   - keep the default lead window unless you are deliberately debugging a slower path
   - the helper reuses or creates a stable smoke folder and goal, confirms active device registration, creates one reminder task, and can wait for `notification_deliveries`

10. Move Android to the launcher and clear `logcat`.
   - background the app before the due window
   - clear `logcat` so receive-side evidence is fresh

11. Wait through the due window plus one scheduler poll.

12. Collect outcome in this order:
   - the JSON report from `tmp/notification-smoke/smoke-task-*.json`
   - `notification_deliveries` row for the task
   - backend log tail
   - Android `logcat`
   - notification shade UI dump

13. If backend outcome is `sent` and the notification is visible, tap it immediately.
   - confirm `com.rocketflow.companion/.MainActivity` reaches foreground
   - confirm the notification/deep-link banner contains the expected `taskId`
   - confirm the task detail section contains the same task title

14. Record the result in `docs/`.
   - use exactly one outcome:
     - `passed`
     - `blocked_external_config`
     - `failed_backend_send`
     - `failed_android_receive`
     - `failed_tap_open`

## Debug Heuristics That Saved Time

- if the backend says `Unexpected error refreshing access token`, do not assume the Firebase JSON is bad
- first test manual OAuth token minting outside Java
- if manual OAuth works, inspect backend dependency alignment:
  - `mvn dependency:tree -Dincludes=com.google.auth -Dverbose`
- if Java classpath reproduction fails with:
  - `NoClassDefFoundError: com/google/auth/CredentialTypeForMetrics`
  - fix dependency skew before reopening Firebase or Android debugging
- if backend row is `sent` but Android shows no notification, only then debug Android receive path
- if tap opens the app but the screen looks wrong, verify whether the session changed or expired between login and tap

## Minimal Evidence Checklist

- backend health `UP`
- active smoke-user session
- visible Firebase token
- active device registration
- JSON smoke-task report when the helper script was used
- one `notification_deliveries` row for the smoke task
- backend outcome `sent` or exact failure reason
- notification shade evidence
- foreground `MainActivity` after tap
- task detail evidence for the intended task

## Current Best Use

Use this playbook when:

- another agent needs to repeat the notification proof
- a narrow backend or Android notification fix needs re-verification
- a new chat must continue the notification runtime path without reconstructing the old thread
- the owned backend runtime and smoke-task setup should be repeated from repo-backed tooling
