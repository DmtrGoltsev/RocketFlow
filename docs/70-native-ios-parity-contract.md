# RocketFlow native iOS parity contract (production V21)

Status: **frozen implementation contract**  
Baseline date: **2026-08-22**  
Baseline: production backend/web source `50a63270ae094fe08ee57b945be0930cb1115dfe`, release `sha-50a63270ae09`, Flyway **V21 (21/21)**; Android `0.1.1` (`versionCode 2`).  
Normative source: the shipped Android behavior and the V21 backend. If this document and an older product document disagree, this document controls native iOS parity. A backend contract change requires a new version of this document.

## 1. Scope and release constraints

The iOS client SHALL reproduce Android's user-visible screens, navigation, data rules, offline behavior, and V21 API behavior. Platform-specific substitutions are allowed only where Android and iOS system APIs differ; they are called out in section 14.

The current Android production base URL is:

```text
http://45.10.110.42/rocket-api
```

It is intentionally recorded without credentials. It is clear-text HTTP. iOS App Transport Security (ATS) blocks this by default. **HTTPS is a production iOS release prerequisite.** A narrowly host-scoped temporary ATS exception may be used only for controlled internal QA; `NSAllowsArbitraryLoads` is forbidden and an ATS exception is not production acceptance.

Primary implementation references:

- [Android navigation and UI](../android/app/src/main/java/com/rocketflow/companion/MainActivity.kt)
- [Android planning models](../android/app/src/main/java/com/rocketflow/companion/planning/PlanningModels.kt)
- [Android planning repository](../android/app/src/main/java/com/rocketflow/companion/planning/PlanningRepository.kt)
- [Android local database](../android/app/src/main/java/com/rocketflow/companion/planning/PlanningLocalStore.kt)
- [Android Focus repository](../android/app/src/main/java/com/rocketflow/companion/focus/FocusRepository.kt)
- [Backend controllers](../backend/src/main/java/com/rocketflow)
- [V21 release evidence](68-android-v21-companion-client.md)
- [Production deployment evidence](69-production-v21-deployment-runbook.md)

## 2. Screen, state, and navigation matrix

| Android state | iOS destination | Entry | Required content/state | Back behavior |
|---|---|---|---|---|
| `Auth` | Auth root | no valid session; terminal refresh failure | login/register mode, field errors, loading/error | system exits/root remains |
| `Planner` | Planner tab | successful auth; Home tab | owned hierarchy, shared section, pending/offline status, stable scroll anchor | system/root behavior |
| `Calendar` | Calendar tab | Calendar tab | selected month/date, date markers, selected-day list, offline/error | system/root behavior |
| `Focus` | Weekly Focus tab | Focus tab; focus deep link | current period, progress, ordered items, picker, rollover, history, cadence | system/root behavior |
| `Detail` | Task detail | task row, Calendar marker, Focus item, task deep link | task fields, checklist, tags, recurrence, reminders, links/share/actions | returns to exact origin tab: Planner, Calendar, or Focus |
| `GoalDetail` | Goal detail | Planner goal | fields, children/actions, links/share | Planner |
| `IdeaDetail` | Idea detail | Planner idea | body, event/note history, actions, links/share | Planner |
| `NoteDetail` | Note detail | Planner note | fields/actions, links/share | Planner |
| `Settings` | Settings | Planner action | language, notifications, reminder/device state | Planner |

Rules:

1. The bottom navigation has exactly `Planner`, `Calendar`, and `Focus`. Authentication is not a tab.
2. Switching top-level tabs resets the Planner scroll anchor. Returning from a detail does not.
3. A task detail remembers its origin tab. Goal, idea, note, and settings always return to Planner.
4. A task deep link opens task detail; a Focus deep link opens Focus. Invalid, inaccessible, deleted, or missing IDs show a localized nonfatal error and a usable top-level screen.
5. On process restoration, Planner/Calendar/Focus restore directly. Task detail restores only if its task is still resolvable; otherwise it restores the recorded origin. Other detail/settings screens restore Planner.
6. Calendar restores selected month/date and selected task. Planner restores expanded nodes and the stable scroll anchor defined in section 13.
7. Session loss atomically moves every screen to Auth and removes user-scoped in-memory state.

Planner rows and actions SHALL cover nested folders, goals, tasks, ideas, notes, and a separate shared-resources section. Read-only shared rows remain inspectable but suppress all write affordances. `shared`, `fullAccess`, `canCreateTasks`, `allowAuthorNoteEdits`, and entity-reference `accessible`/`redacted` flags are authoritative.

