# GitHub CI/CD Policy for RocketFlow

This file describes repository policy. Executable workflows live in `.github/workflows/*.yml`.

## Candidate continuous verification

On branch `codex/native-ios-companion`, the candidate verification workflows are:

- `backend-verify`: backend Maven tests, migration coverage through tests, backend Docker image build, and container health smoke against temporary PostgreSQL.
- `web-verify`: web dependency install and `npm run build`.
- `android-verify`: Android SDK setup, unit tests, debug assembly, and lint.
- `ios-verify`: XcodeGen generation/committed-project parity, Swift package resolution/lock parity, and no-sign simulator build with unit and UI tests.

Commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` narrowed all four verification triggers on this candidate branch to reduce duplicate feature-branch runs and notification noise:

- feature branches run verification only when an operator starts `workflow_dispatch`;
- pull requests targeting `master` run verification automatically;
- pushes to `master` run verification automatically;
- genuine failures from manual, pull-request, or `master` runs may still produce GitHub notifications.

This is not yet default-branch policy: `origin/master` at `7d1ac74cf8f2bf7935c2578f3675db4ca54764bb` does not contain commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` or `ios-verify`. After the candidate is merged, the trigger rules above become default-branch behavior. Until then, they describe only `codex/native-ios-companion`; the candidate branch has stopped automatic push runs and their associated email storm.

The candidate trigger change did not alter production deploy, package, or rollback workflows. Canonical iOS feature-branch evidence is manual [run 32655691351](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32655691351): `540/540` unit plus `2/2` UI tests at app-code/build source `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`.

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
- Current production Flyway state: `V21` (`21/21`).
- Deploy workflow gate: readable pre-promotion history `>=20`; post-promotion history `>=21`.

Release triggers:

- automatic `push` to branch names containing `release` runs build/package/artifact upload, production SSH staging, server-side promotion, and health/Flyway verification;
- manual `workflow_dispatch` on branch names containing `release` remains available for production SSH, staging, and promotion.

Manual production deploys also require:

- `approval_ticket`;
- `production_confirmation=DEPLOY_ROCKETFLOW_PROD`;
- `production` environment approval.

Release branch push deploys do not require manual dispatch inputs, but still run
through the `production` environment and pinned SSH host-key path.

The deploy workflow builds backend and web artifacts, writes SHA256 checksums, writes a release manifest, uploads the release bundle with 30-day retention, verifies the manifest locally and remotely, and only then calls the server-side helper to promote backend and web together. Post-promotion readiness waits/retries service activity, local backend health, local Nginx web routing, and public health/web checks before failing the run.

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
- a readable target release manifest containing integer `flyway_history_min_rows`;
- manifest minimum `>=20` and `<=` the recorded pre-rollback Flyway count.

The workflow fails closed for a missing/unreadable manifest, missing or non-integer minimum (including string/boolean values), a value below 20, or a value above the pre-rollback count. Post-rollback Flyway history must remain `>=20` and must not decrease from the recorded pre-count. A V20 binary declaring minimum 20 may run against retained V21 schema; the workflow does not perform database downgrade, backup restore, or Flyway repair/migrate/undo commands.

## Secret policy

Repository docs and workflows should reference production secrets by name only:

- `HEXCORE_PROD_SSH_HOST`
- `HEXCORE_PROD_SSH_USER`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`
- `HEXCORE_PROD_SSH_KNOWN_HOSTS`

Secret values belong only in GitHub repository or environment secrets.

## Recommended branch protection

The following is optional recommended hardening, not an existing requirement or evidence of configured GitHub branch protection. No branch-protection setting was configured or changed as part of commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` or the native iOS delivery.

If protection is configured later, recommended settings for `master` and any release branch are:

- require status checks before merge;
- require the branch to be up to date before merge;
- require `backend-verify`, `web-verify`, `android-verify`, and `ios-verify` where the target branch exposes those checks;
- disallow force push;
- disallow branch deletion;
- require all conversations to be resolved;
- require pull request review before merge.

## Normal promotion flow

1. Work in a feature branch and run the relevant candidate verification workflows manually when pre-PR evidence is needed.
2. After commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` is merged to `master`, a pull request into `master` runs all four verification workflows automatically.
3. Merge after the checks and review selected for that change pass; after the candidate CI commit reaches `master`, the resulting `master` push verifies again.
4. Prepare a release branch only as a separate production promotion action, after confirming the intended SHA and green evidence. A release-branch push still invokes the unchanged joint backend/web deploy workflow.
5. The release push deploy job verifies pre-deploy inventory, stages artifacts, verifies remote checksums, jointly promotes backend and web, and runs retrying post-deploy health checks.
6. For an operator-driven redeploy, start `RocketFlow HexCore Prod Deploy` manually from the release branch with an approval ticket and `DEPLOY_ROCKETFLOW_PROD`; it uses the same promotion path.

See also:

- `docs/production/rocketflow-cicd-runbook.md`
- `docs/production/rocketflow-live-status.md`
- `docs/production/rocketflow-db-migrations.md`
