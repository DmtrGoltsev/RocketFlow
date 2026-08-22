# RocketFlow Live Status

Last updated: 2026-08-22.

## Current production facts

- Backend systemd unit: `rocketflow-backend.service`.
- Backend current symlink: `/opt/rocketflow/current/rocketflow-backend.jar`.
- Public web route: `/rocket/`.
- Nginx web root target: `/var/www/rocketflow-web/current`.
- Public API route: `/rocket-api/`.
- Nginx API upstream: `127.0.0.1:8080/api/`.
- Production database: `rocketflow_prod`.
- Deployed source SHA: `50a63270ae094fe08ee57b945be0930cb1115dfe`.
- Active release id: `sha-50a63270ae09`.
- Flyway schema history: `V21` (`21/21`).
- GitHub Actions deploy run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905): `success`.
- Backend service: active; backend and web current symlinks resolve to release `sha-50a63270ae09`.
- Public backend and web checks: HTTP `200`.
- Duplicate deployment / rollback: none / not used.
- Focus cadence: disabled.
- Web Push: disabled.
- Android: sideload APK `0.1.1` (`versionCode 2`) installed as an update and passed runtime verification; this is not a Play Store production release.
- Authenticated production API smoke: passed with `0` unexpected HTTP `5xx` responses.

V21 priority-retirement compatibility, Android Planner scroll restoration, SQLite lifecycle, and compact landscape editor work are deployed or rolled out as recorded in `docs/69-v21-production-rollout.md`. Pre-deploy production was release `sha-910c061de4af` at Flyway `20`; the joint backend/web promotion advanced production to release `sha-50a63270ae09` and Flyway `21`.

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

Rollback workflow ID `330828165` is active. It was not used for release `sha-50a63270ae09`.

The current docs-only follow-up commit is not the deployed source. Canonical V21 rollout evidence is in `docs/69-v21-production-rollout.md`; the prior V20 rollout remains documented in `docs/67-weekly-focus-production-rollout-evidence.md`.

The current Android sideload artifact is RocketFlow `0.1.1` (`versionCode 2`) with SHA-256 `3DF9EB210D801D932A4C736A0EF682C8C0AADCB36536B81CA19267F326C52AF7`. `adb install -r` preserved UID `10227` and `firstInstallTime`; cold launch passed, captured crashes / ANRs were `0 / 0`, and the Login screen was visible. The prior `0.1.0` debug-certificate APK and rejected unsigned APK remain historical evidence. No APK or build output is committed.

This debug-cert build is for direct sideloading, not Play Store production signing. Future sideload updates must retain the same certificate. FCM configuration remains absent, so no push-delivery claim is made.

## Readiness signals

A deploy or rollback is considered ready only when these checks pass in the workflow output:

- `rocketflow-backend.service` is active;
- `/opt/rocketflow/current/rocketflow-backend.jar` resolves to the expected release;
- `/var/www/rocketflow-web/current/index.html` exists;
- local `/rocket/` route returns the web root marker;
- local backend health returns `"status":"UP"`;
- `rocketflow_prod.flyway_schema_history` has at least 21 rows after the V21 release.

The completed V21 rollout preflighted release `sha-910c061de4af` at Flyway `20`, required manifest target `21`, and jointly promoted backend and web through the existing helper. Post-start Flyway reached `21`, with no duplicate deploy and no rollback. Application rollback remains forward-schema compatible: it starts from `>=20`, records the pre-count, and fails closed unless a readable target manifest declares an integer `flyway_history_min_rows` between 20 and that pre-count inclusive. It must not decrease Flyway history or perform database downgrade, repair, or restore.
