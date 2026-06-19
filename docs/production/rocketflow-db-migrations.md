# RocketFlow Production DB Migrations

Last updated: 2026-06-19.

## Live database contract

- Production database: `rocketflow_prod`.
- Migration tool: Flyway through the backend application lifecycle.
- Current Flyway history baseline: 18 rows.

## CI/CD rule

The production deploy workflow does not run standalone Flyway commands. It packages the backend, verifies artifacts, promotes the release, waits for post-promotion readiness, and checks the Flyway history table before and after promotion.

On release branch pushes, the production deploy job now runs automatically
through the same HexCore staging, promotion, and verification path used by
guarded manual dispatches. Flyway migrations still occur through the backend
application lifecycle when the promoted service starts.

The expected production check is:

- read `flyway_schema_history` row count from `rocketflow_prod`;
- require at least 18 rows;
- fail the approved deploy or rollback if the history table cannot be read or the count is below the baseline.

## Rollback rule

Application rollback does not imply database rollback.

The manual rollback workflow:

- requires a target application `release_id`;
- requires current release confirmation;
- requires an approval ticket;
- rejects `include_db_rollback=true`;
- performs no backup restore and no Flyway repair/migrate/undo command.

Database recovery, restore, or migration repair must be handled by a separate operator-approved database procedure outside these workflows.

## Evidence to keep

For every production deploy or rollback, keep:

- workflow run URL;
- `release_id`;
- release manifest file name;
- checksum verification output;
- pre/post Flyway history row count;
- approval ticket or incident id.
