# RocketFlow API Contracts

## 1. Purpose

This document defines the MVP API contracts for RocketFlow.

Its purpose is to give backend, web, Android, QA, and future implementation subagents one stable source for:
- endpoint shape
- request payloads
- response payloads
- authentication behavior
- error behavior
- DTO naming and field direction

This document defines the target contract for MVP. Small technical adjustments are allowed during implementation, but they must be documented if they materially change behavior.

## 2. API Style

The RocketFlow API is:
- REST-oriented
- JSON-based
- authenticated for protected resources
- versionable

Recommended base path:
- `/api`

Recommended future-proof versioning rule:
- keep MVP under `/api`
- introduce `/api/v2` only when a real breaking change requires it

## 3. Common API Rules

### Content Type

Requests and responses use:
- `application/json`

Exceptions:
- no multipart upload is needed in MVP

### Timestamps

All timestamps should use ISO 8601 format with timezone awareness.

Examples:
- `2026-04-26T18:30:00Z`
- `2026-04-26T21:30:00+03:00`

Canonical time rules:
- user account stores an IANA timezone such as `Europe/Moscow`
- planned and due times are transmitted as instants with offsets
- recurrence and reminder calculations use the owner's canonical timezone
- timezone changes affect future calculations only

### Identifiers

All resource identifiers should be opaque IDs.

Recommended direction:
- `UUID`

### Pagination

For MVP:
- pagination is optional for small collections
- larger list endpoints may later adopt `page`, `size`, `sort`

### Sorting

Default sorting should be deterministic.

Examples:
- folders by `displayOrder`, then `createdAt`
- goals by `createdAt`
- tasks by `plannedTime`, then `priority`, then `createdAt`

## 4. Authentication Contract

### Auth Model

Authentication uses:
- email
- password
- access token
- refresh token

Recommended token transport:
- bearer token in `Authorization` header

Example:
- `Authorization: Bearer <access-token>`

### Register

`POST /api/auth/register`

Request:
```json
{
  "email": "user@example.com",
  "password": "strong-password",
  "displayName": "Dmitry",
  "timezone": "Europe/Moscow",
  "language": "ru"
}
```

Response `201 Created`:
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "displayName": "Dmitry",
    "timezone": "Europe/Moscow",
    "language": "ru",
    "createdAt": "2026-04-26T18:30:00Z"
  },
  "tokens": {
    "accessToken": "jwt-or-equivalent",
    "refreshToken": "opaque-or-jwt",
    "expiresAt": "2026-04-26T19:00:00Z"
  }
}
```

### Login

`POST /api/auth/login`

Request:
```json
{
  "email": "user@example.com",
  "password": "strong-password"
}
```

Response `200 OK`:
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "displayName": "Dmitry",
    "timezone": "Europe/Moscow",
    "language": "ru"
  },
  "tokens": {
    "accessToken": "jwt-or-equivalent",
    "refreshToken": "opaque-or-jwt",
    "expiresAt": "2026-04-26T19:00:00Z"
  }
}
```

### Refresh Token

`POST /api/auth/refresh`

Request:
```json
{
  "refreshToken": "opaque-or-jwt"
}
```

Response `200 OK`:
```json
{
  "tokens": {
    "accessToken": "jwt-or-equivalent",
    "refreshToken": "opaque-or-jwt",
    "expiresAt": "2026-04-26T20:00:00Z"
  }
}
```

### Logout

`POST /api/auth/logout`

Request:
```json
{
  "refreshToken": "opaque-or-jwt"
}
```

Response `204 No Content`

## 5. Common Response DTOs

### UserSummary

```json
{
  "id": "uuid",
  "email": "user@example.com",
  "displayName": "Dmitry",
  "timezone": "Europe/Moscow",
  "language": "ru"
}
```

### FolderDto

