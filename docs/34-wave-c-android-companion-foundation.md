# Wave C Android Companion Foundation

## Scope

This document records the start of the Android companion stream for MVP.

The companion remains intentionally narrow:

- authenticate
- restore session
- browse owned and shared planning items needed to reach tasks
- open read-only task detail
- register the device for push later in the same stream

## Baseline Started

The repository now gains an Android workspace baseline so future waves can build on concrete structure instead of starting from zero.

Initial foundation goals:

- create an `android/` project root
- define app namespace and module boundaries for `auth`, `browse`, `detail`, and `notifications`
- document that Android is companion-only and read-only for planning data in MVP

## Guardrails

- no task create/edit/delete flows
- no calendar parity work
- no invitation-management parity work
- no offline architecture
- no expansion beyond companion scope without a documented product change

## Next Android Steps

1. add networking and auth/session baseline
2. add browse shell for owned and shared resources
3. add read-only task detail route
4. add device registration and push entry wiring after backend notification flow is ready

## Done Criteria For The Foundation Stage

- Android workspace exists in the repo
- companion-only scope is documented in-repo
- future implementation can start from stable package/module boundaries