## 3. Canonical entities and wire values

Unless marked nullable (`?`), a field is required in the decoded model. IDs are UUID strings on the wire. Timestamps are ISO-8601 instants; calendar dates are `YYYY-MM-DD`; optimistic versions are signed 64-bit integers.

### 3.1 Identity and session

- `User`: `id`, `email`, `displayName`, `timezone`, `language`.
- `Tokens`: `accessToken`, `refreshToken`, `expiresAt`.
- `Session`: `user`, `tokens`.
- `language`: closed enum `ru | en`.
- No token, password, push token, or secret may be logged or included in evidence.

### 3.2 Planning

- `Folder`: `id`, `parentFolderId?`, `name`, `description`, `displayOrder:Int`, `archived:Boolean`, `shared:Boolean`, `fullAccess:Boolean`, `version`, `createdAt`, `updatedAt`.
- `Goal`: `id`, `folderId`, `name`, `description`, `status`, `archived`, `shared`, `canCreateTasks`, `fullAccess`, `version`, `createdAt`, `updatedAt`.
- `Task`: `id`, `goalId`, `title`, `description`, `type`, `priority`, `effort`, `status`, `plannedTime?`, `dueTime?`, `archived`, `shared`, `fullAccess`, `creatorUserId?`, `creatorEmail?`, `creatorDisplayName?`, `version`, `tags[]`, `checklistItems[]`, `recurrence?`, `createdAt`, `updatedAt`. Server reminder rules are not exposed in `TaskDto`; Android task alarms are local settings.
- `ChecklistItem`: `id`, `taskId`, `text`, `checked`, `displayOrder`, `version`, `createdAt`, `updatedAt`.
- `TaskTag`: `id`, `name`, `color`.
- `Idea`: `id`, `folderId`, `title`, `body`, `status`, `displayOrder`, `archived`, `shared`, `fullAccess`, `allowAuthorNoteEdits`, creator identity fields nullable, `version`, timestamps.
- `IdeaNote`: `id`, `ideaId`, `eventType`, `body`, `metadataJson`, nullable author identity, `version`, timestamps.
- `Note`: `id`, `folderId`, nullable author identity, `title`, `body`, `displayOrder`, `archived`, `shared`, `fullAccess`, `version`, timestamps.
- `EntityRef`: `type`, `id`, `title`, `subtitle?`, `status?`, `path?`, `archived?`, `accessible` (default true), `redacted` (default false).
- `EntityLink`: `id`, source and target `type/id`, `relationType`, nullable expanded source/target refs, `createdByUserId?`, `archived`, `version`, timestamps.

Closed wire enums:

| Field | Values |
|---|---|
| task `type` | `green`, `red` |
| task/goal `status` | `todo`, `in_progress`, `done`, `cancelled` |
| link entity type | `goal`, `task`, `idea`, `note` |
| link relation | `related`, `dependency` |
| local sync state | `synced`, `pendingCreate`, `pendingUpdate`, `pendingDelete`, `conflict` |

Idea `status` and idea-note `eventType` remain server-compatible opaque strings (maximum 32 characters where validated); the current create default is `active` and `note`, respectively. iOS SHALL preserve unknown values and SHALL NOT invent a narrower enum.

### 3.3 Hidden priority compatibility

`Task.priority` is a deprecated compatibility shadow, not a product field:

1. It is absent from all iOS UI, sorting, filtering, validation, analytics, accessibility text, and business decisions.
2. Missing/null reads normalize locally to `5` (`DEFAULT_SHADOW`).
3. Creates send `5` for V20 rollback compatibility. V21 ignores supplied/missing/null priority and persists `5`.
4. Updates preserve and resend the locally fetched shadow. V21 ignores that request field and preserves the stored historical value.
5. Move preserves the value; clone creates shadow `5`.
6. Hidden priority policy payloads from `/me/settings` are preserved when required by an old request shape, but remain disabled and invisible.
7. Removal requires a later contract after old Android APK and V20 rollback support are retired.

### 3.4 Recurrence and reminders

Server task recurrence:

```text
mode: daily | weekly | monthly
interval: integer >= 1
daysOfWeek: unique Java weekday names; required for weekly, empty otherwise
dayOfMonth: 1...31 for monthly, null otherwise
startAt: required instant
endAt: null or instant >= startAt
active: boolean
```