```json
{
  "id": "uuid",
  "name": "Work",
  "description": "Main work area",
  "displayOrder": 1,
  "archived": false,
  "shared": false,
  "version": 0,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### GoalDto

```json
{
  "id": "uuid",
  "folderId": "uuid",
  "name": "Promotion",
  "description": "Grow into the next role",
  "archived": false,
  "shared": true,
  "version": 0,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### TaskDto

```json
{
  "id": "uuid",
  "goalId": "uuid",
  "title": "Prepare promotion plan",
  "description": "Outline achievements and next steps",
  "type": "green",
  "priority": 8,
  "status": "todo",
  "plannedTime": "2026-04-27T09:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "archived": false,
  "shared": false,
  "version": 0,
  "tags": [
    {
      "id": "uuid",
      "name": "career",
      "color": "#4f6b9a"
    }
  ],
  "recurrence": {
    "mode": "weekly",
    "interval": 1,
    "daysOfWeek": ["MONDAY"]
  },
  "reminders": [
    {
      "id": "uuid",
      "mode": "before_planned_time",
      "offsetMinutes": 60,
      "active": true
    }
  ],
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### ShareInvitationDto

```json
{
  "id": "uuid",
  "targetType": "goal",
  "targetId": "uuid",
  "targetEmail": "collaborator@example.com",
  "targetUserId": "uuid",
  "status": "pending",
  "createdAt": "2026-04-26T18:30:00Z",
  "expiresAt": "2026-05-03T18:30:00Z"
}
```

### PriorityDecayPolicyDto

```json
{
  "taskType": "green",
  "enabled": true,
  "thresholdPreset": "day",
  "decayAmount": 1
}
```

### UserSettingsDto

```json
{
  "language": "ru",
  "greenPriorityDecayPolicy": {
    "taskType": "green",
    "enabled": true,
    "thresholdPreset": "day",
    "decayAmount": 1
  },
  "redPriorityDecayPolicy": {
    "taskType": "red",
    "enabled": true,
    "thresholdPreset": "week",
    "decayAmount": 1
  },
  "notificationsEnabled": true
}
```

## 6. Error Model

### Error Response Shape

All API errors should return a consistent structure.

```json
{
  "error": {
    "code": "validation_error",
    "message": "The request contains invalid fields.",
    "details": [
      {
        "field": "email",
        "message": "Email is required."
      }
    ],
    "traceId": "uuid"
  }
}
```

### Recommended Error Codes

- `validation_error`
- `authentication_failed`
- `unauthorized`
- `forbidden`
- `not_found`
- `conflict`
- `invalid_state`
- `rate_limited`
- `internal_error`

### Status Code Rules

- `400 Bad Request` for malformed payloads
- `401 Unauthorized` for missing or invalid auth
- `403 Forbidden` for access denied
- `404 Not Found` for missing resources
- `409 Conflict` for duplicate or conflicting state
- `422 Unprocessable Entity` when payload is structurally valid but violates a business rule

Concurrency rule:
- mutable entities use optimistic locking with a `version` field
- stale update attempts must return `409 Conflict`

## 7. Me and Settings API

### Get Current User

`GET /api/me`

Response `200 OK`:
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "displayName": "Dmitry",
  "timezone": "Europe/Moscow",
  "language": "ru"
}
```

### Get Settings

`GET /api/me/settings`

Response `200 OK`:
```json
{
  "language": "ru",
  "greenPriorityDecayPolicy": {
    "taskType": "green",
    "enabled": true,
    "thresholdPreset": "day",
    "decayAmount": 1
  },
  "redPriorityDecayPolicy": {
    "taskType": "red",
    "enabled": true,
    "thresholdPreset": "week",
    "decayAmount": 1
  },
  "notificationsEnabled": true
}
```

### Update Settings

`PATCH /api/me/settings`

Request:
```json
{
  "language": "en",
  "greenPriorityDecayPolicy": {
    "enabled": true,
    "thresholdPreset": "day",
    "decayAmount": 1
  },
  "redPriorityDecayPolicy": {
    "enabled": true,
    "thresholdPreset": "month",
    "decayAmount": 1
  },
  "notificationsEnabled": true
}
```

Response `200 OK`:
```json
{
  "language": "en",
  "greenPriorityDecayPolicy": {
    "taskType": "green",
    "enabled": true,
    "thresholdPreset": "day",
    "decayAmount": 1
  },
  "redPriorityDecayPolicy": {
    "taskType": "red",
    "enabled": true,
    "thresholdPreset": "month",
    "decayAmount": 1
  },
  "notificationsEnabled": true
}
```

## 8. Folder API

### List Folders

`GET /api/folders`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "name": "Work",
      "description": "Main work area",
      "displayOrder": 1,
      "archived": false,
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:30:00Z"
    }
  ]
}
```

### Create Folder

`POST /api/folders`

Request:
```json
{
  "name": "Work",
  "description": "Main work area"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "name": "Work",
  "description": "Main work area",
  "displayOrder": 1,
  "archived": false,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### Update Folder

`PATCH /api/folders/{folderId}`

Request:
```json
{
  "name": "Work Projects",
  "description": "Priority work area",
  "displayOrder": 2,
  "archived": false,
  "version": 0
}
```

Response `200 OK`:
```json
{
  "id": "uuid",
  "name": "Work Projects",
  "description": "Priority work area",
  "displayOrder": 2,
  "archived": false,
  "version": 1,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:31:00Z"
}
```

### Delete Folder

`DELETE /api/folders/{folderId}`

Response:
- `204 No Content`

Business note:
- `DELETE` performs a soft delete in MVP and is backed by archive-like behavior

## 9. Goal API

### List Goals in Folder

`GET /api/folders/{folderId}/goals`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "folderId": "uuid",
      "name": "Promotion",
      "description": "Grow into the next role",
      "archived": false,
      "shared": true,
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:30:00Z"
    }
  ]
}
```

### Create Goal

`POST /api/folders/{folderId}/goals`

Request:
```json
{
  "name": "Promotion",
  "description": "Grow into the next role"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "folderId": "uuid",
  "name": "Promotion",
  "description": "Grow into the next role",
  "archived": false,
  "shared": false,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### Get Goal

`GET /api/goals/{goalId}`

Response `200 OK`:
```json
{
  "id": "uuid",
  "folderId": "uuid",
  "name": "Promotion",
  "description": "Grow into the next role",
  "archived": false,
  "shared": true,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### Update Goal

`PATCH /api/goals/{goalId}`

Request:
```json
{
  "name": "Promotion 2026",
  "description": "Move into the next role this year",
  "archived": false,
  "version": 0
}
```

Response `200 OK`:
```json
{
  "id": "uuid",
  "folderId": "uuid",
  "name": "Promotion 2026",
  "description": "Move into the next role this year",
  "archived": false,
  "shared": true,
  "version": 1,
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:32:00Z"
}
```

### Delete Goal

`DELETE /api/goals/{goalId}`

Response:
- `204 No Content`

## 10. Task API

### List Tasks in Goal

`GET /api/goals/{goalId}/tasks`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "goalId": "uuid",
      "title": "Prepare promotion plan",
      "description": "Outline achievements and next steps",
      "type": "green",
      "priority": 8,
      "status": "todo",
      "plannedTime": "2026-04-27T09:00:00+03:00",
      "dueTime": "2026-04-28T18:00:00+03:00",
      "archived": false,
      "shared": false,
      "version": 0,
      "tags": [],
      "recurrence": null,
      "reminders": [],
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:30:00Z"
    }
  ]
}
```

### Create Task

`POST /api/goals/{goalId}/tasks`

Request:
```json
{
  "title": "Prepare promotion plan",
  "description": "Outline achievements and next steps",
  "type": "green",
  "priority": 8,
  "status": "todo",
  "plannedTime": "2026-04-27T09:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "tagIds": ["uuid"]
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "goalId": "uuid",
  "title": "Prepare promotion plan",
  "description": "Outline achievements and next steps",
  "type": "green",
  "priority": 8,
  "status": "todo",
  "plannedTime": "2026-04-27T09:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "archived": false,
  "shared": false,
  "version": 0,
  "tags": [
    {
      "id": "uuid",
      "name": "career",
      "color": "#4f6b9a"
    }
  ],
  "recurrence": null,
  "reminders": [],
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### Get Task

`GET /api/tasks/{taskId}`

Response `200 OK`:
```json
{
  "id": "uuid",
  "goalId": "uuid",
  "title": "Prepare promotion plan",
  "description": "Outline achievements and next steps",
  "type": "green",
  "priority": 8,
  "status": "todo",
  "plannedTime": "2026-04-27T09:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "archived": false,
  "shared": false,
  "version": 0,
  "tags": [],
  "recurrence": null,
  "reminders": [],
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:30:00Z"
}
```

### Update Task

`PATCH /api/tasks/{taskId}`

Request:
```json
{
  "title": "Prepare promotion plan draft",
  "description": "Outline achievements and next steps in writing",
  "type": "green",
  "priority": 7,
  "status": "in_progress",
  "plannedTime": "2026-04-27T10:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "archived": false,
  "version": 0
}
```

Contract note:
- `tagIds` may be omitted when a client does not author tags; omitted `tagIds` preserves existing task tags
- send `"tagIds": []` to intentionally clear all tags, or a UUID list to replace the tag set

Response `200 OK`:
```json
{
  "id": "uuid",
  "goalId": "uuid",
  "title": "Prepare promotion plan draft",
  "description": "Outline achievements and next steps in writing",
  "type": "green",
  "priority": 7,
  "status": "in_progress",
  "plannedTime": "2026-04-27T10:00:00+03:00",
  "dueTime": "2026-04-28T18:00:00+03:00",
  "archived": false,
  "shared": false,
  "version": 1,
  "tags": [],
  "recurrence": null,
  "reminders": [],
  "createdAt": "2026-04-26T18:30:00Z",
  "updatedAt": "2026-04-26T18:40:00Z"
}
```

### Complete Task

`POST /api/tasks/{taskId}/complete`

Response `200 OK`:
```json
{
  "id": "uuid",
  "status": "done",
  "completedAt": "2026-04-27T11:00:00+03:00"
}
```

### Cancel Task

`POST /api/tasks/{taskId}/cancel`

Response `200 OK`:
```json
{
  "id": "uuid",
  "status": "cancelled"
}
```

### Delete Task

`DELETE /api/tasks/{taskId}`

Response:
- `204 No Content`

## 11. Task Tag and Link API

### List Tags

`GET /api/tags`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "name": "career",
      "color": "#4f6b9a"
    }
  ]
}
```

### Create Tag

`POST /api/tags`

Request:
```json
{
  "name": "career",
  "color": "#4f6b9a"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "name": "career",
  "color": "#4f6b9a"
}
```

### Replace Task Tags

`PUT /api/tasks/{taskId}/tags`

Request:
```json
{
  "tagIds": ["uuid", "uuid"]
}
```

Response `200 OK`:
```json
{
  "taskId": "uuid",
  "tags": [
    {
      "id": "uuid",
      "name": "career",
      "color": "#4f6b9a"
    },
    {
      "id": "uuid",
      "name": "urgent",
      "color": "#c0504d"
    }
  ]
}
```

### Create Task Link

`POST /api/tasks/{taskId}/links`

Request:
```json
{
  "targetTaskId": "uuid",
  "linkType": "related"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "sourceTaskId": "uuid",
  "targetTaskId": "uuid",
  "linkType": "related"
}
```

### Delete Task Link

`DELETE /api/tasks/{taskId}/links/{linkId}`

Response:
- `204 No Content`

## 12. Calendar API

### Get Calendar Projection

`GET /api/calendar?from=2026-04-01T00:00:00Z&to=2026-04-30T23:59:59Z`

Response `200 OK`:
```json
{
  "items": [
    {
      "taskId": "uuid",
      "goalId": "uuid",
      "title": "Prepare promotion plan",
      "type": "green",
      "priority": 8,
      "status": "todo",
      "plannedTime": "2026-04-27T09:00:00+03:00",
      "dueTime": "2026-04-28T18:00:00+03:00"
    }
  ]
}
```

### Move Task in Calendar

`POST /api/tasks/{taskId}/move`

Request:
```json
{
  "plannedTime": "2026-04-27T12:00:00+03:00"
}
```

Response `200 OK`:
```json
{
  "id": "uuid",
  "plannedTime": "2026-04-27T12:00:00+03:00",
  "priority": 8,
  "updatedAt": "2026-04-26T19:00:00Z"
}
```

Business note:
- if the move postpones the task, backend may record a reschedule event and evaluate priority decay

## 13. Recurrence and Reminder API

### Upsert Recurrence Rule

`PUT /api/tasks/{taskId}/recurrence`

Request:
```json
{
  "mode": "weekly",
  "interval": 1,
  "daysOfWeek": ["MONDAY", "WEDNESDAY"],
  "startAt": "2026-04-27T09:00:00+03:00",
  "endAt": null,
  "active": true
}
```

Response `200 OK`:
```json
{
  "taskId": "uuid",
  "recurrence": {
    "mode": "weekly",
    "interval": 1,
    "daysOfWeek": ["MONDAY", "WEDNESDAY"],
    "startAt": "2026-04-27T09:00:00+03:00",
    "endAt": null,
    "active": true
  }
}
```

### Upsert Reminder Rules

`PUT /api/tasks/{taskId}/reminders`

Request:
```json
{
  "reminders": [
    {
      "mode": "before_planned_time",
      "offsetMinutes": 30,
      "active": true
    },
    {
      "mode": "before_due_time",
      "offsetMinutes": 1440,
      "active": true
    }
  ]
}
```

Response `200 OK`:
```json
{
  "taskId": "uuid",
  "reminders": [
    {
      "id": "uuid",
      "mode": "before_planned_time",
      "offsetMinutes": 30,
      "active": true
    },
    {
      "id": "uuid",
      "mode": "before_due_time",
      "offsetMinutes": 1440,
      "active": true
    }
  ]
}
```

Business rules:
- reminder rules require a compatible time anchor
- for example, `before_planned_time` requires `plannedTime`
- reminder deliveries for shared tasks still target the owner in MVP

## 14. Quick Reschedule API

### Quick Reschedule Task

`POST /api/tasks/{taskId}/reschedule`

Request:
```json
{
  "preset": "3h"
}
```

Supported presets:
- `30m`
- `1h`
- `3h`
- `24h`

Alternative request shape allowed if needed:
```json
{
  "minutes": 180
}
```

Response `200 OK`:
```json
{
  "task": {
    "id": "uuid",
    "plannedTime": "2026-04-27T12:00:00+03:00",
    "priority": 7,
    "updatedAt": "2026-04-26T19:10:00Z"
  },
  "rescheduleEvent": {
    "id": "uuid",
    "previousPlannedTime": "2026-04-27T09:00:00+03:00",
    "newPlannedTime": "2026-04-27T12:00:00+03:00",
    "createdAt": "2026-04-26T19:10:00Z"
  },
  "priorityDecayApplied": true
}
```

Validation rules:
- task must exist
- caller must have access
- planned time must exist
- preset must be supported
- if the caller is a collaborator, the owner's decay policy still applies

## 15. Sharing API

Share invitation request bodies target an existing RocketFlow account by exactly one identifier:

By email:
```json
{
  "email": "collaborator@example.com"
}
```

By user ID:
```json
{
  "userId": "uuid"
}
```

Validation rules:
- caller must own the folder, goal, or task being shared
- target user must exist
- self-share is rejected
- duplicate pending invitations and duplicate active shares for the same target are rejected

### Share Folder

`POST /api/folders/{folderId}/share`

Response `201 Created`:
```json
{
  "id": "uuid",
  "targetType": "folder",
  "targetId": "uuid",
  "targetEmail": "collaborator@example.com",
  "targetUserId": "uuid",
  "status": "pending",
  "createdAt": "2026-04-26T19:15:00Z",
  "expiresAt": "2026-05-03T19:15:00Z"
}
```

### Share Goal

`POST /api/goals/{goalId}/share`

Response `201 Created`:
```json
{
  "id": "uuid",
  "targetType": "goal",
  "targetId": "uuid",
  "targetEmail": "collaborator@example.com",
  "targetUserId": "uuid",
  "status": "pending",
  "createdAt": "2026-04-26T19:15:00Z",
  "expiresAt": "2026-05-03T19:15:00Z"
}
```

### Share Task

`POST /api/tasks/{taskId}/share`

Response `201 Created`:
```json
{
  "id": "uuid",
  "targetType": "task",
  "targetId": "uuid",
  "targetEmail": "collaborator@example.com",
  "targetUserId": "uuid",
  "status": "pending",
  "createdAt": "2026-04-26T19:15:00Z",
  "expiresAt": "2026-05-03T19:15:00Z"
}
```

### Create Share Link

`POST /api/folders/{folderId}/share-links`
`POST /api/goals/{goalId}/share-links`
`POST /api/tasks/{taskId}/share-links`

Request body is optional. `expiresAt` must be in the future when provided:
```json
{
  "expiresAt": "2030-01-01T00:00:00Z"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "targetType": "folder",
  "targetId": "uuid",
  "token": "url-safe-random-token",
  "status": "active",
  "createdAt": "2026-04-26T19:15:00Z",
  "expiresAt": "2030-01-01T00:00:00Z"
}
```

The raw `token` is returned only on creation. Store it client-side if the user needs to copy/share the same link later.

### List Share Links

`GET /api/folders/{folderId}/share-links`
`GET /api/goals/{goalId}/share-links`
`GET /api/tasks/{taskId}/share-links`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "targetType": "folder",
      "targetId": "uuid",
      "status": "active",
      "createdAt": "2026-04-26T19:15:00Z",
      "expiresAt": "2030-01-01T00:00:00Z",
      "revokedAt": null
    }
  ]
}
```

### Resolve Share Link

`GET /api/shares/links/{token}`

Requires authentication. Returns metadata only, not protected folder/goal/task contents:
```json
{
  "id": "uuid",
  "targetType": "folder",
  "targetId": "uuid",
  "status": "active",
  "expiresAt": "2030-01-01T00:00:00Z"
}
```

### Accept Share Link

`POST /api/shares/links/{token}/accept`

Requires authentication. Creates read-only collaborator access for the authenticated user.
```json
{
  "shareId": "uuid",
  "targetType": "folder",
  "targetId": "uuid",
  "status": "active"
}
```

### Revoke Share Link

`POST /api/shares/links/{linkId}/revoke`

Owner-only. Revoking a link prevents future resolve/accept by token; accepted shares remain active.
```json
{
  "id": "uuid",
  "status": "revoked"
}
```

### List Invitations

`GET /api/shares/invitations`

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "uuid",
      "targetType": "goal",
      "targetId": "uuid",
      "targetEmail": "collaborator@example.com",
      "targetUserId": "uuid",
      "status": "pending",
      "createdAt": "2026-04-26T19:15:00Z",
      "expiresAt": "2026-05-03T19:15:00Z"
    }
  ]
}
```

