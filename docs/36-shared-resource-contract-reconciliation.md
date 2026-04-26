# Shared Resource Contract Reconciliation

## Purpose

This note reconciles an earlier documentation example with the implemented backend behavior for shared-resource discovery.

It exists so web, Android, QA, and future contributors use one source of truth for `/api/shares/resources`.

## Reconciled Decision

Canonical behavior:

- `GET /api/shares/resources` returns shared goals with their persisted `folderId`
- no synthetic `virtual-shared` folder identifier is introduced
- the endpoint remains discovery-oriented, not ownership-oriented
- folder ownership semantics do not expand through shared-resource discovery

## Why This Is Canonical

Wave A backend sharing intentionally preserved the existing `GoalDto.folderId` UUID shape:

- `docs/20-wave-a-backend-sharing.md`

This is now the authoritative implementation reality and should override the older illustrative example that used `virtual-shared`.

## Client Guidance

Web and Android should treat shared resources as:

- separate discovery surfaces
- not evidence of shared folder ownership
- eligible for grouping in presentation if useful

But clients should not depend on a synthetic folder id contract.

## Documents Synchronized By This Note

- `docs/05-api-contracts.md`
- `docs/15-frontend-lead-decomposition.md`
- current and future Wave C docs that consume sharing discovery

