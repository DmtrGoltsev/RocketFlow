# V21 Production Rollout

Last updated: 2026-08-22.

## Outcome

V21 was deployed successfully as a joint backend and web release from source `50a63270ae094fe08ee57b945be0930cb1115dfe` with release id `sha-50a63270ae09`.

- GitHub Actions run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905): `success`.
- Pre-deploy release: `sha-910c061de4af`, Flyway `20`.
- Post-deploy Flyway: `21`.
- `rocketflow-backend.service`: active.
- Backend and web current symlinks: release `sha-50a63270ae09`.
- Public backend and web checks: HTTP `200`.
- Duplicate deployment: none.
- Rollback: not used.

The deployment used manifest `rocketflow-release-manifest-sha-50a63270ae09.json` and GitHub artifact `9470293960`. The artifact ZIP SHA-256 was recorded as `54b9994e...f49e`; all packaged checksum verification passed.

## Controlled Waiver

The user granted a one-time waiver to proceed without a fresh backup or recovery point. This waiver is not precedent for future deployments. A future-deploy backup and rollback task was recorded in Obsidian.

No database rollback, Flyway repair, or restore was performed.

## Authenticated API Smoke

The production API smoke passed all planned steps:

1. Register.
2. Login.
3. Create folder.
4. Create goal.
5. Create task.
6. Get task.
7. Patch task and confirm the priority compatibility shadow was preserved.
8. Delete test data.
9. Logout.
10. Confirm final health.

Unexpected HTTP `5xx` responses: `0`.

## Android Sideload Rollout

RocketFlow APK `0.1.1` (`versionCode 2`) was verified with SHA-256 `3DF9EB210D801D932A4C736A0EF682C8C0AADCB36536B81CA19267F326C52AF7`.

- `adb install -r`: passed.
- Existing app UID `10227`: preserved.
- Existing `firstInstallTime`: preserved.
- Cold launch: passed.
- Captured crashes / ANRs: `0 / 0`.
- Initial visible state: Login screen.

This is direct sideload evidence; it does not claim a Play Store release or production push-provider certification.

## Related Documents

- Current production truth: `docs/production/rocketflow-live-status.md`.
- Current handoff summary: `docs/33-current-state-summary.md`.
- V21 delivery contract and implementation evidence: `docs/68-scroll-and-priority-retirement-delivery.md`.
- Historical V20 rollout evidence: `docs/67-weekly-focus-production-rollout-evidence.md`.