Recurrence requires task `plannedTime` or `dueTime`; `startAt` must match that source instant. Weekly rules include the owner's local weekday of `startAt`. Monthly `dayOfMonth` matches the owner's local start day. Server generation uses the owner's timezone, Monday-based weekly cycles, and skips months that do not contain the configured day (it does not clamp). An inactive rule generates no occurrences.

Android local task-alarm setting: `enabled`, `triggerAt`, `repeat`, where `repeat = none | hourly | daily | weekly | monthly`. Monthly local alarm recurrence clamps to the last valid day of a shorter month. This local alarm model is separate from server task recurrence.

## 4. HTTP, auth, and error contract

All paths below are relative to the production base URL. JSON requests send `Accept: application/json` and `Content-Type: application/json; charset=UTF-8`. Connect/read timeout is 10 seconds. Every protected endpoint sends `Authorization: Bearer <accessToken>`.

Success is any `2xx`; an empty success body decodes as `{}`. The canonical error is:

```json
{
  "error": {
    "code": "machine_code",
    "message": "human-readable message",
    "details": [{"field": "optional.field", "message": "detail"}],
    "traceId": "optional-correlation-id"
  }
}
```

The client preserves HTTP status, code, message, field details, and trace ID. Malformed error bodies become `internal_error`. Typical meanings: `400/422` validation, `401` expired/invalid auth, `403` read/write denial, `404` missing/inaccessible resource, `409` optimistic conflict, `429` throttling, `5xx` transient server failure.

Auth lifecycle:

| Method/path | Auth | Request | Response |
|---|---|---|---|
| `POST /auth/register` | none | `email`, `password` (8..200), `displayName` (<=120), `timezone` (<=64), `language:ru|en` | `200 {user,tokens}` |
| `POST /auth/login` | none | `email`, `password` | `200 {user,tokens}` |
| `POST /auth/refresh` | none | `refreshToken` | `200 {tokens}` |
| `POST /auth/logout` | none | `refreshToken` | `204`; local logout completes even if request fails |
| `GET /me` | bearer | none | `200 User` |

Exactly one serialized refresh is attempted after a protected `401`, then the original request is retried once. A terminal refresh or `/me` `401` clears only the matching current session and routes to Auth. Concurrent old-session failures must not clear a newer login. Non-401 bootstrap network failure retains the stored session and enters offline mode.

## 5. API matrix consumed by Android

Request fields marked `version` are mandatory optimistic-lock values unless the row is a local create. Nullable destination IDs mean root placement. All endpoints in this section are bearer-protected.

### 5.1 Planning CRUD, move, clone, tags, and links

| Method/path | Request | Success / client behavior |
|---|---|---|
| `GET /folders/hierarchy` | none | owned folder/goal/task tree |
| `POST /folders` | `name`, `description?`, `parentFolderId?` | Folder |
| `PUT /folders/{id}` | `name`, `description?`, `displayOrder`, `archived`, `version` | Folder |
| `DELETE /folders/{id}` | none | `204` |
| `POST /folders/{id}/move` | `targetFolderId?`, `version` | Folder |
| `POST /folders/{id}/clone` | `targetFolderId?`, `name?`, `includeChildren?` | cloned Folder |
| `POST /goals` | `folderId`, `name`, `description?`, `status?` | Goal |
| `PUT /goals/{id}` | `name`, `description?`, `status`, `archived`, `version` | Goal |
| `DELETE /goals/{id}` | none | `204` |
| `POST /goals/{id}/move` | `targetFolderId`, `version` | Goal |
| `POST /goals/{id}/clone` | `targetFolderId`, `name?` | cloned Goal |
| `POST /tasks` | task create body below | Task |
| `PUT /tasks/{id}` | task update body below | Task |
| `DELETE /tasks/{id}` | none | `204` |
| `POST /tasks/{id}/move` | `targetGoalId`, `version` | Task |
| `POST /tasks/{id}/clone` | `targetGoalId`, `title?`, `includeTags:false` | cloned Task |
| `PUT /tasks/{id}/recurrence` | recurrence body in 3.4 | `{taskId,recurrence}` |
| `POST /tasks/{id}/reschedule` | `preset:30m|1h|3h|24h` | `{task,event,priorityDecayApplied:false}` |
| `GET /task-tags` | none | TaskTag[] |
| `POST /task-tags` | `name`, `color` | TaskTag |
| `PUT /task-tags/{id}` | `name`, `color` | TaskTag |
| `DELETE /task-tags/{id}` | none | `204` |
| `GET /entity-links?entityType={type}&entityId={id}` | query | EntityLink[] |
| `POST /entity-links` | source/target type+id, `relationType` | EntityLink |
| `PATCH /entity-links/{id}` | `relationType`, `version` | EntityLink; supported by backend even if current Android UI does not expose edit |
| `DELETE /entity-links/{id}` | none | `204` |

