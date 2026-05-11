# RocketFlow GitHub CI/CD Setup

This file is not executed by GitHub.

Executable CI/CD files live in `.github/workflows/*.yml`. This document explains what those workflows do and how to apply the non-file GitHub settings that cannot be enforced by a markdown file.

## What GitHub Executes

These workflows already run on every `push`, every `pull_request`, and can also be started manually:

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

The production deploy workflow is also executable, but it is manual:

- workflow: `Backend Yandex Prod Deploy`
- trigger: `workflow_dispatch`
- GitHub environment: `production`

Production deploy is intentionally not automatic on `push`.

## What Must Be Applied In GitHub Settings

Branch protection is a GitHub repository setting, not a normal repo file. It must be applied through the GitHub UI, GitHub API, GitHub CLI, or infrastructure tooling.

Minimum branch protection for `master`:

- require status checks before merge
- require branch to be up to date before merge
- required checks:
  - `backend-verify`
  - `web-verify`
  - `android-verify`
- block force pushes
- block branch deletion
- require conversation resolution

When the team starts using pull requests consistently, also require pull requests before merging.

## Apply Branch Protection By Script

The repository includes an executable helper:

```powershell
$env:GITHUB_TOKEN = "<token-with-repository-admin-permission>"
./scripts/Set-GitHubBranchProtection.ps1
```

With pull requests required:

```powershell
$env:GITHUB_TOKEN = "<token-with-repository-admin-permission>"
./scripts/Set-GitHubBranchProtection.ps1 -RequirePullRequest
```

The script calls the GitHub REST API and applies the required checks:

- `backend-verify`
- `web-verify`
- `android-verify`

## Apply Production Environment Protection

The `production` environment must also be configured in GitHub settings:

- require manual approval before deployment
- store production secrets in the `production` environment when possible
- do not expose production secrets to pull request workflows

The deploy workflow already contains `environment: production`, so GitHub can enforce approvals after the environment rule is configured.

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

## Normal Promotion Flow

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
