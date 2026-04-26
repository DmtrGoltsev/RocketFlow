# RocketFlow Auth and Settings Foundation

## 1. Purpose

This document records the implementation of the auth and settings foundation stage for RocketFlow.

This stage covers:
- registration
- login
- token refresh
- logout
- current user profile
- user settings read and update
- baseline security wiring
- integration verification

## 2. What Was Implemented

### Persistence

Added auth session persistence through:
- `V2__auth_sessions.sql`

Existing foundation tables now support:
- `users`
- `user_credentials`
- `user_settings`
- `auth_sessions`

### Backend Modules Used

Implemented mainly inside:
- `auth`
- `accounts`
- `settings`
- `config`
- `common`

### API Endpoints Implemented

Implemented endpoints:
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/me`
- `GET /api/me/settings`
- `PATCH /api/me/settings`

## 3. Key Implementation Decisions

### Token Model

For MVP foundation:
- access tokens are opaque server-side tokens
- refresh tokens are opaque server-side tokens
- token hashes are stored in the database
- access and refresh validity are tracked per session

This keeps the auth foundation simple and easy to change later if JWT becomes justified.

### Password Handling

- passwords are hashed with BCrypt
- plain-text passwords are never stored

### Current Authorization Model

- protected endpoints use bearer access tokens
- current user resolution comes from the authenticated token session
- ownership and sharing permission logic for domain resources is still a later step

### Settings Model

Implemented settings support for:
- language
- notifications enabled flag
- green priority decay policy
- red priority decay policy
- optimistic locking through `version`

### Timezone Model

The auth/settings implementation follows the stabilized rule:
- timezone belongs to `users`
- settings do not duplicate timezone

## 4. Security Baseline

Added:
- stateless security filter chain
- custom bearer token filter
- explicit public auth endpoints
- protected `/api/me` and `/api/me/settings`

Not yet implemented:
- production-grade token rotation policies beyond the current basic flow
- account verification
- password reset
- rate limiting
- sharing-aware authorization rules

## 5. Verification

Verification now includes:
- application bootstrap smoke test
- PostgreSQL-backed Flyway migration smoke test
- auth/settings integration tests with embedded PostgreSQL and MockMvc

Verified flows:
- register
- login
- read current user
- read settings
- update settings
- refresh tokens

Command used:
- `mvn test`

Result:
- full backend test suite passed

## 6. Residual Risks

Still intentionally deferred:
- real sharing permission enforcement
- recurrence and reminder behavior
- task-related authorization
- device registration and notification delivery
- folder/goal/task CRUD

Security notes still to address in future stages:
- remove the transitional empty `UserDetailsService` workaround once a fuller auth configuration is in place
- add rate limiting and abuse protection
- add stronger session lifecycle and cleanup strategy if needed

## 7. Next Planned Step

The next planned implementation step is:
- core folders/goals/tasks CRUD foundation

Safe parallel track after that:
- web shell and localization foundation