Task create fields: `goalId`, `title` (<=200), `description?` (<=2000), `type:green|red`, compatibility `priority:5`, `effort>=0?`, `status`, `plannedTime?`, `dueTime?`, `tagIds?`, `checklistItems?`, and `recurrence?` through the dedicated recurrence endpoint. Task update additionally requires `archived` and `version`. For tags, omitted means preserve and `[]` means clear. Checklist request items contain nullable `id`, required `text` (<=500), `checked`, and `displayOrder>=0`.

| Method/path | Request | Success |
|---|---|---|
| `GET /ideas?folderId={id}` | query | Idea[] |
| `POST /ideas` | `folderId`, `title`, `body`, `status`, `allowAuthorNoteEdits` | Idea |
| `PUT /ideas/{id}` | editable fields, `archived`, `version` | Idea |
| `DELETE /ideas/{id}` | none | `204` |
| `POST /ideas/{id}/move` | `targetFolderId`, `version` | Idea |
| `POST /ideas/{id}/clone` | `targetFolderId`, `title?` | Idea |
| `GET /ideas/{id}/notes` | none | IdeaNote[] |
| `POST /ideas/{id}/notes` | `body`, `eventType`, `metadataJson` | IdeaNote |
| `PUT /ideas/{id}/notes/{noteId}` | editable fields, `version` | IdeaNote |
| `DELETE /ideas/{id}/notes/{noteId}` | none | `204` |
| `GET /notes?folderId={id}` | query | Note[] |
| `POST /notes` | `folderId`, `title`, `body` | Note |
| `PUT /notes/{id}` | editable fields, `displayOrder`, `archived`, `version` | Note |
| `DELETE /notes/{id}` | none | `204` |
| `POST /notes/{id}/move` | `targetFolderId`, `version` | Note |
| `POST /notes/{id}/clone` | `targetFolderId`, `title?` | Note |

### 5.2 Sharing, links, and invitations

`{segment}` is exactly one of `folders | goals | tasks | ideas`.

| Method/path | Request | Success |
|---|---|---|
| `POST /{segment}/{id}/share` | exactly one of `email` or `userId`, plus `fullAccess` | share/invitation result |
| `POST /{segment}/{id}/share-links` | access options supported by server | ShareLink |
| `GET /{segment}/{id}/share-links` | none | ShareLink[] |
| `GET /shares/resources` | none | shared folders/goals/tasks/ideas visible to user |
| `GET /share-invitations` | none | ShareInvitation[] |
| `POST /share-invitations/{id}/accept` | none | accepted resource |
| `POST /share-invitations/{id}/decline` | none | invitation state |
| `DELETE /share-invitations/{id}` | none | revoke, `204` |
| `GET /share-links/{token}` | none | resolved link metadata |
| `POST /share-links/{token}/accept` | none | accepted resource |
| `DELETE /share-links/{id}` | none | revoke, `204` |

The iOS surface SHALL match current Android actions: invite by email/user, create/list/revoke share links, list/revoke invitations, and resolve/accept a link. Backend accept/decline invitation routes must be retained for wire compatibility; exposing them in iOS requires matching Android product approval, not an iOS-only workflow. Redacted/inaccessible linked entities show a neutral unavailable row and never leak title/path.

## 6. Calendar contract

| Method/path | Request | Response |
|---|---|---|
| `GET /calendar?from={date}&toExclusive={date}` | half-open local-date interval; maximum 400 days | `{timezone,from,toExclusive,markers[]}` |

Marker: `markerId`, `occurrenceId`, `taskId`, `goalId?`, `kind`, `at`, `localDate`, `title`, `status`, `effort`, `recurring`. `kind = planned | deadline`; an unknown kind is displayed as planned for forward compatibility. The same task may create both kinds. Ordering within a day is `at`, then localized title, then kind. `occurrenceId` is the stable identity for a recurring occurrence; row identity must not collapse separate planned/deadline markers.

