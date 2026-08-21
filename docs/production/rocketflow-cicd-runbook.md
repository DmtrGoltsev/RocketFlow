# RocketFlow CI/CD Runbook

Last updated: 2026-08-22.

## Production contract

- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Web route: `/rocket/ -> /var/www/rocketflow-web/current`.
- API route: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Current live pre-promotion Flyway source baseline for a future V21 deploy: at least 20 rows.
- V21 release manifest target: exactly 21 rows; post-promotion Flyway baseline: at least 21 rows.

## Current recorded rollout

- Deployed source SHA: `910c061de4af9395d9bb682624bd966b2977a738`.
- Release id: `sha-910c061de4af`.
- Successful deploy: GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631).
- Post-promotion Flyway state: `V20` (`20/20`).
- Local and public health checks passed; captured post-deploy evidence reported zero application errors, HTTP `5xx` responses, or service restarts.
- Rollback workflow ID `330828165` is active and was not used.
- Focus cadence and Web Push are disabled.
- Authenticated production smoke remains an evidence gap.

The docs-only commit recording these facts is not a deployed release. Full checksums and backup evidence are in `docs/67-weekly-focus-production-rollout-evidence.md`.

The current branch prepares a future V21 release, but production remains on the V20 source/release above. `V21__retire_task_priority.sql` and the updated workflow gates are not deploy evidence.

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
- pre-promotion Flyway history count for `rocketflow_prod`, required to be at least 20 rows because current production is the V20 baseline;
- release manifest Flyway contract, required to equal 21 locally and again during remote staging;
- post-promotion Flyway history count, required to be at least 21 rows after the jointly promoted V21-capable backend starts and applies `V21` through its Flyway lifecycle.

After promotion, the deploy waits up to 40 attempts with 5-second sleeps for
`rocketflow-backend.service`, the local Nginx `/rocket/` marker, and local
backend health before failing the run. The public `/rocket-api/health` and
`/rocket/` checks use the same retry window.

The workflow does not invoke standalone Flyway commands. For the future V21 rollout, the order is fixed: verify the existing V20-or-newer source state, verify and stage an artifact whose manifest requires V21, jointly promote its backend and web through `rocketflow-promote-latest`, let backend startup apply `V21`, then require V21-or-newer state in post-deploy readiness. This joint transition is safe because the new web is compatible with both the V20 and V21 backend contracts. Android is released separately only after the joint deploy gate succeeds. The pre-promotion gate must remain V20 because current production has not applied V21 yet.

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

Rollback approach at V20 or after V21:

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

1. Confirm release branch policy and required CI checks are green.
2. Confirm the release branch push or manual `production` environment approval is intentional.
3. Confirm the release artifact bundle exists and manifest verification passed.
4. Check pre-deploy inventory output for current symlink, service status, web root, and Flyway row count.
5. Confirm backend and web were jointly promoted, backend health and the `/rocket/` marker pass, and Flyway is at least V21.
6. Release Android separately only after the joint backend/web gate passes.
7. Record the deployed source SHA, promoted `release_id`, workflow run id, and any later docs-only commit separately in the production change record.
