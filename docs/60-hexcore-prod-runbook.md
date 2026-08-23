# HexCore Production Runbook

Initial setup date: 2026-05-16.
Last updated: 2026-08-23.

## Server role

HexCore hosts the RocketFlow production backend, web build, Nginx routes, and PostgreSQL database.

Live routing contract:

- Web: `/rocket/ -> /var/www/rocketflow-web/current`.
- API: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Production database: `rocketflow_prod`.
- Current Flyway history state: `V21`, 21 rows (`21/21`).

Current deployed source is `50a63270ae094fe08ee57b945be0930cb1115dfe`, release id `sha-50a63270ae09`. GitHub Actions deploy run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905) completed successfully. Current rollout evidence is recorded in `docs/69-v21-production-rollout.md`; `docs/67-weekly-focus-production-rollout-evidence.md` is the immutable historical V20 checkpoint.

Production has already completed the V21 rollout. The deploy workflow intentionally remains compatible with a readable V20-or-newer source state: preflight requires `>=20` rows, the release manifest declares Flyway minimum `21`, and post-start checks require `>=21` rows. The existing helper jointly promotes backend and web. Application rollback accepts a V20-or-newer database baseline, requires the Flyway count not to decrease, and uses a V20 application artifact that is forward-compatible with retained V21 schema.

## Runtime layout

Backend release jars:

`/opt/rocketflow/releases/rocketflow-backend-<release_id>.jar`

Backend current symlink:

`/opt/rocketflow/current/rocketflow-backend.jar`

Web release archives:

`/opt/rocketflow/web-releases/rocketflow-web-<release_id>.tar.gz`

Active web root:

`/var/www/rocketflow-web/current`

Release manifests and checksums:

- `/opt/rocketflow/releases/rocketflow-release-manifest-<release_id>.json`
- `/opt/rocketflow/releases/rocketflow-release-<release_id>.sha256`
- `/opt/rocketflow/releases/rocketflow-release-<release_id>.remote.sha256`

## CI/CD entrypoints

Production deploy:

`.github/workflows/backend-hexcore-prod-deploy.yml`

GHCR package:

`.github/workflows/rocketflow-ghcr-package.yml`

Manual application rollback:

`.github/workflows/rocketflow-prod-rollback.yml`

Rollback is fail-closed: the target release manifest must be readable and its `flyway_history_min_rows` must be a JSON integer from `20` through the recorded pre-rollback Flyway count, inclusive. Missing/unreadable manifests, missing or string/boolean/out-of-range values are rejected. After promotion, Flyway history must remain at least 20 and must not decrease. This permits a V20 binary with minimum 20 on retained V21 schema without database downgrade.

## Required GitHub secret names

Only these names should appear in repo files:

- `HEXCORE_PROD_SSH_HOST`
- `HEXCORE_PROD_SSH_USER`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`
- `HEXCORE_PROD_SSH_KNOWN_HOSTS`

Store values only in GitHub repository or environment secrets.

## Deploy readiness evidence

During an approved production deploy, the workflow records:

- release id;
- current backend symlink;
- current web root symlink;
- `rocketflow-backend.service` active state;
- local backend health at `127.0.0.1:8080/api/health`;
- local Nginx web marker at `/rocket/`;
- Flyway history row count for `rocketflow_prod`;
- local and remote SHA256 verification output.

For every approved deploy, retain the readable preflight count (`>=20`) and post-start count (`>=21`) in change evidence. Current production truth remains V21 until a later evidenced rollout updates `docs/production/rocketflow-live-status.md`; candidate V22 source is not deploy evidence.

## Operator verification

From an operator workstation, verify public endpoints with the documented public host for the environment:

```powershell
Invoke-RestMethod -Uri http://<production-host>/rocket-api/health
```

On the server, read-only checks are:

```bash
systemctl status rocketflow-backend.service
journalctl -u rocketflow-backend.service -n 100 --no-pager
curl http://127.0.0.1:8080/api/health
curl http://127.0.0.1/rocket-api/health
curl http://127.0.0.1/rocket/
```

Service restart/reload commands are intentionally not part of this local runbook edit. Production changes should go through the approved workflows or an operator-approved emergency procedure.

## Backup reference

Production database backup handling is documented separately:

`docs/65-prod-db-backup-local-runbook.md`

The application rollback workflow does not downgrade or restore the database and does not run Flyway migration, undo, or repair commands.