Dates and recurrence are calculated in the task owner's timezone returned by the API. Range semantics are `[from,toExclusive)`. Up to 10,000 generated occurrences are allowed server-side. Selecting a date shows its markers; selecting a marker opens task detail and preserves Calendar as the return destination.

Calendar caches exact requested ranges in the user-scoped database. On non-401 failure, iOS returns an exact-range cache if present, otherwise an empty offline month with an error. `401` follows the auth lifecycle and is never silently converted to cache success.

## 7. Weekly Focus contract

### 7.1 Model and period semantics

- `FocusPeriod`: `id`, `weekStart`, `weekEndExclusive`, `startsAt`, `endsAt`, `timezone`, `status`, `version`, ordered `items[]`, optional `rolloverOffer`.
- `FocusItem`: `id`, `taskId`, `title`, `status`, nullable raw `effort`, `effectiveWeight=max(effort,1)`, `plannedTime?`, `dueTime?`, `position`, `displayOrder`, `historyOnly`, folder/goal IDs and titles, `path`, `shared`, `canWrite`.
- `Progress`: `completedWeight`, `totalWeight`, rounded and clamped integer `percent`, `completedCount`, `totalCount`. Current-progress calculations exclude `historyOnly`; zero total means 0%.
- `HistorySummary`: period identity/range/timezone/status/version/progress. History detail is immutable period content.
- Period weeks are server-created in the user's timezone and represented as `[weekStart,weekEndExclusive)`; the server's period/version is authoritative.
- Rollover is an explicit offer from a prior period. Only selected offered `taskIds` are resolved into the current period; no implicit carry-over.

### 7.2 API and picker

| Method/path | Request | Response |
|---|---|---|
| `GET /focus/current` | none | FocusPeriod |
| `GET /focus/candidates?q=&folderId=&goalId=&cursor=&limit=` | opaque cursor, Android uses up to 100 | candidate page |
| `PUT /focus/current/items/{taskId}` | `periodVersion?`, `idempotencyKey?` | FocusPeriod |
| `DELETE /focus/current/items/{taskId}` | JSON body with `periodVersion?`, `idempotencyKey?` | FocusPeriod |
| `PATCH /focus/current/items/order` | ordered `taskIds`, `periodVersion?`, `idempotencyKey?` | FocusPeriod |
| `POST /focus/rollovers/{sourcePeriodId}/resolve` | selected `taskIds`, `periodVersion?`, `idempotencyKey?` | FocusPeriod |
| `GET /focus/history` | none | HistorySummary[] |
| `GET /focus/history/{periodId}` | none | FocusPeriod |
| `GET /focus/notification-settings` | none | settings |
| `PATCH /focus/notification-settings` | cadence/quiet fields, `version?`, `idempotencyKey?` | settings |

Candidate data is server-authoritative and grouped in the picker by folder then goal, with localized title sorting inside a group. Search uses server `q`; cursor is opaque and must never be parsed. Already selected tasks are disabled/omitted. Shared read-only candidates remain visible only when the server marks them eligible.

Notification settings: `intervalMinutes?` is one of `null,30,60,120,240`; `null` disables cadence. `quietStart` and `quietEnd` are either both null or both valid `HH:mm`. Defaults are 120, 22:00, and 08:00. Quiet hours use the period/user timezone and may cross midnight.

### 7.3 Focus offline and conflicts

Add, remove, reorder, rollover, and settings changes are optimistic and queued locally. Each pending action has a UUID reused as `idempotencyKey` and carries the expected period/settings version. A connected background worker sends actions in order.

- Network failure, `429`, or `5xx`: retain action and retry with WorkManager/backoff equivalent.
- `401`: run the auth lifecycle; terminal auth failure stops sync.
- `409`: refresh server state, remove the action if its effect is already present, otherwise rebase and retry up to three times. After the third conflict, mark a terminal issue and accept server state.
- Other `4xx`: refresh server state, terminalize the action, do not retry.
- Current/history/settings use user-scoped cache on non-401 read failure and expose offline plus pending/terminal issue state.

## 8. General offline database, pending operations, and sync

iOS SHALL use a durable user-scoped database equivalent to Android SQLite. It stores folders, goals, tasks, checklist items, tags, ideas, idea notes, notes, entity links, calendar range/markers, Focus periods/items/settings, and pending Focus actions. Never display one user's cache after account switch.

