# Wave B Backend Notifications

## Scope Delivered

- Added `V7__notifications_devices.sql` for `device_registrations` and `notification_deliveries`.
- Implemented `POST /api/devices` and `DELETE /api/devices/{deviceId}`.
- Added notification persistence, payload preparation, and a minimal `FcmSender` abstraction under `backend/src/main/java/com/rocketflow/notifications/`.
- Added a single-instance-friendly reminder polling bridge that can be enabled with `rocketflow.notifications.scheduler.enabled=true`.
- Kept shared-task reminder delivery owner-scoped by resolving target devices from `task.ownerUserId` only.

## Device Registration Behavior

- `POST /api/devices` is idempotent-enough on `pushToken`.
- Re-registering the same token reuses the same row, refreshes metadata, and marks the registration active.
- A token is globally unique, so if the same device token is registered by another user later, ownership moves to the latest registering user. This avoids duplicate delivery or cross-account leakage from a stale token.
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
- The default `LoggingFcmSender` is a stubbed implementation:
  - when `rocketflow.notifications.fcm.enabled=false` it returns a failed result with a clear provider response
  - when enabled it logs the send intent and returns a stub success
- This keeps the backend contract stable for Android and backend tests without introducing external messaging infrastructure or extra rollout complexity during the frozen MVP window.

## Test Coverage Added

- `NotificationDeliveryIntegrationTest`
  - duplicate-token registration and owner-scoped delete behavior
  - owner-only reminder delivery for shared tasks
  - delivery logging for failed sends
