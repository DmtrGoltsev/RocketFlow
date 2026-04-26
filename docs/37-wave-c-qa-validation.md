# Wave C QA Validation

## Scope

This companion QA pack covers the current Wave C surfaces:

- web `calendar / sharing / settings`
- Android auth, browse, and read-only task detail baseline

It complements:

- `docs/32-wave-c-web-collaboration-settings.md`
- `docs/34-wave-c-android-companion-foundation.md`
- `docs/35-wave-c-android-auth-session.md`
- `docs/40-wave-c-android-browse-detail.md`
- `docs/42-wave-c-android-notification-entry-foundation.md`

## Web Validation Focus

### Calendar

- `/app/calendar` loads against `GET /api/calendar`
- visible tasks match backend visibility rules for owner and collaborator paths
- move-task UI updates `plannedTime` consistently with task detail reads
- quick reschedule reflects updated `plannedTime` and priority after backend evaluation
- missing or invalid `plannedTime` paths surface stable error states

### Sharing

- `/app/sharing` can create goal and task invitations
- invitation accept / decline / revoke actions follow current backend status transitions
- shared-resource lists use discovery semantics and do not imply folder sharing
- shared goals display their persisted `folderId` contract without assuming `virtual-shared`

### Settings

- `/app/settings` loads `GET /api/me/settings`
- `PATCH /api/me/settings` preserves optimistic locking behavior
- language updates immediately keep RU/EN parity in the active client session
- notification and priority decay toggles reflect saved backend state after refresh

### Localization Discipline

- all new Wave C copy is available in both RU and EN
- route-level labels, notices, and empty/error states stay mirrored
- any feature-local copy modules are checked for RU/EN parity in the same change set

### Scheduling Authoring Follow-Up

- task create/edit can enable recurrence without leaving the planning shell
- task create/edit can replace the reminder list for a task
- detail cards render current recurrence/reminder summaries instead of placeholder copy
- validation catches anchor-time, duplicate-reminder, and interval/offset mistakes before request dispatch when possible

## Android Validation Focus

### Auth And Session

- login succeeds with valid credentials
- invalid credentials show stable error messaging
- app restart restores the session when tokens remain valid
- expired access token recovers through refresh when refresh token remains valid
- logout clears local session and returns to signed-out UI

### Android Browse And Detail

- owned folders load predictably
- goal switching inside an owned folder loads the correct owned task list
- shared goals and shared tasks load from discovery without implying folder sharing
- read-only task detail opens from both owned and shared task lists
- inaccessible or missing task paths surface stable failure UX instead of looping retries
- task detail is loaded from `GET /api/tasks/{taskId}` instead of assuming list payload completeness

### Android Notification Entry Foundation

- Android can register a device against `POST /api/devices`
- Android stores the returned `deviceId` locally for later best-effort deactivate/logout behavior
- `rocketflow://task/{taskId}` opens the existing task-detail path
- notification/deep-link task open survives signed-out state by waiting for session restore/login
- inaccessible or deleted task paths fail gracefully after notification-open entry

### Android Current Constraints

- Android remains companion-only and read-only at this stage
- push/deep-link flow is not complete yet
- no release readiness should assume Android beyond auth + browse + read-only detail baseline

## Expected Verification Commands

Backend:

- `mvn -Dtest=AuthSettingsIntegrationTest test`
- `mvn -Dtest=SharingIntegrationTest,CalendarReschedulePriorityIntegrationTest,NotificationDeliveryIntegrationTest test`
- `mvn test`

Web:

- `npm run build`

Android:

- `.\gradlew.bat assembleDebug`

## Wave C Gates

Wave C should not be treated as stable enough for the next fan-out until:

- web production build is green
- backend tests covering sharing, scheduling, and notifications remain green
- Android auth/browse/detail baseline assembles successfully once SDK is configured
- Android notification-entry foundation assembles successfully once SDK is configured
- shared-resource contract wording stays synchronized across docs and clients
- RU/EN parity is confirmed for all Wave C user-visible strings
- web scheduling authoring no longer relies on later-wave placeholders
