# Cancelled Status Reconciliation

## Purpose

This note records the reconciliation of the `cancelled` task status across the RocketFlow MVP documentation and current backend implementation.

## What Drift Existed

The frozen domain and API documents already treated `cancelled` as part of the allowed task status set.

Some implementation-stage notes still described the status set as:

- `todo`
- `in_progress`
- `done`

That was documentation drift.

## Reconciled Truth

The canonical task status set for the current MVP is:

- `todo`
- `in_progress`
- `done`
- `cancelled`

## Current Backend Reality

The backend already enforces this status set in:

- `backend/src/main/resources/db/migration/V3__planning_core.sql`
- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`

This reconciliation does not change MVP scope.
It aligns implementation notes with the frozen contracts and current backend validation.