### Accept Invitation

`POST /api/shares/invitations/{invitationId}/accept`

Response `200 OK`:
```json
{
  "id": "uuid",
  "status": "accepted"
}
```

### Decline Invitation

`POST /api/shares/invitations/{invitationId}/decline`

Response `200 OK`:
```json
{
  "id": "uuid",
  "status": "declined"
}
```

### Revoke Invitation

`POST /api/shares/invitations/{invitationId}/revoke`

Response `200 OK`:
```json
{
  "id": "uuid",
  "status": "revoked"
}
```

### List Shared Resources

`GET /api/shares/resources`

Response `200 OK`:
```json
{
  "folders": [
    {
      "id": "uuid",
      "name": "Work",
      "description": "Main work area",
      "displayOrder": 1,
      "archived": false,
      "shared": true,
      "version": 1,
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:30:00Z"
    }
  ],
  "goals": [
    {
      "id": "uuid",
      "folderId": "b6d3b3e8-1f44-4d5c-9b4c-bce2d3c1b9f1",
      "name": "Promotion",
      "description": "Grow into the next role",
      "archived": false,
      "shared": true,
      "version": 3,
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:35:00Z"
    }
  ],
  "tasks": [
    {
      "id": "uuid",
      "goalId": "uuid",
      "title": "Prepare promotion plan",
      "description": "Outline achievements and next steps",
      "type": "green",
      "priority": 8,
      "status": "todo",
      "plannedTime": "2026-04-27T09:00:00+03:00",
      "dueTime": "2026-04-28T18:00:00+03:00",
      "archived": false,
      "shared": true,
      "version": 2,
      "tags": [],
      "recurrence": null,
      "reminders": [],
      "createdAt": "2026-04-26T18:30:00Z",
      "updatedAt": "2026-04-26T18:30:00Z"
    }
  ]
}
```

