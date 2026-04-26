# RocketFlow Current State Summary

## Purpose

This file is the short handoff summary for starting a new thread without carrying the full historical conversation.

Use this together with:

- `README.md`
- `docs/19-cross-lead-orchestration-plan.md`

## Project Status

Project root:

- `C:\Users\hp\Documents\Codex\RocketFlow`

Completed:

- planning and documentation baseline
- architecture and API contract baseline
- backend foundation
- auth and settings foundation
- folders / goals / tasks CRUD foundation
- `Wave A`
- `Wave B`
- `Wave C` documentation and stabilization baseline
- `Wave C.1` web scheduling authoring follow-up

Verified:

- backend full test suite passes with `mvn test`
- web production build passes with `npm run build`

## Most Important Docs

Core:

- `README.md`
- `docs/19-cross-lead-orchestration-plan.md`

Wave A:

- `docs/20-wave-a-backend-sharing.md`
- `docs/21-wave-a-backend-recurrence-reminders.md`
- `docs/22-wave-a-web-shell-foundation.md`
- `docs/23-wave-a-qa-backend-api-validation.md`
- `docs/24-wave-a-devops-backend-ci.md`
- `docs/25-wave-a-web-auth-i18n.md`

Reconciliation:

- `docs/26-cancelled-status-reconciliation.md`

Wave B:

- `docs/27-wave-b-backend-calendar-priority.md`
- `docs/28-wave-b-backend-notifications.md`
- `docs/29-wave-b-web-planning-flows.md`
- `docs/30-wave-b-qa-scheduling-validation.md`
- `docs/31-wave-b-devops-staging-secrets.md`

Wave C:

- `docs/32-wave-c-web-collaboration-settings.md`
- `docs/34-wave-c-android-companion-foundation.md`
- `docs/35-wave-c-android-auth-session.md`
- `docs/36-shared-resource-contract-reconciliation.md`
- `docs/37-wave-c-qa-validation.md`
- `docs/38-wave-c-devops-verification.md`
- `docs/39-wave-c1-web-scheduling-authoring.md`
- `docs/40-wave-c-android-browse-detail.md`
- `docs/41-wave-c1-web-scheduling-authoring-implementation.md`
- `docs/42-wave-c-android-notification-entry-foundation.md`

## Implemented Backend Scope

- auth
- user settings
- folders / goals / tasks CRUD
- sharing and access
- recurrence and reminders
- calendar projection
- move and quick reschedule
- priority decay
- device registration
- notification delivery foundation

## Implemented Web Scope

- retro shell foundation
- RU-first i18n foundation
- auth foundation
- folders / goals / tasks planning flows
- calendar / sharing / settings routes
- recurrence and reminder authoring inside task create/edit

## Important Product / Technical Rules

- Russian is primary, English must be kept in sync
- all meaningful stages are documented in `docs/`
- canonical task statuses are:
  - `todo`
  - `in_progress`
  - `done`
  - `cancelled`
- Android companion now also has device-registration and notification-open/deep-link foundation; real FCM/runtime validation is still pending
- backend remains a modular monolith
- current scheduler assumption is still single backend instance

## Current Quality State

- backend green
- web build green
- no active subagents need to be resumed

Known non-blocking note:

- Mockito/JDK dynamic agent warning exists in backend test runs but does not currently break the suite

## Recommended Next Step

Continue the Android companion path after the completed notification-entry foundation:

- Android SDK setup and `assembleDebug` verification
- real FCM/runtime token flow and staging-oriented notification validation

If orchestration discipline is needed again, use:

- `docs/19-cross-lead-orchestration-plan.md`

as the baseline and create the next wave documents in sequence.
