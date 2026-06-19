# RocketFlow Live Status

Last updated: 2026-06-14.

## Current production facts

- Backend systemd unit: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Public web route: `/rocket/`.
- Nginx web root target: `/var/www/rocketflow-web/current`.
- Public API route: `/rocket-api/`.
- Nginx API upstream: `127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Flyway schema history: 18 rows.

## Release state model

Production releases are identified by `release_id`, normally `sha-<12-char-git-sha>`.

Backend artifacts are staged at:

`/opt/rocketflow/releases/rocketflow-backend-<release_id>.jar`

Web artifacts are staged at:

`/opt/rocketflow/web-releases/rocketflow-web-<release_id>.tar.gz`

The deploy workflow also writes:

- `/opt/rocketflow/releases/rocketflow-release-manifest-<release_id>.json`
- `/opt/rocketflow/releases/rocketflow-release-<release_id>.sha256`
- `/opt/rocketflow/releases/rocketflow-release-<release_id>.remote.sha256`

## Operational posture

Production is live behind the HexCore host and is managed by GitHub Actions with a `production` environment gate. Deploy, package publish, and rollback are separate workflows so package publishing never triggers deployment.

Database rollback is outside the app rollback workflow. The rollback workflow explicitly rejects `include_db_rollback=true`.

## Readiness signals

A deploy or rollback is considered ready only when these checks pass in the workflow output:

- `rocketflow-backend.service` is active;
- `/opt/rocketflow/current/rocketflow-backend.jar` resolves to the expected release;
- `/var/www/rocketflow-web/current/index.html` exists;
- local `/rocket/` route returns the web root marker;
- local backend health returns `"status":"UP"`;
- `rocketflow_prod.flyway_schema_history` has at least 18 rows.
