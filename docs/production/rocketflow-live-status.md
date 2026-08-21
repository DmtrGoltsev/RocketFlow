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
- Deployed source SHA: `910c061de4af9395d9bb682624bd966b2977a738`.
- Active release id: `sha-910c061de4af`.
- Flyway schema history: `V20` (`20/20`).
- GitHub Actions deploy run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631): `success`.
- Local and public health: passed.
- Captured post-deploy errors / HTTP `5xx` / service restarts: `0 / 0 / 0`.
- Focus cadence: disabled.
- Web Push: disabled.
- Android: installable sideload APK built from the deployed source is verified with the existing debug certificate; it has no Firebase configuration and is not a Play Store production release.
- Authenticated production smoke: not completed.

The current repository delivery candidate includes V21 priority-retirement compatibility, Android Planner scroll restoration, SQLite lifecycle, and compact landscape editor work, but none of it is deployed. Candidate verification is backend `142/142`, web `61/61` plus build/audit PASS, and Android `90/90` plus build/lint/debug Android-test APK assembly PASS. Production remains exactly at the source, release, and Flyway V20 facts above until a successful approved deploy is recorded. The APK history below is also unchanged.

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

Rollback workflow ID `330828165` is active. It was not used for release `sha-910c061de4af`.

The current docs-only follow-up commit is not the deployed source. Canonical rollout evidence is in `docs/67-weekly-focus-production-rollout-evidence.md`.

The current Android sideload artifact is `android/app/build/outputs/apk/release/RocketFlow-0.1.0-prod-debugcert.apk` (SHA-256 `2209f2b5e8ee8f01fa486d997f898d9fc08db98cf02e0b22d3182fa1026cc4d1`, `3287664` bytes). It is signed with the existing debug certificate, installs successfully with `adb install -r`, and passed cold-launch, logcat, health, `77` test, and lint (`0` errors) checks. The prior unsigned APK with SHA-256 `1763de390dd587c686fe84152c521a2d92e65b747fb2689ec2076c0560c576d7` is retained only as superseded historical evidence after Android rejected it as damaged/not installable. No APK or build output is committed.

This debug-cert build is for direct sideloading, not Play Store production signing. Future sideload updates must retain the same certificate. FCM configuration remains absent, so no push-delivery claim is made.

## Readiness signals

A deploy or rollback is considered ready only when these checks pass in the workflow output:

- `rocketflow-backend.service` is active;
- `/opt/rocketflow/current/rocketflow-backend.jar` resolves to the expected release;
- `/var/www/rocketflow-web/current/index.html` exists;
- local `/rocket/` route returns the web root marker;
- local backend health returns `"status":"UP"`;
- `rocketflow_prod.flyway_schema_history` has at least 20 rows after the V20 release.

For a future V21 rollout only, the deploy workflow preflights the current V20 baseline at `>=20`, requires manifest target `=21` and post-start `>=21`, and jointly promotes backend and web through the existing helper. This is safe because the new web is compatible with both V20 and V21; Android follows separately after readiness. Application rollback starts from `>=20`, records the pre-count, and now fails closed unless a readable target manifest declares integer `flyway_history_min_rows` between 20 and that pre-count inclusive. Post-count must remain `>=20` without decreasing; a V20 binary with minimum 20 may run on retained V21 schema, with no database downgrade, repair, or restore. This workflow hardening is repository candidate state only and does not change the live V20 facts above; no deploy or push was performed.
