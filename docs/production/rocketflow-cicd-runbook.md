# RocketFlow CI/CD Runbook

Last updated: 2026-06-19.

## Production contract

- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Web route: `/rocket/ -> /var/www/rocketflow-web/current`.
- API route: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Current Flyway history baseline: 18 rows.

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

Pre/post inventory checks during the approved deploy:

- current backend symlink;
- active `rocketflow-backend.service` status;
- active web root under `/var/www/rocketflow-web/current`;
- local Nginx web route marker at `/rocket/`;
- local backend health at `127.0.0.1:8080/api/health`;
- Flyway history count for `rocketflow_prod`, expected to be at least 18 rows.

The workflow does not invoke standalone Flyway commands. Production schema
migrations are handled by the backend application's Flyway lifecycle when the
promoted backend release starts; the workflow verifies Flyway history before and
after promotion.

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

1. Verify current backend symlink and target release files.
2. Verify target remote checksum when available.
3. Touch target backend/web artifacts so the existing server-side `rocketflow-promote-latest` helper promotes that target.
4. Run post-rollback health and web checks.

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