Contract note:
- accepted folder shares are expanded into `folders`, contained `goals`, and contained `tasks`
- shared goals keep their persisted `folderId`; for folder shares this `folderId` appears in `folders`
- shared tasks use the same `TaskDto` shape as task list/detail responses, including `tags`, `recurrence`, and `reminders`
- direct task shares do not include the parent goal or folder unless separately shared
- folder, goal, and task collaborators are read-only; write endpoints remain owner-only
- new invitations require the invitee account to already exist; legacy pending invitations without `targetUserId` remain acceptable by the account whose email matches `targetEmail`
- share links are authenticated: resolving or accepting a token requires a valid session, and unauthenticated callers do not receive protected resource data

## 16. Device Registration API

### Register Device

`POST /api/devices`

Request:
```json
{
  "platform": "android",
  "pushToken": "fcm-device-token",
  "installationId": "0b0f2d7f-1111-2222-3333-444455556666",
  "deviceName": "Pixel 8"
}
```

Response `201 Created`:
```json
{
  "id": "uuid",
  "platform": "android",
  "deviceName": "Pixel 8",
  "active": true,
  "createdAt": "2026-04-26T19:20:00Z"
}
```

Contract notes:
- `installationId` should be a stable client-generated identifier for one app installation
- when `installationId` is provided, the backend should upsert the logical device even if the push token rotated
- older clients may omit `installationId`, in which case fallback behavior remains token-based

