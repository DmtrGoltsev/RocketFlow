# RocketFlow Production DB Migrations

Last updated: 2026-08-21.

## Live database contract

- Production database: `rocketflow_prod`.
- Migration tool: Flyway through the backend application lifecycle.
- Current Flyway history baseline: `V20`, 20 rows (`20/20`).
- Release `sha-910c061de4af` applied `V19__weekly_focus.sql` and `V20__focus_notifications.sql` through the backend application lifecycle.
- V21 is a future rollout target only; it is not deployed as of this status update.

## CI/CD rule

The production deploy workflow does not run standalone Flyway commands. It packages the backend, verifies artifacts, promotes the release, waits for post-promotion readiness, and checks the Flyway history table before and after promotion.

On release branch pushes, the production deploy job now runs automatically
through the same HexCore staging, promotion, and verification path used by
guarded manual dispatches. Flyway migrations still occur through the backend
application lifecycle when the promoted service starts.

The current V20 production check and future V21 rollout gates are:

- read `flyway_schema_history` row count from `rocketflow_prod`;
- require at least 20 rows before jointly promoting the future V21-capable backend and V20+V21-compatible web artifact;
- require the manifest target to equal 21 and the post-start history count to be at least 21 before the joint deploy completes and Android is released separately;
- for application rollback, require at least 20 rows before promotion, record that count, and require the post-rollback count to remain at least 20 without decreasing;
- if a rollback target manifest declares a Flyway minimum, require that it supports at least the V20 baseline rather than forcing V21;
- fail the approved deploy or rollback if the history table cannot be read or a required baseline/invariance check fails.

For the first V20 promotion, the pre-promotion source baseline was 18 rows and the post-promotion target was 20 rows. GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631) completed successfully with the final `20/20` state.

`V21__retire_task_priority.sql` changes column defaults only (`priority* -> 5`, green/red decay enabled -> `false`). It does not update/delete rows, drop columns/constraints/indexes, or rewrite historical task, reschedule-event, or settings values.

## Rollback rule

Application rollback does not imply database rollback.

The manual rollback workflow:

- requires a target application `release_id`;
- requires current release confirmation;
- requires an approval ticket;
- rejects `include_db_rollback=true`;
- performs no backup restore and no Flyway repair/migrate/undo command.

Database recovery, restore, or migration repair must be handled by a separate operator-approved database procedure outside these workflows.

After V21, application rollback means jointly promoting a V20-compatible backend/web artifact while the database remains unchanged at V21. The same workflow is also valid at V20 because its baseline is `>=20`. The retained legacy columns, wire fields, constraints, values, and defaults make the V20 binary forward-compatible with V21; no old APK/V20 shadow may be removed until rollback support explicitly ends.

## Evidence to keep

For every production deploy or rollback, keep:

- workflow run URL;
- `release_id`;
- release manifest file name;
- checksum verification output;
- pre/post Flyway history row count;
- approval ticket or incident id.

The immutable evidence record for the V20 rollout is `docs/67-weekly-focus-production-rollout-evidence.md`.
