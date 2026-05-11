# METLA Security Review

## 2026-05-04 Repeat Of First-Task Run

- Status: `Finalized`.
- Run anchor: strict-mode repeat started after the user's repeat-the-first-task message in this chat.
- Source of truth: `master@8f19b6ad221f46d56364bdecb75de31d9f3067e7` on `2026-05-04`.
- Scope authority: only current-run evidence produced after that message.
- Prior-artifact rule: any older `docs/metla.md` content was used only for formatting continuity, not as evidence.
- Reading rule: finalization used only the current-run packets from planner, context-reader, six security reviewers, and validator decisions. No new broad repo review was performed during finalization.
- Dirty-worktree note: the context-reader recorded only one untracked noise file, `docs/55-next-chat-transition-prompt.md`.
- Final confirmed count: `8`.
- Severity totals: `High 2`, `Medium 6`, `Low 0`.

## Methodology Summary

- Planner: `Herschel`.
- Designated context-reader: `Aquinas`.
- Security reviewers: `Parfit`, `Ramanujan`, `Helmholtz`, `Hilbert`, `Russell`, `Peirce`.
- Review topology: `planner -> context-reader -> 6 independent reviewers -> validator-led acceptance -> integrator finalization`.
- Acceptance rules used in this run:
  - quorum acceptance for findings with compatible multi-reviewer support
  - bounded-gate acceptance for strong single-packet findings explicitly approved by the validator

## Evidence Basis And Acceptance Outcome

- Accepted by quorum:
  - `F-01`
  - `F-02`
  - `F-03`
- Accepted by bounded gate:
  - `F-04`
  - `F-05`
  - `F-06`
  - `F-07`
  - `F-08`
- Held or rejected out of the confirmed set:
  - collaborator create-task on shared folder/goal
  - direct-task-share parent metadata leak
  - creator identity exposure in task DTOs
  - refresh rotation path
  - dangerous-execution / RCE / SSRF / arbitrary file-read claims

| ID | Severity | Finding | Acceptance basis | Final decision |
| --- | --- | --- | --- | --- |
| `F-01` | Medium | Share-link bearer token is carried in URL paths | quorum | Confirmed |
| `F-02` | Medium | Device registrations can be rebound across accounts | quorum | Confirmed |
| `F-03` | Medium | Local-first logout can leave live server-side session or device state behind | quorum | Confirmed |
| `F-04` | High | Redeemed share-link survives later revoke | bounded gate | Confirmed |
| `F-05` | Medium | Replayable refresh-bearing web session is stored in `localStorage` | bounded gate | Confirmed |
| `F-06` | Medium | Android cleartext API transport remains buildable and default-enabled in current config | bounded gate | Confirmed |
| `F-07` | High | Manual GHCR publish can mint trusted mutable tags from `workflow_dispatch` refs without a repo-visible publication gate | bounded gate | Confirmed |
| `F-08` | Medium | Published backend artifact is rebuilt after the Maven test gate instead of promoting the tested artifact | bounded gate | Confirmed |

## Confirmed Findings

### `F-01` Share-link bearer token is carried in URL paths

- Severity: `Medium`.
- Acceptance basis: quorum.
- Summary: current-run reviewer packets converged on the same root: share-link capability tokens are exposed as URL path material end-to-end, including backend endpoints and Android link handling.
- Current-run refs already cited:
  - `backend/src/main/java/com/rocketflow/sharing/SharingController.java`
  - `backend/src/main/java/com/rocketflow/sharing/SharingApi.java`
  - `android/app/src/main/java/com/rocketflow/companion/sharing/SharingRepository.kt`
  - `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- Impact: any log, browser history, clipboard observer, proxy, or telemetry surface that captures full request paths or copied URLs can capture a replayable share capability until expiry or revocation.

### `F-02` Device registrations can be rebound across accounts

- Severity: `Medium`.
- Acceptance basis: quorum.
- Summary: current-run reviewer packets showed that device registration resolution trusts caller-supplied `pushToken` or `installationId` as global logical-device keys and reassigns ownership when one matches an existing row.
- Current-run refs already cited:
  - `backend/src/main/java/com/rocketflow/notifications/DevicesService.java`
  - `backend/src/main/java/com/rocketflow/notifications/DeviceRegistrationRepository.java`
  - `backend/src/main/resources/db/migration/V7__notifications_devices.sql`
  - `backend/src/main/resources/db/migration/V8__device_registration_logical_device_upsert.sql`
  - `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`
- Impact: if an attacker learns another device's `pushToken` or `installationId`, reminder routing and logical ownership can be rebound across account boundaries.

### `F-03` Local-first logout can leave live server-side session or device state behind

- Severity: `Medium`.
- Acceptance basis: quorum.
- Summary: current-run reviewer packets showed that both web and Android can present logout as complete before backend logout and device cleanup are durably confirmed.
- Current-run refs already cited:
  - `web/src/features/auth/AuthProvider.tsx`
  - `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
  - `android/app/src/main/java/com/rocketflow/companion/auth/AuthRepository.kt`
  - `android/app/src/main/java/com/rocketflow/companion/notifications/NotificationsRepository.kt`
  - `backend/src/main/java/com/rocketflow/auth/AuthController.java`
  - `backend/src/main/java/com/rocketflow/auth/AuthService.java`
