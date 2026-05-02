# Wave B Backend Notifications

## Scope Delivered

- Added `V7__notifications_devices.sql` for `device_registrations` and `notification_deliveries`.
- Implemented `POST /api/devices` and `DELETE /api/devices/{deviceId}`.
- Added notification persistence, payload preparation, and an `FcmSender` abstraction under `backend/src/main/java/com/rocketflow/notifications/`.
- Added a single-instance-friendly reminder polling bridge that can be enabled with `rocketflow.notifications.scheduler.enabled=true`.
- Kept shared-task reminder delivery owner-scoped by resolving target devices from `task.ownerUserId` only.

## Device Registration Behavior

- `POST /api/devices` is idempotent-enough on `pushToken`.
- `POST /api/devices` now also accepts an optional logical `installationId` for stable app-install identity.
- Re-registering the same token reuses the same row, refreshes metadata, and marks the registration active.
- Re-registering the same logical installation with a rotated token now reuses or reconciles the existing device row instead of relying on client-side delete-then-create only.
- A token is globally unique, so if the same device token is registered by another user later, ownership moves to the latest registering user. This avoids duplicate delivery or cross-account leakage from a stale token.
- If a current token row and an older logical-installation row conflict, the token-matching row becomes canonical and the superseded installation row is retired.
- `DELETE /api/devices/{deviceId}` deactivates the caller's registration instead of hard-deleting it.

## Notification Delivery Foundation

- Due reminders are derived from the existing reminder rules plus owner timezone through `ReminderEligibilityService`.
- Delivery skips archived, `done`, and `cancelled` tasks.
- If owner notifications are disabled, one skipped delivery row is logged for that reminder occurrence.
- If the owner has no active devices, one skipped delivery row is logged for that reminder occurrence.
- If active devices exist, one delivery row is persisted per device with `sent` or `failed` status.
- Duplicate normal sends are prevented with delivery existence checks plus unique indexes on `(task_id, reminder_rule_id, scheduled_at, device_registration_id)` and the null-device skipped case.

## FCM Boundary

- `FcmSender` is intentionally small for MVP: `send(device, payload) -> SendResult`.
- The backend now has two concrete sender paths:
  - `FirebaseAdminFcmSender` is activated when Firebase Messaging is configured and available.
- `LoggingFcmSender` remains the fallback path when Firebase Messaging is absent.
- `LoggingFcmSender` behavior is intentionally explicit:
  - when `rocketflow.notifications.fcm.enabled=false` it returns a failed result with a clear provider response
  - when FCM is marked enabled but a real Firebase sender is unavailable, it logs the attempted send context and returns a failed result explaining the missing real sender
- `FirebaseMessagingConfiguration` is intentionally fail-fast for one operator error class:
  - if `rocketflow.notifications.fcm.enabled=true` but neither credentials JSON nor credentials path is provided, backend startup fails instead of silently degrading
- Firebase configuration is bound through `rocketflow.notifications.fcm.*`, including:
  - `enabled`
  - `project-id`
  - `credentials-json`
  - `credentials-path`

## Scheduler Safety Status

- Reminder delivery is still not a production-ready multi-instance system.
- The backend binds notification config through the explicit `rocketflow.notifications.*` namespace.
- The scheduler now uses a PostgreSQL advisory transaction lock before polling due reminders, which reduces duplicate-send risk during overlapping scheduler runs.
- This is a safety improvement, not full horizontal-scaling readiness.

## Test Coverage Added

- `NotificationDeliveryIntegrationTest`
  - duplicate-token registration and owner-scoped delete behavior
  - owner-only reminder delivery for shared tasks
  - delivery logging for failed sends
