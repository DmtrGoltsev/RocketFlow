# METLA Security Review

## Final Current-Run Report

- Run anchor: repeated strict-mode run started after the user's repeat-task message.
- Status: `Finalized` after validator follow-up decisions for the current repeated run only.
- Canonical revision: `HEAD 38257c9fd9de73f150c3ff030e9078435122ff94`.
- Artifacts used:
  - planner: `Lovelace`
  - context-reader: `Feynman`
  - security reviewers: `Kepler`, `Pauli`, `Rawls`, `Wegener`, `Boole`, `Gibbs`
- Prior-artifact rule: any earlier `docs/metla.md` content was treated as stale context only, not as source of truth.
- Reading rule: this finalization used the current-run packets and their already-cited references only. No new broad repo read was performed.
- Final confirmed count: `8`.

## Evidence Basis And Quorum / Gate Rationale

- Quorum-confirmed findings:
  - `RC-01`
  - `RC-02`
  - `RC-04`
  - `RC-06`
- Accepted via bounded gate after validator review:
  - `RC-03`
  - `RC-05`
  - `RC-07`
  - `RC-08`
- Kept out of the confirmed set:
  - `RC-09`

| Root ID | Deduped root cause | Supporting reviewers | Acceptance basis | Final decision |
| --- | --- | --- | --- | --- |
| `RC-01` | Invitation claim by unverified invited email | `Pauli`, `Rawls` | `2 of 6` compatible confirmations | Confirmed |
| `RC-02` | Collaborator writes can drive owner reminder or scheduling side effects | `Kepler`, `Rawls` | `2 of 6` compatible confirmations | Confirmed |
| `RC-03` | Concurrent reuse of one refresh token can mint multiple successor sessions | `Kepler` | bounded gate acceptance on direct code-path evidence | Confirmed |
| `RC-04` | Android backup-eligible plaintext session storage enables token replay | `Pauli`, `Boole` | `2 of 6` compatible confirmations | Confirmed |
| `RC-05` | Web `localStorage` holds replayable refresh-bearing session state | `Boole` | bounded gate acceptance on direct storage and refresh-flow evidence | Confirmed |
| `RC-06` | Manual GHCR publish path can push arbitrary refs as trusted mutable tags | `Wegener`, `Gibbs` | `2 of 6` compatible confirmations | Confirmed |
| `RC-07` | Mutable CI / build / base-image trust roots | `Wegener` | bounded gate acceptance on direct workflow and build-input evidence | Confirmed |
| `RC-08` | Push-token-based device binding is transferable and revocation is fragile | `Rawls` | bounded gate acceptance on direct API and integration-test evidence | Confirmed |
| `RC-09` | Reminder scheduler has no technical singleton / claiming control | `Gibbs` | insufficient for confirmed set in this run | Rejected / insufficient evidence |

## Confirmed Findings

### `RC-01` Unverified invited email can be claimed through self-registration

- Acceptance basis: quorum-confirmed.
- Summary: current-run packets independently showed that public registration can activate an account for a supplied email before mailbox proof, while invitation listing and acceptance remain anchored to `target_email`.
- Primary cited refs:
  - `backend/src/main/java/com/rocketflow/auth/AuthService.java`
  - `backend/src/main/resources/db/migration/V4__sharing_foundation.sql`
  - `backend/src/main/java/com/rocketflow/sharing/ShareInvitationRepository.java`
  - `backend/src/main/java/com/rocketflow/sharing/SharingService.java`
  - `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`
- Impact: unintended collaborator access to shared goals and tasks.

### `RC-02` Accepted collaborator writes can trigger owner-side reminder and scheduling effects

- Acceptance basis: quorum-confirmed.
- Summary: current-run packets independently tied collaborator task writes to owner-only reminder delivery and owner-policy scheduling side effects within the shared-resource model.
- Primary cited refs:
  - `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
  - `backend/src/main/java/com/rocketflow/notifications/NotificationDeliveryService.java`
  - `backend/src/main/java/com/rocketflow/notifications/NotificationPayloadFactory.java`
  - `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`
  - `docs/04-architecture-blueprint.md`
- Impact: collaborator-authored changes can affect owner-device reminders and owner-scoped scheduling outcomes.

### `RC-03` Refresh-token rotation can be branched through concurrent reuse

- Acceptance basis: bounded gate.
- Summary: validator accepted the single-review direct code-path claim that refresh uses a read-revoke-create flow without a concurrency guard strong enough to prevent one live refresh token from minting multiple successor sessions under race conditions.
- Primary cited refs:
  - `backend/src/main/java/com/rocketflow/auth/AuthService.java`
  - `backend/src/main/java/com/rocketflow/auth/AuthSessionRepository.java`
  - `backend/src/main/java/com/rocketflow/auth/AuthSession.java`
- Impact: a stolen refresh token can be reused in parallel to create more than one valid successor session.

### `RC-04` Android stores reusable auth tokens in backup-eligible plaintext preferences

- Acceptance basis: quorum-confirmed.
- Summary: current-run packets independently showed `allowBackup=true` together with plaintext `SharedPreferences` storage for reusable auth material and direct replayability through the refresh flow.
- Primary cited refs:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/java/com/rocketflow/companion/auth/SessionStore.kt`
  - `backend/src/main/java/com/rocketflow/auth/AuthService.java`
  - `backend/src/main/java/com/rocketflow/config/AuthProperties.java`