- Impact: a user can believe sign-out finished while a refresh-capable session or a registered notification target remains live on the server.

### `F-04` Redeemed share-link survives later revoke

- Severity: `High`.
- Acceptance basis: bounded gate.
- Summary: validator accepted the current-run evidence that redeeming a share link mints persistent share rows, while later revocation changes link state but does not offboard the already accepted collaborator.
- Current-run refs already cited:
  - `backend/src/main/java/com/rocketflow/sharing/SharingService.java`
  - `backend/src/main/java/com/rocketflow/sharing/SharingAccessService.java`
  - `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`
- Impact: once a leaked or forwarded link has been redeemed, later revoking the link does not contain that access.

### `F-05` Replayable refresh-bearing web session is stored in `localStorage`

- Severity: `Medium`.
- Acceptance basis: bounded gate.
- Summary: validator accepted the current-run evidence that the web client stores a full auth session, including refresh-bearing material, in script-readable `localStorage` and uses it to restore sessions on boot.
- Current-run refs already cited:
  - `web/src/features/auth/auth-storage.ts`
  - `web/src/features/auth/types.ts`
  - `web/src/features/auth/auth-api.ts`
- Impact: any browser-side code execution or equivalent storage access can steal durable session material and replay refresh flows for account takeover.

### `F-06` Android cleartext API transport remains buildable and default-enabled in current config

- Severity: `Medium`.
- Acceptance basis: bounded gate.
- Summary: validator accepted the current-run evidence that Android transport security remains configuration-driven, cleartext is permitted for `http://` bases, and the current default configuration points at a cleartext API base.
- Current-run refs already cited:
  - `android/app/build.gradle.kts`
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/java/com/rocketflow/companion/network/HttpJsonClient.kt`
- Impact: when such a build is used, login credentials, bearer tokens, refresh traffic, device registration data, and sharing flows can be observed or modified by a network-positioned attacker.

### `F-07` Manual GHCR publish can mint trusted mutable tags from `workflow_dispatch` refs without a repo-visible publication gate

- Severity: `High`.
- Acceptance basis: bounded gate.
- Summary: validator accepted the current-run evidence that the backend image publish workflow can be manually dispatched from selected refs, uses operator-controlled tags, can append `latest`, and shows no repo-visible protected-ref or publication gate.
- Current-run refs already cited:
  - `.github/workflows/backend-image-publish.yml`
- Impact: a repo actor who can dispatch this workflow can publish unreviewed or non-release code under trusted mutable image tags consumed downstream.

### `F-08` Published backend artifact is rebuilt after the Maven test gate instead of promoting the tested artifact

- Severity: `Medium`.
- Acceptance basis: bounded gate.
- Summary: validator accepted the current-run evidence that the release path tests one build output and then rebuilds the shipped backend artifact inside Docker with tests skipped, instead of promoting the exact tested artifact.
- Current-run refs already cited:
  - `.github/workflows/backend-image-publish.yml`
  - `.github/workflows/backend-verify.yml`
  - `backend/Dockerfile`
- Impact: the artifact that reaches the registry can diverge from the artifact that passed the main verification gate, weakening release provenance.

## Held / Rejected Out Of Confirmed Set

### collaborator create-task on shared folder/goal

- Final decision: held out of the confirmed set.
- Reason: it was raised as a current-run candidate by one reviewer, but the validator did not accept it into the final set for this run.

### direct-task-share parent metadata leak

- Final decision: held out of the confirmed set.
- Reason: the current run produced only a single-packet low-severity metadata concern, and it was not validator-accepted.

### creator identity exposure in task DTOs

- Final decision: held out of the confirmed set.
- Reason: the current run produced only a single-packet low-severity disclosure concern, and it was not validator-accepted.

### refresh rotation path

- Final decision: held out of the confirmed set.
- Reason: although the context-reader revalidated the mechanics, the validator explicitly marked the exploit packet as insufficient for confirmation in this run.

### dangerous-execution / RCE / SSRF / arbitrary file-read claims

- Final decision: rejected from the confirmed set.
- Reason: the dangerous-execution reviewer did not produce a confirmed current-run packet for these classes.

## Blind Spots And Residual Uncertainty

- GitHub org and environment controls remain out-of-repo unknowns, including who can dispatch publish workflows, protected refs, approvals, and GHCR tag immutability.
- Actual Android release configuration was not validated from a shipped production artifact, including whether production builds retain the current cleartext-capable default API base.
- The share-link URL-token finding does not independently establish real production leakage through logging, APM, reverse proxies, browser history, or clipboard capture; it confirms that the token shape is exposure-prone.
- The device-rebind finding assumes an attacker can learn a valid `pushToken` or `installationId`; the leak source was not established in the current run.
- The `localStorage` session finding assumes browser-side code execution or equivalent storage access; the current run did not separately establish an XSS source.

## File Finalized In This Step

- Canonical report: `C:\Users\hp\Documents\Codex\RocketFlow\docs\metla.md`
