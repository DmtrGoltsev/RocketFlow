# RocketFlow Backend Foundation

## 1. Purpose

This document records the first implementation foundation stage for RocketFlow:
- backend project skeleton
- database migration setup

These were the next two planned implementation steps after the planning, domain, architecture, API, and QA documents.

## 2. What Was Added

### Backend Skeleton

Created:
- Maven-based Spring Boot backend project under `backend/`
- root application class
- explicit package structure aligned to the architectural blueprint

Package structure created:
- `common`
- `config`
- `auth`
- `accounts`
- `settings`
- `folders`
- `goals`
- `tasks`
- `sharing`
- `calendar`
- `recurrence`
- `reminders`
- `prioritypolicy`
- `notifications`

### Foundation Dependencies

Configured:
- Spring Boot web
- validation
- security
- JPA
- actuator
- Flyway
- Flyway PostgreSQL support module
- PostgreSQL driver
- Spring Boot test
- embedded PostgreSQL for migration verification tests

### Base Configuration

Added:
- `application.yml`
- datasource placeholders through environment variables
- Flyway location setup
- JPA validation mode
- actuator exposure for `health` and `info`
- UTC-based server-side JSON and JDBC time handling

### Migration Setup

Added first Flyway migration:
- `V1__baseline_foundation.sql`

The initial migration creates:
- `users`
- `user_credentials`
- `user_settings`

This schema was chosen intentionally because the next implementation step in the plan is auth and settings foundation.

Foundation decisions now frozen:
- user timezone has one source of truth: `users.timezone`
- priority decay remains a `UserSettings` concern in MVP persistence
- `user_settings` stores language, notifications, and embedded green/red decay policies
- database constraints enforce supported language and threshold values

## 3. Verification

Verification performed:
- Maven test run
- PostgreSQL-backed Flyway migration smoke test through embedded PostgreSQL

Result:
- build succeeded
- application context smoke test passed
- baseline Flyway migration applied successfully against embedded PostgreSQL

Important note:
- one test excludes datasource, JPA, and Flyway autoconfiguration because it verifies application bootstrap in isolation
- a separate test verifies the Flyway migration path against embedded PostgreSQL

## 4. Why This Stage Is Safe

This stage does not lock the project into the unresolved collaboration and scheduling semantics identified during the independent architecture review.

Safe areas covered:
- module-aligned backend package layout
- project dependency baseline
- migration tool integration
- initial auth/settings-oriented schema direction

Not yet implemented:
- auth behavior
- settings API
- business entities beyond the first three tables
- collaboration logic
- recurrence
- reminders
- notification delivery

## 5. Follow-Up Notes

Observations from verification:
- the project currently starts with Spring Security default development behavior
- real security configuration still needs to be implemented in the auth foundation step
- local developer defaults now live in the `local` profile instead of the main application profile

## 6. Next Planned Step

The next planned implementation step after this document is:
- auth and settings foundation

Recommended parallel track after that:
- web shell and localization foundation