Folder, goal, task, note, entity-link create/delete, and task-tag mutations are local-first. Local creates use client IDs. Updates coalesce into the pending row; deleting an unsynced create removes it and its dependents locally; deleting a synced entity creates a pending tombstone. Ideas and idea notes follow current Android behavior and require immediate network success; they are cached but are not added to the generic planning mutation queue.

Planning push order is deterministic: tags, folders parent-first, goals after folders, tasks after goals, notes after folders, then links after both endpoints exist. Pull follows push and replaces authoritative owned/shared data while preserving unresolved local rows. Optional idea/note/link pull failure does not discard a successfully loaded core hierarchy.

Planning conflict and retry rules:

| Failure | Required result |
|---|---|
| offline/I/O/timeout, `429`, `5xx` | retain pending op, expose last error, connected worker retries |
| `400`, `403`, `404`, `409`, `422` or server conflict code | mark row `conflict`, block automatic replay, expose reset/recovery action |
| create dependency not yet remote | leave pending until dependency succeeds |
| update/delete reset | discard local pending change and refresh remote; missing remote removes local row |
| missing destination folder for goal recovery | allow explicit move to root/recovery destination where Android does |
| `401` | auth lifecycle; never label as ordinary offline success |

The planning worker requires network connectivity and makes at most five retry attempts for one scheduled run. UI refresh calls `push -> pull` under a mutex. Snapshot exposes `pendingCount`, pending issues, `offline`, and `lastSyncError`. Version conflicts are user-resolved/server-reset in Planning; Focus alone has the three-attempt automatic rebase described above.

## 9. CRUD behavior and permissions

1. Create/edit forms validate the same maximum lengths and enums as the API, retain user input on error, and map field errors to the matching control.
2. Move forbids a folder becoming its own descendant and offers only writable valid destinations. Goal/task/idea/note moves preserve entity identity and version semantics.
3. Clone creates new identity/version/timestamps. Folder clone may include children; task clone passes `includeTags:false`; recurrence/reminder behavior follows the server response, never client assumptions.
4. Archive is an update field, not a local hide-only action. Archived/closed/completed tasks do not schedule local reminders.
5. `fullAccess=false` and `canWrite=false` suppress edit, move, delete, reorder, share, and writable-link actions. `canCreateTasks` independently controls task creation in shared goals.
6. Creator identity fields are nullable and must have a localized neutral fallback.
7. Optimistic updates send the last server `version`; a successful response replaces the local version.

## 10. Notifications, reminders, deep links, and settings

Deep-link routes are frozen:

```text
rocketflow://task/{taskId}
rocketflow://focus
```

Notification data types are `task_reminder` and `focus_reminder`. Focus push is data-only and includes `periodId` and `eventId`; duplicate Focus events are suppressed for 14 days. Task notifications require `taskId`. Tapping routes through the auth gate, then to task detail or Focus.

Android task alarms use a high-importance public alarm channel, alarm sound/vibration, `setAlarmClock` when permitted, then exact-while-idle, then inexact fallback. They are rescheduled after boot, app resume, time/timezone change, package replacement, and exact-alarm permission change. One-shot settings clear after delivery; repeating settings advance and reschedule. Done/cancelled/archived/missing tasks clear alarms.

Focus notifications use a standard private channel and server cadence/quiet-hours settings. Android requests runtime notification permission on API 33+ and registers a device with:

| Method/path | Request/response |
|---|---|
| `POST /devices` | request `platform:"android"`, `pushToken`, `installationId`, `deviceName`; response registration identity/state |
| `DELETE /devices/{id}` | `204`; `404` also clears matching local registration |

Registration is scoped by authenticated user and token; stale same-user registration is deleted before replacement, and an old account's registration is never deleted under a new account.

Settings parity includes language (`ru|en`), `notificationsEnabled`, Focus cadence/quiet hours, local task reminder default/current values, runtime notification authorization state, and device-registration state. `/me/settings` GET/PATCH uses `language`, `notificationsEnabled`, and `version`; deprecated priority-policy data is preserved/disabled as in 3.3 and is never shown.

## 11. Scroll, back, tab reset, and restoration

Planner scroll state is a tuple: first visible stable row (`folder|goal|task|idea|note` + ID), pixel offset, fallback absolute Y, and expanded-node state. Restore order is exact row, nearest visible ancestor, fallback Y, then clamped bounds. It survives expand/collapse, edit/detail round trips, refresh, insertion above, background/foreground, and recreation.

