# GitHub CI/CD Policy for RocketFlow

This file describes repository policy. Executable workflows live in `.github/workflows/*.yml`.

## Continuous verification

The normal verification workflows remain:

- `backend-verify`: backend Maven tests, migration coverage through tests, backend Docker image build, and container health smoke against temporary PostgreSQL.
- `web-verify`: web dependency install and `npm run build`.
- `android-verify`: Android SDK setup, unit tests, debug assembly, and lint.

## Production deploy policy

Production deploys are handled by GitHub Actions through HexCore.

- Workflow: `RocketFlow HexCore Prod Deploy`.
- File: `.github/workflows/backend-hexcore-prod-deploy.yml`.
- Runtime: backend jar plus `rocketflow-backend.service`; web static build through Nginx.
- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Web route: `/rocket/ -> /var/www/rocketflow-web/current`.
- API route: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Production DB: `rocketflow_prod`.
- Flyway history baseline: 18 rows.

Release triggers:

- automatic `push` to branch names containing `release` runs build/package/artifact upload only;
- manual `workflow_dispatch` on branch names containing `release` is required for any production SSH, staging, or promotion step.

Manual production deploys also require:

- `approval_ticket`;
- `production_confirmation=DEPLOY_ROCKETFLOW_PROD`;
- `production` environment approval.

The deploy workflow builds backend and web artifacts, writes SHA256 checksums, writes a release manifest, uploads the release bundle with 30-day retention, verifies the manifest locally and remotely, and only then calls the server-side promotion helper.

`MVP2` must not deploy directly unless it is renamed or promoted through a branch whose name contains `release`.

## GHCR package policy

The GHCR workflow is package-only by default.

- Workflow: `RocketFlow GHCR Package`.
- File: `.github/workflows/rocketflow-ghcr-package.yml`.
- Default behavior: build Docker image package and upload a GitHub Actions artifact.
- Publish behavior: push to GHCR only when `publish_image=true`, `approval_ticket` is present, `publish_confirmation=PUBLISH_ROCKETFLOW_GHCR`, and the `production` environment gate passes.
- It never deploys to HexCore.

## Rollback policy

Manual application rollback is handled by:

`.github/workflows/rocketflow-prod-rollback.yml`

Rollback requires:

- target release id;
- current release confirmation;
- approval ticket or incident id;
- `include_db_rollback=false`;
- `production` environment approval.

The rollback workflow does not perform database rollback, backup restore, or Flyway repair/migrate/undo commands.

## Secret policy

Repository docs and workflows should reference production secrets by name only:

- `HEXCORE_PROD_SSH_HOST`
- `HEXCORE_PROD_SSH_USER`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`
- `HEXCORE_PROD_SSH_KNOWN_HOSTS`

Secret values belong only in GitHub repository or environment secrets.

## Branch protection

Minimum protection for release branches:

- require status checks before merge;
- require the branch to be up to date before merge;
- require `backend-verify`, `web-verify`, and `android-verify`;
- disallow force push;
- disallow branch deletion;
- require all conversations to be resolved;
- require pull request review before merge.

## Normal promotion flow

1. Work in the development branch.
2. Open a pull request into the release branch.
3. Wait for green `backend-verify`, `web-verify`, and `android-verify`.
4. Merge only after checks and review pass.
5. Push to the release branch creates backend/web artifacts, checksums, and a release manifest.
6. Start `RocketFlow HexCore Prod Deploy` manually from the release branch with an approval ticket and `DEPLOY_ROCKETFLOW_PROD`.
7. The manual deploy job verifies pre-deploy inventory, stages artifacts, verifies remote checksums, promotes the release, and runs post-deploy health checks.

See also:

- `docs/production/rocketflow-cicd-runbook.md`
- `docs/production/rocketflow-live-status.md`
- `docs/production/rocketflow-db-migrations.md`
