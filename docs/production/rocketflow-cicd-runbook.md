# RocketFlow CI/CD Runbook

Last updated: 2026-08-23.

## Production contract

- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Web route: `/rocket/ -> /var/www/rocketflow-web/current`.
- API route: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Current production Flyway state: `V21` (`21/21`).
- Deploy preflight accepts a readable compatible source state with at least 20 rows.
- Release manifest Flyway minimum: exactly 21 rows; post-promotion gate: at least 21 rows.

## Current recorded rollout

- Deployed source SHA: `50a63270ae094fe08ee57b945be0930cb1115dfe`.
- Release id: `sha-50a63270ae09`.
- Successful deploy: GitHub Actions run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905).
- Post-promotion Flyway state: `V21` (`21/21`).
- Backend service and backend/web symlinks passed; local and public backend/web checks returned HTTP `200`.
- Rollback workflow ID `330828165` is active and was not used.
- Focus cadence and Web Push are disabled.
- Authenticated production smoke passed with `0` unexpected HTTP `5xx` responses.

Canonical V21 evidence is in `docs/69-v21-production-rollout.md`. The earlier `docs/67-weekly-focus-production-rollout-evidence.md` remains immutable historical V20 evidence.

Candidate source after this rollout, including Flyway V22, is not deployed merely because it exists in a branch. Production status changes only after an approved workflow and recorded post-deploy evidence.

## Workflows

### `RocketFlow HexCore Prod Deploy`

File: `.github/workflows/backend-hexcore-prod-deploy.yml`.

Purpose: build backend and web, create a release bundle, verify checksums and manifest, upload the bundle as a GitHub artifact, then stage verified files on HexCore and jointly promote backend and web through the existing helper only after the remote manifest/checksum check passes.

Triggers:

- `push` to branch names containing `release` runs build/package/artifact upload, production SSH staging, server-side promotion, and health/Flyway verification.
- `workflow_dispatch` on branch names containing `release` remains available for manual production deployment and requires the existing approval inputs.

Protection:

- Production deploy job environment: `production`.
- Concurrency: one production deploy at a time.
- Manual runs require `approval_ticket` and `production_confirmation=DEPLOY_ROCKETFLOW_PROD`.
- Release branch pushes do not require manual dispatch inputs, but still run through the `production` environment and pinned SSH host-key path.

Release bundle contents:

- `rocketflow-backend-sha-<12>.jar`.
- `rocketflow-web-sha-<12>.tar.gz`.
- `rocketflow-release-sha-<12>.sha256`.
- `rocketflow-release-manifest-sha-<12>.json`.

Inventory checks during the approved deploy:

- current backend symlink;
- active `rocketflow-backend.service` status;
- active web root under `/var/www/rocketflow-web/current`;
- local Nginx web route marker at `/rocket/`;
- local backend health at `127.0.0.1:8080/api/health`;
- pre-promotion Flyway history count for `rocketflow_prod`, required to be readable and at least 20 rows as the workflow's compatibility floor;
- release manifest Flyway contract, required to equal 21 locally and again during remote staging;
- post-promotion Flyway history count, required to be at least 21 rows after the jointly promoted V21-capable backend starts and applies `V21` through its Flyway lifecycle.

After promotion, the deploy waits up to 40 attempts with 5-second sleeps for
`rocketflow-backend.service`, the local Nginx `/rocket/` marker, and local
backend health before failing the run. The public `/rocket-api/health` and
`/rocket/` checks use the same retry window.

The workflow does not invoke standalone Flyway commands. Its fixed order is: verify a readable V20-or-newer source state (`>=20`), verify and stage an artifact whose manifest minimum is exactly `21`, jointly promote backend and web through `rocketflow-promote-latest`, let backend startup run its Flyway lifecycle, then require V21-or-newer state (`>=21`) in post-deploy readiness. The compatibility floor remains 20 for fail-closed recovery from a supported V20 baseline; it does not describe the current production state, which is V21.

### `RocketFlow GHCR Package`

File: `.github/workflows/rocketflow-ghcr-package.yml`.

Purpose: build a backend Docker image package and upload it as a GitHub Actions artifact. It does not deploy.

Publishing to GHCR happens only when all are true:

- workflow is started manually;
- `publish_image=true`;
- `approval_ticket` is provided;
- `publish_confirmation=PUBLISH_ROCKETFLOW_GHCR`;
- `production` environment approval passes.

### `RocketFlow Prod Rollback`

File: `.github/workflows/rocketflow-prod-rollback.yml`.

Purpose: manually promote an already staged release id after confirming the currently active release. It does not perform database rollback.

Required inputs:

- `target_release_id`, for example `sha-0123456789ab`;
- `current_release_confirmation`, copied from current production inventory;
- `approval_ticket`;
- `include_db_rollback=false`.

Rollback approach for a supported V20 baseline or retained V21 schema:

1. Require at least 20 Flyway history rows and record the exact pre-rollback count. This permits rollback both before and after V21.
2. Verify current backend symlink, target release files, and target remote checksum; require a readable target release manifest.
3. Parse `flyway_history_min_rows` as a JSON integer and require `20 <= minimum <= PRE_FLYWAY_COUNT`. Equality to the pre-count and lower compatible values pass. Missing/unreadable manifests, missing fields, string/boolean values, values below 20, and values above the pre-count fail closed.
4. Touch target backend/web artifacts so the existing server-side `rocketflow-promote-latest` helper jointly promotes that target.
5. Run post-rollback health and web checks, then require the Flyway count to remain at least 20 and not decrease from the recorded pre-rollback count.

The target must be a V20-compatible artifact proven against the forward V21 schema. A V20 binary with manifest minimum 20 is allowed on retained V21 schema. V21 retains the legacy task/settings columns, wire fields, constraints, historical values, and compatible defaults, so the app rollback does not require a data rollback. The workflow never repairs, migrates, undoes, downgrades, or restores the database; database recovery remains a separate operator-approved procedure.

Current workflow-contract verification: `7/7` accepted cases and `4/4` invalid cases PASS; YAML parsing and Bash syntax PASS. `actionlint` and `shellcheck` were unavailable.

## Required secret names

Keep secret values only in GitHub Actions secrets or environment secrets. Repository files should mention only these names:

- `HEXCORE_PROD_SSH_HOST`
- `HEXCORE_PROD_SSH_USER`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`
- `HEXCORE_PROD_SSH_KNOWN_HOSTS`

## Operator checklist

1. Confirm the intended release SHA and the selected CI evidence are green; branch protection is not currently configured to enforce checks automatically.
2. Confirm the release branch push or manual `production` environment approval is intentional.
3. Confirm the release artifact bundle exists and manifest verification passed.
4. Check pre-deploy inventory output for current symlink, service status, web root, and Flyway row count.
5. Confirm backend and web were jointly promoted, backend health and the `/rocket/` marker pass, and Flyway is at least V21.
6. Release Android separately only after the joint backend/web gate passes.
7. Record the deployed source SHA, promoted `release_id`, workflow run id, and any later docs-only commit separately in the production change record.