### Delete Device

`DELETE /api/devices/{deviceId}`

Response:
- `204 No Content`

## 17. Validation Rules by Resource

### Folder

- `name` is required
- `name` should be short enough for UI readability

### Goal

- `name` is required
- `folderId` must exist and be accessible

### Task

- `title` is required
- `type` must be `green` or `red`
- `priority` must be between `1` and `10`
- `status` must be one of the allowed task statuses
- `plannedTime` and `dueTime` must be valid timestamps when present

### Recurrence

- recurrence must contain a supported mode
- weekly recurrence requires at least one weekday
- recurrence anchors must be coherent with task timing

### Reminders

- each reminder must have a valid mode
- each reminder must have a valid anchor-compatible configuration

### Sharing

- exactly one of `email` or `userId` is required for invitations
- target object must exist
- duplicate pending invitation or duplicate active access must be rejected
- self-invite must be rejected

## 18. Permission Rules in API Terms

The following users may read a goal:
- the owner
- an accepted collaborator on the parent folder
- an accepted collaborator on that goal

The following users may modify a goal:
- the owner

The following users may read a task:
- the owner
- an accepted collaborator on the parent folder
- an accepted collaborator on the parent goal
- an accepted collaborator on that task

The following users may modify a task:
- the owner

Folder access:
- owners can create, update, delete, invite, and manage links
- accepted folder collaborators can read the folder via `/api/shares/resources`
- accepted folder collaborators can read contained goals via `GET /api/folders/{folderId}/goals`
- accepted folder collaborators can read contained tasks through the normal goal/task read endpoints
- folder collaborators are read-only; contained goal/task create, update, delete, schedule, recurrence, and reminder writes remain owner-only

## 19. Localization and Client Contract Notes

API payloads should use stable enum-like values independent of UI language.

Examples:
- task type uses `green` or `red`
- task status uses `todo`, `in_progress`, `done`, `cancelled`
- language uses `ru` or `en`

Reasoning:
- backend contracts must not depend on presentation language
- web and Android localize labels locally

## 20. Android-Specific Contract Notes

Android MVP needs these responses to stay stable:
- auth responses
- task detail shape
- notification-related task lookup
- device registration

Recommended push payload minimum:
```json
{
  "type": "task_reminder",
  "taskId": "uuid"
}
```

Optional payload fields:
- `title`
- `plannedTime`
- `dueTime`

## 21. Open Implementation Decisions

These points may still be finalized in implementation while preserving the contract direction:
- exact token format
- exact invitation expiry duration
- whether reminders are fully replaced or partially patched in `PUT /reminders`

If any of these decisions materially change client behavior, update this document.

## 22. Next Document

The next recommended document is:
- `docs/06-qa-strategy.md`

After that, implementation can start with:
- backend foundation
- web shell and localization foundation
