# METLA Security Review

## 2026-05-03 Current-Run Final Report

- Status: `Finalized`.
- Run anchor: strict-mode run started after the user's 2026-05-03 request for a fresh current-state security review and new report file.
- Artifacts used:
  - planner: `James`
  - context-reader: `Pascal`
  - security reviewers: `Huygens`, `Laplace`, `Hume`, `Confucius`, `Peirce`, `Schrodinger`
- Prior-artifact rule: any pre-existing `docs/metla.md` content was treated as stale context only, not as source of truth.
- Reading rule: this finalization used only the current-run packets plus their already-cited references. No new broad repo read was performed.
- Deduped root-cause count: `10`.
- Final confirmed count: `8`.

## Evidence Basis And Quorum / Bounded-Gate Rationale

- Confirmed from quorum:
  - `RC-01`
  - `RC-02`
  - `RC-03`
- Accepted into the confirmed set via bounded gate after validator review:
  - `RC-04`
  - `RC-05`
  - `RC-06`
  - `RC-07`
  - `RC-09`
- Kept out of the confirmed set:
  - `RC-08`
  - `RC-10`

| Root ID | Deduped root cause | Supporting reviewers | Acceptance basis | Final decision |
| --- | --- | --- | --- | --- |
| `RC-01` | Link-redeemed shares survive share-link revocation and there is no in-scope owner offboarding path for already accepted link grants | `Huygens`, `Hume` | `2 of 6` compatible confirmations | Confirmed |
| `RC-02` | Refresh-token rotation is non-atomic and replayable under concurrent `/api/auth/refresh` use | `Huygens`, `Peirce` | `2 of 6` compatible confirmations | Confirmed |
| `RC-03` | Manual GHCR publish can build the selected workflow-dispatch ref and push trusted mutable tags without an in-repo protected-ref gate | `Confucius`, `Schrodinger` | `2 of 6` compatible confirmations | Confirmed |
| `RC-04` | Android can be built with cleartext API transport, exposing bearer and refresh-token flows when an `http://` base URL is used | `Laplace` | bounded gate acceptance on direct current-worktree transport evidence | Confirmed |
| `RC-05` | Share-link bearer tokens are carried in URL paths, increasing leakage risk through logs, history, and telemetry surfaces | `Hume` | bounded gate acceptance on direct API-shape evidence | Confirmed |
| `RC-06` | Device registration trusts caller-supplied push identifiers across accounts, allowing rebind if a token or installation ID leaks | `Hume` | bounded gate acceptance on direct code and integration-test evidence | Confirmed |
| `RC-07` | The backend image publish lane rebuilds the shipped artifact after verification instead of promoting the verified artifact | `Confucius` | bounded gate acceptance on direct release-provenance evidence | Confirmed |
| `RC-08` | Backend verify/publish smoke depends on a mutable third-party `postgres:16` image tag | `Confucius` | single-packet evidence, not accepted into confirmed set | Rejected / insufficient evidence |
| `RC-09` | Logout is allowed to succeed locally before backend logout and device-unregister cleanup are durably confirmed | `Peirce` | bounded gate acceptance on direct client and backend cleanup-order evidence | Confirmed |
| `RC-10` | Notification delivery sends to FCM before the dedupe record is durably committed, leaving a crash/rollback duplicate-send window | `Schrodinger` | single-packet evidence, not accepted into confirmed set | Rejected / insufficient evidence |

## Confirmed Findings

### `RC-01` Link-redeemed shares survive link revocation

- Acceptance basis: quorum-confirmed.
- Summary: two current-run reviewer packets independently showed that redeeming a share link creates persistent `folder_shares`, `goal_shares`, or `task_shares`, while revoking the link only changes `share_links` state and does not tear down already accepted grants.
- Primary refs already cited in current-run packets:
  - `backend/src/main/java/com/rocketflow/sharing/SharingService.java`
  - `backend/src/main/java/com/rocketflow/sharing/SharingAccessService.java`
  - `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`
  - `docs/05-api-contracts.md`
- Impact: leaked or forwarded share-link access cannot be fully offboarded after first redemption.

### `RC-02` Refresh-token rotation is replayable under concurrency

- Acceptance basis: quorum-confirmed.
- Summary: two current-run reviewer packets independently converged on the same refresh path: active session lookup, later revocation write, then successor minting, without a repo-visible atomic consume guard.
- Primary refs already cited in current-run packets:
  - `backend/src/main/java/com/rocketflow/auth/AuthService.java`
  - `backend/src/main/java/com/rocketflow/auth/AuthSessionRepository.java`
  - `backend/src/main/java/com/rocketflow/auth/AuthSession.java`
  - `backend/src/main/resources/db/migration/V2__auth_sessions.sql`
- Impact: one stolen refresh token can mint more than one valid successor session under race conditions.

### `RC-03` Manual GHCR publish can release arbitrary selected refs under trusted mutable tags

- Acceptance basis: quorum-confirmed.
- Summary: two current-run reviewer packets independently showed that the documented backend publish lane is `workflow_dispatch`, can push operator-controlled tags and `latest`, and has no repo-visible protected-ref or environment gate.
- Primary refs already cited in current-run packets:
  - `.github/workflows/backend-image-publish.yml`
  - `docs/31-wave-b-devops-staging-secrets.md`
  - `scripts/Invoke-BackendDockerRuntimeSmoke.ps1`
