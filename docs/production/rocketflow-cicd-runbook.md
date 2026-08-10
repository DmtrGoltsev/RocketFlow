# RocketFlow CI/CD Runbook

Last updated: 2026-08-09.

## Production contract

- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Web route: `/rocket/ -> /var/www/rocketflow-web/current`.
- API route: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Pre-promotion Flyway source baseline for the first V20 deploy: at least 18 rows.
- Release/post-promotion Flyway target: at least 20 rows.

## Workflows

### `RocketFlow HexCore Prod Deploy`

File: `.github/workflows/backend-hexcore-prod-deploy.yml`.

Purpose: build backend and web, create a release bundle, verify checksums and manifest, upload the bundle as a GitHub artifact, then stage verified files on HexCore and promote only after the remote manifest/checksum check passes.

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
- pre-promotion Flyway history count for `rocketflow_prod`, required to be at least 18 rows so the existing V18 production baseline can start the V20 release;
- release manifest Flyway contract, required to be at least 20 rows locally and again during remote staging;
- post-promotion Flyway history count, required to be at least 20 rows after the promoted JAR starts and applies `V19` and `V20` through its Flyway lifecycle.

After promotion, the deploy waits up to 40 attempts with 5-second sleeps for
`rocketflow-backend.service`, the local Nginx `/rocket/` marker, and local
backend health before failing the run. The public `/rocket-api/health` and
`/rocket/` checks use the same retry window.

The workflow does not invoke standalone Flyway commands. The order is fixed:
verify the existing V18-or-newer source state, verify and stage an artifact whose
manifest requires V20, promote the release, let the backend startup lifecycle
apply `V19` and `V20`, then require the V20-or-newer state in post-deploy
readiness. The pre-promotion gate must not require V20 because the old production
JAR has not applied those migrations yet.

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

Rollback approach:

1. Require at least 20 Flyway history rows; application rollback does not change or reverse the database after the V20 release.
2. Verify current backend symlink and target release files.
3. Verify target remote checksum when available.
4. Touch target backend/web artifacts so the existing server-side `rocketflow-promote-latest` helper promotes that target.
5. Run post-rollback health and web checks.

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
5. After promotion, check backend health and `/rocket/` web marker.
6. Record the promoted `release_id` and workflow run id in the production change record.
