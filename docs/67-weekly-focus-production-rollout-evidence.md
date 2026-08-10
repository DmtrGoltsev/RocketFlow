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

- Unsigned APK SHA-256: `1763de390dd587c686fe84152c521a2d92e65b747fb2689ec2076c0560c576d7`.
- Signing state: unsigned.
- Installability: not installable.
- Firebase configuration: absent.
- Production Android release: not performed.

## Residual Evidence Gap

Authenticated production smoke remains open. Completion requires a sanitized record of successful authentication and the intended minimal authenticated Calendar/Weekly Focus path; health checks alone do not satisfy this gate.