The anchor resets only on explicit top-level tab switch, sign-out, or user-data clear. A pull must not jump to top. Stable IDs, not localized text or list indexes, identify rows.

Back rules are those in section 2. Keyboard dismissal is handled before navigation only when that is the native control behavior; Save and Cancel remain reachable without requiring keyboard dismissal.

## 12. Localization, accessibility, keyboard, and rotation

- Every shipped string, validation message, date label, status, empty/error/offline state, notification, and accessibility label is available in Russian and English. Server opaque values use localized fallback text without mutation.
- Date/time rendering uses user locale and timezone; API values remain ISO/date wire formats.
- Every actionable control has a VoiceOver name, role/trait, value/state, and deterministic focus order. Icon-only controls have localized labels. Color is never the sole status cue.
- Content supports iOS Dynamic Type without clipped labels or overlapping actions. Interactive targets are at least 44x44 points. Read-only/disabled state is announced.
- Auth and editor fields expose suitable keyboard type, secure entry, autofill/content type, return-key behavior, and error association. Passwords/tokens are never spoken or logged unexpectedly.
- In portrait and compact landscape with the software keyboard open, focused title/body fields remain visible in a genuinely scrollable viewport and Save/Cancel remain reachable without closing the keyboard. Content uses keyboard safe-area/inset updates, not a fixed guessed keyboard height.
- Rotation preserves form draft, focus, selected top-level tab, Calendar month/date, task-detail origin, expanded nodes, and Planner anchor. It must not duplicate a mutation, notification, or pending operation.
- Modal/dialog content remains reachable at largest supported text size; no actionable content may sit behind the keyboard, home indicator, notch, or system bars.

## 13. iOS-only platform substitutions

These are the only expected platform deviations:

1. Use Keychain for access/refresh tokens and installation identity; Android secure-preference implementation details are not copied.
2. Use `UNUserNotificationCenter` standard local/remote notifications, actions, and deep-link routing. iOS has no Android full-screen alarm equivalent; task reminders SHALL be normal time-sensitive notifications where entitlement/policy permits, otherwise standard alerts. Delivery timing remains OS best effort.
3. Use `UNCalendarNotificationTrigger`/`UNTimeIntervalNotificationTrigger` for local repeats while preserving the recurrence semantics in 3.4. Reconcile pending requests on launch, timezone change, settings change, and task-state change.
4. Use APNs token registration. The V21 backend currently validates device `platform` as exactly `android`; adding `ios` and APNs delivery/token semantics is a backend prerequisite and versioned contract change. iOS must not masquerade as Android.
5. Use Universal Links only after associated domains and HTTPS exist. The custom `rocketflow` scheme and route semantics remain mandatory for V21 parity.
6. Use ATS as described in section 1; broad clear-text exceptions are forbidden.

No iOS-only data model, navigation destination, sync policy, conflict policy, or product action is permitted under this contract.

## 14. Acceptance matrix and required evidence

Each ID is release-blocking unless explicitly marked backend prerequisite. Evidence must name app build, backend release, device/iOS version, locale, orientation, account, UTC timestamp, and artifact path. Screenshots must contain no secrets or unrelated personal data.

