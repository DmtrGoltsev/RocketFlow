# RocketFlow Production DB Migrations

Last updated: 2026-08-23.

## Live database contract

- Production database: `rocketflow_prod`.
- Migration tool: Flyway through the backend application lifecycle.
- Current recorded Flyway state: `V21`, 21 rows (`21/21`).
- Release `sha-50a63270ae09` applied `V21__retire_task_priority.sql` through the backend application lifecycle; canonical deploy evidence is GitHub Actions run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905).
- Candidate `V22__support_ios_device_registrations.sql` exists in source but is not deployed. No production DB inspection was performed during the native iOS documentation update.

## CI/CD rule

The production deploy workflow does not run standalone Flyway commands. It packages the backend, verifies artifacts, promotes the release, waits for post-promotion readiness, and checks the Flyway history table before and after promotion.

On release branch pushes, the production deploy job now runs automatically
through the same HexCore staging, promotion, and verification path used by
guarded manual dispatches. Flyway migrations still occur through the backend
application lifecycle when the promoted service starts.

The active deploy and rollback gates are:

- read `flyway_schema_history` row count from `rocketflow_prod`;
- require at least 20 rows before jointly promoting backend and web; this is a supported-source compatibility floor, not the current V21 production count;
- require the deploy manifest Flyway minimum to equal 21 and the post-start history count to be at least 21 before the joint deploy completes;
- for application rollback, require at least 20 rows before promotion, record that count, and require the post-rollback count to remain at least 20 without decreasing;
- if a rollback target manifest declares a Flyway minimum, require that it supports at least the V20 baseline rather than forcing V21;
- fail the approved deploy or rollback if the history table cannot be read or a required baseline/invariance check fails.

Historical V20 checkpoint: for the first V20 promotion, the pre-promotion source baseline was 18 rows and the post-promotion target was 20 rows. GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631) completed successfully with the final `20/20` state. This paragraph is history, not current operator state.

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

Current V21 rollout evidence is `docs/69-v21-production-rollout.md`. The immutable V20 historical record is `docs/67-weekly-focus-production-rollout-evidence.md`.