- Impact: unreviewed or non-release refs can be published under trusted backend image tags.

### `RC-04` Android cleartext transport can expose bearer and refresh-token flows

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct current-worktree evidence that Android can enable cleartext API transport when the configured base URL is `http://`, and the same client path carries login credentials, bearer tokens, and refresh-token flows.
- Primary refs already cited in current-run packets:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/build.gradle.kts`
  - `android/app/src/main/java/com/rocketflow/companion/network/HttpJsonClient.kt`
  - `android/app/src/main/java/com/rocketflow/companion/auth/AuthRepository.kt`
- Impact: if such a build is distributed, a network-positioned attacker can observe or tamper with authenticated mobile traffic.

### `RC-05` Share-link bearer tokens are carried in URL paths

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct API-shape evidence that share-link capabilities are exposed as URL path tokens end-to-end, increasing leakage risk through logs, copied URLs, history, and telemetry surfaces.
- Primary refs already cited in current-run packets:
  - `backend/src/main/java/com/rocketflow/sharing/SharingController.java`
  - `android/app/src/main/java/com/rocketflow/companion/sharing/SharingRepository.kt`
  - `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
  - `docs/11-devops-baseline.md`
  - `docs/04-architecture-blueprint.md`
- Impact: anyone who captures an active share-link URL can reuse that capability until expiry or revocation.

### `RC-06` Device registrations can be rebound by caller-supplied push identifiers

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct code and test evidence that registration resolution trusts caller-supplied `pushToken` or `installationId`, allowing cross-account reassignment if one of those identifiers leaks.
- Primary refs already cited in current-run packets:
  - `backend/src/main/java/com/rocketflow/notifications/DevicesService.java`
  - `backend/src/main/java/com/rocketflow/notifications/DeviceRegistrationRepository.java`
  - `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`
  - `backend/src/main/java/com/rocketflow/notifications/NotificationPayloadFactory.java`
  - `android/app/src/main/java/com/rocketflow/companion/notifications/RocketFlowMessagingService.kt`
- Impact: notification routing and device ownership can drift away from the intended account binding.

### `RC-07` Backend publish rebuilds the shipped artifact after verification

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct evidence that the canonical backend publish lane verifies one build path and then rebuilds the artifact inside Docker before shipping, rather than promoting the already verified artifact.
- Primary refs already cited in current-run packets:
  - `.github/workflows/backend-image-publish.yml`
  - `backend/Dockerfile`
  - `backend/pom.xml`
  - `docs/31-wave-b-devops-staging-secrets.md`
- Impact: the tested artifact and the shipped artifact can diverge, weakening release-path provenance.

### `RC-09` Logout is allowed to complete locally before authoritative server cleanup

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct client and backend evidence that web and Android local sign-out can complete before backend logout and device-unregister cleanup are durably confirmed.
- Primary refs already cited in current-run packets:
  - `web/src/features/auth/AuthProvider.tsx`
  - `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
  - `android/app/src/main/java/com/rocketflow/companion/auth/AuthRepository.kt`
  - `android/app/src/main/java/com/rocketflow/companion/notifications/NotificationsRepository.kt`
  - `backend/src/main/java/com/rocketflow/notifications/NotificationDeliveryService.java`
  - `backend/src/main/java/com/rocketflow/notifications/NotificationPayloadFactory.java`
- Impact: post-logout security state can lag behind visible sign-out, including stale session or stale device-registration effects.

## Rejected / Insufficient-Evidence Items

### `RC-08` Mutable `postgres:16` smoke-image trust root

- Final decision: kept out of the confirmed set.
- Reason: the current run produced only single-packet evidence for this root cause, and it was not accepted through the bounded gate.
- Current-run refs already cited:
  - `.github/workflows/backend-verify.yml`
  - `.github/workflows/backend-image-publish.yml`
  - `scripts/Invoke-BackendDockerRuntimeSmoke.ps1`
  - `README.md`
  - `docs/31-wave-b-devops-staging-secrets.md`

### `RC-10` Send-before-commit notification duplicate window

- Final decision: kept out of the confirmed set.
- Reason: the current run produced only single-packet evidence for this root cause, and it was not accepted through the bounded gate.
- Current-run refs already cited:
  - `backend/src/main/java/com/rocketflow/notifications/NotificationDeliveryService.java`
  - `backend/src/main/resources/db/migration/V7__notifications_devices.sql`
  - `backend/src/main/java/com/rocketflow/notifications/ReminderNotificationScheduler.java`
  - `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`

## Blind Spots / Remaining Risks

- GitHub org or environment controls, protected refs, GHCR immutability, and deployment tag-consumption policy are out-of-repo unknowns.
- Release-manifest and distribution policy for Android builds were not validated from shipped artifacts.
- Runtime logging, proxy, and APM behavior for share-link URL handling were not visible in repo-backed evidence.
- Firebase delivery infrastructure and production notification runtime were not available for live replay.
- Some accepted bounded-gate items depend on deployment choices outside the repo, especially Android transport configuration and image tag-consumption policy.

## Files Finalized In This Step

- Canonical report: `C:\Users\hp\Documents\Codex\RocketFlow\docs\metla.md`
- External snapshot copy: `C:\Users\hp\Documents\Codex\SecuritySnapshots\RocketFlow\2026-05-03-current-state-metla.md`