| ID | Acceptance | Required evidence |
|---|---|---|
| `IOS-AUTH-001` | register/login/logout and restored session match section 4 in RU and EN | UI recording, redacted HTTP trace, unit/UI tests |
| `IOS-AUTH-002` | one serialized refresh/retry; terminal 401 clears only owning session | deterministic concurrent unit test and trace |
| `IOS-AUTH-003` | tokens in Keychain; no secrets in logs/evidence | storage inspection statement and sanitized log scan |
| `IOS-PLAN-001` | hierarchy renders owned/shared nested content and permissions exactly | seeded-account screenshots and API fixture comparison |
| `IOS-PLAN-002` | folder/goal/task/note CRUD, archive, move, clone, tags/checklist succeed with versions | integration test matrix and before/after API snapshots |
| `IOS-PLAN-003` | hidden priority has no UI/business effect and follows shadow rules | UI search, create/update/clone wire assertions, unit tests |
| `IOS-PLAN-004` | local-first operations survive kill/relaunch and sync in dependency order | offline recording, DB/pending dump, final server snapshot |
| `IOS-PLAN-005` | permanent conflict blocks; retryable errors remain queued; reset works | injected 409/422/429/5xx tests and UI evidence |
| `IOS-PLAN-006` | idea/idea-note network-required behavior matches Android | offline/online UI tests and request trace |
| `IOS-NAV-001` | all destinations, origin-aware task back, and tab reset match section 2 | full navigation UI test and recording |
| `IOS-NAV-002` | task/focus deep links handle auth, missing and inaccessible resources | cold/warm launch UI tests |
| `IOS-SCROLL-001` | stable anchor survives every event in section 11 and resets only on listed events | automated anchor assertions plus before/after video |
| `IOS-CAL-001` | `[from,toExclusive)`, timezone, planned/deadline, recurring identities and ordering match API | seeded recurrence fixtures, JSON, month screenshots |
| `IOS-CAL-002` | exact-range cache works offline; 401 is not hidden | network fault UI/integration tests |
| `IOS-FOCUS-001` | period boundaries, weighted progress, history-only exclusion and history match server | fixture/unit tests and current/history screenshots |
| `IOS-FOCUS-002` | picker grouping/search/cursor/add/remove/reorder/rollover match Android | UI recording and request sequence |
| `IOS-FOCUS-003` | idempotency, ordered queue, 409 three-attempt rebase, terminal/server-win behavior | deterministic repository tests and pending-action dump |
| `IOS-FOCUS-004` | cadence options, quiet hours and offline settings match section 7 | boundary-time tests in two timezones and UI screenshots |
| `IOS-SHARE-001` | invite/share-link/resource flows and read/write restrictions match section 5.2 | two-account integration tests and redaction screenshots |
| `IOS-LINK-001` | related/dependency links, inaccessible refs and delete behavior match | API/UI tests with deleted and inaccessible target |
| `IOS-REM-001` | local reminder scheduling/repeat/cancel/deep link match semantics | pending-request dump, delivery recording, state-transition tests |
| `IOS-PUSH-001` | Focus APNs dedupe/deep link and account-scoped registration work | backend prerequisite completed; APNs trace and 14-day dedupe test |
| `IOS-SET-001` | language, notifications, cadence, reminder state and hidden settings persist correctly | RU/EN UI tests and settings request fixtures |
| `IOS-A11Y-001` | VoiceOver traversal/labels/states, 44pt targets, contrast/non-color cues pass | Accessibility Inspector report and narrated recording |
| `IOS-A11Y-002` | largest Dynamic Type has no clipping/overlap and all actions remain reachable | portrait/landscape screenshot set |
| `IOS-IME-001` | portrait title/body remain visible and Save/Cancel reachable with keyboard open | screenshot, hierarchy dump, UI test |
| `IOS-IME-002` | compact landscape title/body remain visible in scroll viewport and Save/Cancel reachable without hiding keyboard | screenshot, hierarchy dump, UI test |
| `IOS-ROT-001` | rotation preserves draft/navigation/calendar/anchor and creates no duplicate op | rotation UI test, DB/pending count evidence |
| `IOS-OFFLINE-001` | account-scoped caches never cross users; kill/relaunch retains valid pending work | two-account offline test and sanitized DB inspection |
| `IOS-NET-001` | canonical errors/field details/trace IDs render safely; 429/5xx policy is correct | stub-server unit/integration matrix |
| `IOS-SEC-001` | HTTPS/ATS production path passes; no broad ATS exception | release plist, ATS diagnostic, production request trace |
| `IOS-LOC-001` | complete RU/EN string coverage and locale/timezone date behavior | localization audit and two-timezone screenshots |

## 15. Definition of done

Native iOS parity is complete only when:

1. Every non-prerequisite acceptance ID above is green with archived evidence.
2. `IOS-PUSH-001` has the versioned backend `ios`/APNs extension; `IOS-SEC-001` has HTTPS. Neither may be waived for production.
3. Contract/API tests use V21 fixtures, including unknown nullable/opaque values and hidden priority compatibility.
4. Unit, repository, database migration, UI, accessibility, localization, rotation, offline, and notification suites pass on the minimum supported iOS and current release iOS.
5. A clean production-like account completes auth, Planner, Calendar, Focus, sharing, links, reminders, and deep links without crash, data loss, inaccessible controls, cross-account leakage, or secret-bearing logs.
6. Any deliberate difference from Android is listed in section 13 and backed by an iOS API limitation; product divergence requires a new approved contract version.
