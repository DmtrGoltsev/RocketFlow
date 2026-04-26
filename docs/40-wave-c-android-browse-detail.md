# Wave C Android: Browse and Read-Only Task Detail

## Scope

This slice extends the Android companion beyond auth/session into the next planned companion-only surfaces:

- owned folder browse
- owned goal browse within a folder
- owned task browse within a goal
- shared goal discovery
- shared task discovery
- read-only task detail opened from owned or shared task lists

## Implementation Notes

- the Android client keeps the existing lightweight JSON-over-HTTP stack
- protected browse/detail requests reuse the auth refresh path through `AuthRepository`
- browse and detail remain inside the current single-activity shell
- shared-resource discovery stays separate from folder ownership semantics
- task detail always uses `GET /api/tasks/{taskId}` instead of trusting list payload completeness

## Guardrails Kept

- Android remains companion-only
- no task create/edit/delete UI
- no calendar or quick-reschedule UI
- no invitation-management UI
- no push/deep-link flow yet
- no offline/cache architecture

## Delivered Surface

### Owned Browse

- folders load from `GET /api/folders`
- goals load from `GET /api/folders/{folderId}/goals`
- tasks load from `GET /api/goals/{goalId}/tasks`

### Shared Browse

- shared goals and tasks load from `GET /api/shares/resources`
- shared items are shown as discovery surfaces only
- persisted `folderId` remains a backend contract detail and is not treated as shared-folder access

### Read-Only Task Detail

- task detail loads from `GET /api/tasks/{taskId}`
- detail renders:
  - title and description
  - status, type, priority
  - planned and due times
  - shared and archived markers
  - tags
  - recurrence summary
  - reminder summary

## Files Added Or Expanded

- `android/app/src/main/java/com/rocketflow/companion/browse/**`
- `android/app/src/main/java/com/rocketflow/companion/detail/**`
- `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- `android/app/src/main/java/com/rocketflow/companion/auth/AuthRepository.kt`
- `android/app/src/main/java/com/rocketflow/companion/RocketFlowCompanionApp.kt`

## Done Criteria For This Slice

- Android can browse owned planning items needed to reach tasks
- Android can discover shared goals and shared tasks without scope creep into folder sharing
- Android can open a read-only task detail from browse
- auth/session restoration continues to work with the new protected requests

## Next Planned Step

The next Android step after this slice moved into:

- `docs/42-wave-c-android-notification-entry-foundation.md`

That follow-up covers:

- push registration
- notification receive path
- open task from notification / deep link
