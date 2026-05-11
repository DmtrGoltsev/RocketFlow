# RocketFlow GitHub CI/CD Policy

This document defines the repository CI/CD rules that should be enforced before production deployment.

## Current CI Gates

These workflows run on every `push`, every `pull_request`, and can also be started manually:

- `Backend Verify` / required job `backend-verify`
  - runs backend Maven tests
  - validates Flyway migrations through the test suite
  - builds the backend Docker image
  - runs the backend container health smoke against temporary PostgreSQL
- `Web Verify` / required job `web-verify`
  - installs web dependencies
  - runs `npm run build`
- `Android Verify` / required job `android-verify`
  - installs Android SDK packages
  - runs `./gradlew assembleDebug`

These gates are intentionally verification-only. They must stay green before merging or promoting code.

## Production Deploy Rule

Production deploy is not automatic on `push`.

The production backend workflow is manual:

- `Backend Yandex Prod Deploy` / job `deploy-backend`
- trigger: `workflow_dispatch`
- GitHub environment: `production`

Reason: direct deploy-on-push is too risky for the current stage. We should only deploy after the normal CI gates are green and the operator intentionally starts production deployment.

## Required GitHub Branch Protection

Configure this in GitHub UI:

1. Open repository settings.
2. Go to `Rules` -> `Rulesets` or `Branches`.
3. Target branch: `master`.
4. Enable required status checks before merge.
5. Require these checks:
   - `backend-verify`
   - `web-verify`
   - `android-verify`
6. Enable "Require branches to be up to date before merging".
7. Enable "Require a pull request before merging" when the team starts using PRs consistently.
8. Restrict direct pushes to `master` when production work begins.

If GitHub rulesets are available, prefer a ruleset over the older branch protection screen because it is easier to audit and extend.

## Required Production Environment Protection

Configure GitHub environment `production`:

- require manual approval before deployment
- store production secrets only in the `production` environment when possible
- do not expose production secrets to pull request workflows

The deploy workflow already points to `environment: production`, so GitHub can enforce approvals once the environment rule is configured.

## Production Secrets

Required secrets:

- `YC_SERVICE_ACCOUNT_KEY_JSON`
- `YC_CLOUD_ID`
- `YC_FOLDER_ID`
- `YC_PROD_REGISTRY_ID`
- `YC_PROD_BACKEND_INSTANCE_ID`
- `ROCKETFLOW_PROD_DB_URL`
- `ROCKETFLOW_PROD_DB_USERNAME`
- `ROCKETFLOW_PROD_DB_PASSWORD`

Optional secrets:

- `ROCKETFLOW_PROD_FCM_CREDENTIALS_JSON`

Recommended variables:

- `ROCKETFLOW_PROD_ALLOWED_ORIGINS`
- `ROCKETFLOW_PROD_ALLOWED_ORIGIN_PATTERNS`
- `ROCKETFLOW_PROD_HEALTH_URL`
- `ROCKETFLOW_PROD_NOTIFICATIONS_SCHEDULER_ENABLED`
- `ROCKETFLOW_PROD_NOTIFICATIONS_FCM_ENABLED`
- `ROCKETFLOW_PROD_FCM_PROJECT_ID`

## Promotion Flow

1. Push code to a feature branch.
2. Open a pull request into `master`.
3. Wait for `backend-verify`, `web-verify`, and `android-verify`.
4. Merge only after all required checks are green.
5. Start `Backend Yandex Prod Deploy` manually.
6. Confirm the production health check is green.

## Current Limits

- Web and Android gates are build-only, not device/browser runtime certification.
- Terraform validation still requires local or CI Terraform installation.
- Production HTTPS is not yet configured in this baseline.
- Backend horizontal scaling remains blocked until scheduler and notification behavior are certified for multiple instances.
