# HexCore Production Runbook

Initial setup date: 2026-05-16.
Last updated: 2026-06-14.

## Server role

HexCore hosts the RocketFlow production backend, web build, Nginx routes, and PostgreSQL database.

Live routing contract:

- Web: `/rocket/ -> /var/www/rocketflow-web/current`.
- API: `/rocket-api/ -> 127.0.0.1:8080/api/`.
- Backend service: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Production database: `rocketflow_prod`.
- Flyway history baseline: 18 rows.

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

The application rollback workflow does not restore database backups and does not run Flyway migration or repair commands.
