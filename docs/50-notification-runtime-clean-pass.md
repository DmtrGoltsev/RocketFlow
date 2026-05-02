# Notification Runtime Clean Pass

## Purpose

This note records the notification runtime pass that finally proved:

- `reminder -> push -> tap -> task open`

It follows:

- `docs/48-notification-smoke-backend-send-blocker.md`
- `docs/49-notification-smoke-firebase-auth-blocker.md`

## Outcome

Outcome state:

- `passed`

## Addendum: Controlled Rerun On 2026-04-28

A later controlled rerun on `2026-04-28` reconfirmed the local Android critical path and closed the local notification gate with verdict:

- `tap-open proven`

Latest canonical evidence pack:

- `<repo-root>\tmp\notification-smoke\android-controlled-rerun-20260428-004138-final-fact-pack-20260428-005044.json`

Follow-up reconciliation notes:

- the repo-owned blocker in `scripts/Invoke-NotificationSmokeTask.ps1` is closed
- a non-blocking keyboard UX note does not reopen the notification gate

## Runtime Shape Used

On `2026-04-27`, the clean pass was executed on the same self-owned local runtime used during the earlier blocker narrowing.

Runtime used:

- temporary PostgreSQL cluster on port `55432`
- isolated database:
  - `rocketflow_smoke`
- isolated backend instance:
  - `http://localhost:18080`
- Android debug app pointing to:
  - `http://10.0.2.2:18080/api`

Confirmed backend env for the passing runtime:

- `ROCKETFLOW_DB_URL=jdbc:postgresql://localhost:55432/rocketflow_smoke`
- `ROCKETFLOW_DB_USERNAME=rocketflow_smoke`
- `ROCKETFLOW_DB_PASSWORD=<db-password>`
- `ROCKETFLOW_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY=PT15S`
- `ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY=PT5S`
- `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID=rocketflowgoltsev`
- `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH=<firebase-admin-credentials-json>`
- `ROCKETFLOW_ANDROID_API_BASE_URL=http://10.0.2.2:18080/api`

## Narrow Repo Fix That Unblocked FCM Send

The remaining blocker from `docs/49-notification-smoke-firebase-auth-blocker.md` turned out not to be an external Firebase credential problem.

It was a backend dependency-skew defect.

Observed evidence:

- manual OAuth token exchange with the new Firebase Admin JSON returned `200` with a real `access_token`
- backend still failed with:
  - `Unknown error while making a remote service call: Unexpected error refreshing access token`
- a Java-side reproduction using the backend dependency classpath failed with:
  - `NoClassDefFoundError: com/google/auth/CredentialTypeForMetrics`
- `mvn dependency:tree -Dincludes=com.google.auth -Dverbose` showed:
  - `google-auth-library-oauth2-http:1.29.0`
  - `google-auth-library-credentials:1.23.0`
  - the older credentials jar won the conflict through `google-api-client`

Narrow fix:

- pinned `com.google.auth:google-auth-library-credentials:1.29.0` in `backend/pom.xml`
- added `backend/src/test/java/com/rocketflow/notifications/GoogleAuthClasspathAlignmentTest.java`

Post-fix proof:

- Java `jshell` reproduction of `GoogleCredentials.refreshAccessToken()` succeeded with the same JSON
- backend repackaged and restarted cleanly
- notification delivery rows changed from `failed` to `sent`

## Final Clean Attempt

The final no-restart end-to-end proof used:

- task id:
  - `3f5b81e4-1ebd-4def-9eb4-f4c1b8642b2c`
- title:
  - `Smoke push pass 20260427-172515`
- reminder rule:
  - `before_planned_time`
- offset:
  - `1 minute`

Persisted delivery evidence:

- scheduled at:
  - `2026-04-27 17:27:15.209568+03`
- attempted at:
  - `2026-04-27 17:27:22.105131+03`
- status:
  - `sent`
- provider response:
  - `projects/rocketflowgoltsev/messages/0:1777300043145775%a9d4206da9d4206d`

Backend runtime evidence:

- log recorded:
  - `Reminder delivery run sent=1 failed=0 skipped=0`

Android receive evidence:

- emulator app was backgrounded to launcher before the due window
- notification shade showed:
  - title `RocketFlow reminder`
  - body `Smoke push pass 20260427-172515`
- logcat showed real Firebase receive-side activity and notification sound/render behavior

Android tap-open evidence:

- tapping the notification brought `com.rocketflow.companion/.MainActivity` to the foreground
- UI rendered the notification-open banner for:
  - `3f5b81e4-1ebd-4def-9eb4-f4c1b8642b2c`
- the task detail section rendered:
  - `Smoke push pass 20260427-172515`
  - `Status: todo`
  - `Scheduled: 2026-04-27T14:28:15.209568Z`

## Additional Passing Evidence

An earlier post-fix send also succeeded for:

- task id:
  - `697bb284-4029-4781-a70d-4cd98c5f644d`
- title:
  - `Smoke push fixed 20260427-172051`

That attempt proved:

- real backend send
- real Android notification receive
- notification-tap intent preservation across a forced re-login after backend restart

The later clean attempt above removed the restart/session artifact and closed the full path without that caveat.

## Files Changed During The Repair

- `backend/pom.xml`
- `backend/src/test/java/com/rocketflow/notifications/GoogleAuthClasspathAlignmentTest.java`

## Checks Run

- `mvn -Dtest=GoogleAuthClasspathAlignmentTest,FcmSenderConfigurationTest,FirebaseMessagingConfigurationTest test`
- `mvn test`
- `mvn -DskipTests package`
- Java `jshell` reproduction of `GoogleCredentials.refreshAccessToken()`
- real backend `/actuator/health` check on `http://localhost:18080/actuator/health`
- real emulator reminder smoke with:
  - delivered push
  - notification shade evidence
  - tap-open evidence