- Impact: exported, migrated, or extracted mobile app state can yield reusable session tokens.

### `RC-05` Web persists a replayable refresh-bearing session in script-readable `localStorage`

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct evidence that the web client stores replayable session material in `localStorage` and actively reuses the stored refresh token during restore.
- Primary cited refs:
  - `web/src/features/auth/auth-storage.ts`
  - `web/src/features/auth/types.ts`
  - `web/src/features/auth/AuthProvider.tsx`
  - `web/src/features/auth/auth-api.ts`
- Impact: any browser-context compromise or profile theft that can read application storage can replay the refresh token and take over the session.

### `RC-06` Manual GHCR publish can release arbitrary workflow-dispatch refs under trusted mutable tags

- Acceptance basis: quorum-confirmed.
- Summary: two reviewer packets independently showed that the repo-visible backend publish workflow can be manually dispatched, builds the selected ref, and can stamp mutable deployment tags before pushing to GHCR.
- Primary cited refs:
  - `.github/workflows/backend-image-publish.yml`
  - `scripts/Invoke-BackendDockerRuntimeSmoke.ps1`
  - `docs/11-devops-baseline.md`
- Impact: unreviewed or non-release refs can be published under trusted backend image tags.

### `RC-07` Repo-visible CI and build trust roots remain mutable

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct workflow and build-input evidence that third-party action refs, backend base images, and Android bootstrap inputs remain mutable in the repo-visible trust chain.
- Primary cited refs:
  - `.github/workflows/backend-verify.yml`
  - `.github/workflows/web-verify.yml`
  - `.github/workflows/android-verify.yml`
  - `backend/Dockerfile`
  - `android/gradle/wrapper/gradle-wrapper.properties`
- Impact: CI behavior and build outputs can drift or be poisoned through upstream mutable trust roots without a corresponding repo diff.

### `RC-08` Device registrations are transferable by bearer push token and revocation is fragile

- Acceptance basis: bounded gate.
- Summary: validator accepted the direct API and integration-test evidence that registration ownership can be reassigned by push token and that failed unregister paths can leave stale active device bindings.
- Primary cited refs:
  - `backend/src/main/resources/db/migration/V7__notifications_devices.sql`
  - `backend/src/main/java/com/rocketflow/notifications/DevicesService.java`
  - `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`
  - `android/app/src/main/java/com/rocketflow/companion/notifications/NotificationsRepository.kt`
  - `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- Impact: notification ownership and revocation can drift away from the intended account-to-device binding.

## Rejected / Insufficient-Evidence Items

- `RC-09` was kept out of the confirmed set.
  - Current-run evidence from `Gibbs` was concrete, but it remained a single-packet scheduler-control issue and did not clear the final acceptance bar for this run.
  - The strongest user-visible impact path is also partially latent at canonical `HEAD` because the sender behavior is still stubbed.
- General collaborator edit access to shared goals and tasks was not treated as a standalone confirmed authz bug in this run.
- Direct-task-share inheritance to parent goal or folder access stayed rejected on negative test and spec evidence.
- Workflow `image_tag` command injection stayed rejected because the reviewed publish path sanitizes the value.
- Android deep-link handling stayed out of the confirmed set because the current-run packets did not prove an auth bypass or data-return channel.
- Web `localStorage` persistence was not treated as standalone proof of XSS; only the replayable session-storage root cause was confirmed.

## Blind Spots / Remaining Risks

- No staging or production runtime access was available for this run.
- GitHub org controls, environment approvals, branch protections, package immutability, and actual deployment tag-consumption policy were not visible in repo-backed evidence.
- Firebase IAM scope, real push-delivery infrastructure, and external notification transport were not visible from the current-run evidence set.
- No Android backup extraction run or merged release-manifest inspection outside the cited packets was performed.
- Deployment topology, real actuator reachability, and singleton rollout guarantees remain out-of-repo unknowns.
- Canonical `HEAD` still differs from the dirty worktree, and this report intentionally stayed anchored to the current-run source-of-truth rule.
