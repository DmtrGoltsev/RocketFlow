# Weekly Focus Production Rollout Evidence

Evidence captured on `2026-08-10`. This is the immutable production change record for the backend/web and database rollout. It contains no credentials, tokens, provider keys, or production data.

## Release Identity

- Deployed source SHA: `910c061de4af9395d9bb682624bd966b2977a738`.
- Release id: `sha-910c061de4af`.
- Deploy source branch: `release-weekly-focus-calendar-910c061de4af`.
- The commit adding this evidence is a later docs-only commit on `codex/weekly-focus-calendar-web-push`. It is not the deployed source and does not change the active release id.

## Deployment

- Workflow: `.github/workflows/backend-hexcore-prod-deploy.yml`.
- GitHub Actions run: [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631).
- Run conclusion: `success`.
- Flyway state after promotion: `V20`, 20 migrations present (`20/20`).
- Local backend health: passed.
- Public backend health: passed.
- Captured post-deploy application errors: `0`.
- Captured post-deploy HTTP `5xx` responses: `0`.
- Captured post-deploy service restarts: `0`.

Health evidence proves service readiness only. An authenticated production smoke was not completed and remains an explicit gap.

## Backup

- File: `rocketflow_prod_20260810T045958Z.dump`.
- Size: `223191` bytes.
- SHA-256: `783590b8fa26f6d2882aab0a5cf670b483be5895fd80b6a915cd4c9946841b39`.
- `pg_restore -l`: `238` catalog entries, `PASS`.

The dump itself is sensitive and is not stored in the repository.

## Rollback And Feature Flags

- Rollback workflow: `.github/workflows/rocketflow-prod-rollback.yml`.
- Rollback workflow ID: `330828165`.
- Workflow state: `active`.
- Rollback used for this rollout: no.
- Focus cadence: disabled.
- Web Push: disabled.

No production FCM or Web Push delivery is claimed while these capabilities remain disabled.

## Android Artifact

- Historical unsigned APK SHA-256: `1763de390dd587c686fe84152c521a2d92e65b747fb2689ec2076c0560c576d7`. Android reported this artifact as a damaged package; it was not installable and is superseded by the artifact below.
- Current sideload artifact: `android/app/build/outputs/apk/release/RocketFlow-0.1.0-prod-debugcert.apk` (standard ignored build-output path; the APK is not committed).
- Exact source SHA: `910c061de4af9395d9bb682624bd966b2977a738`.
- Size: `3287664` bytes.
- SHA-256: `2209f2b5e8ee8f01fa486d997f898d9fc08db98cf02e0b22d3182fa1026cc4d1`.
- Signing state: APK Signature Scheme v2 and v3, using the existing debug certificate with SHA-256 fingerprint `b5675864b9cb8a046d889f54e58f5b0256d6937ecd448e69d7faa955e587aca0`; no new key was created.
- Packaging checks: `zipalign` valid; release manifest has `debuggable=false`; production API configuration is embedded.
- Device proof: `adb install -r` succeeded; the installed APK hash exactly matched the built artifact; app UID, first-install timestamp, and app data were preserved.
- Runtime proof: cold launch, logcat review, and backend health check passed.
- Build verification: Android `77` tests passed and lint reported `0` errors.
- Firebase configuration: absent; no FCM delivery claim is made for this artifact.
- Distribution status: installable direct-sideload artifact, not a Play Store production release. The debug certificate is not a Play production signing identity, and future sideload updates must use the same certificate to preserve update compatibility.

## Residual Evidence Gap

Authenticated production smoke remains open. Completion requires a sanitized record of successful authentication and the intended minimal authenticated Calendar/Weekly Focus path; health checks alone do not satisfy this gate.
