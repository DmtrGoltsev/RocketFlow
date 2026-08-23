# Native iOS Delivery Evidence

Status: **repository implementation and simulator CI green; external production gates open**

Checkpoint date: `2026-08-23`

Branch: `codex/native-ios-companion`

Canonical app-code/build source: `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`

Documentation identity: this document is a living branch document. Its eventual docs-only commit SHA is intentionally separate from the app-code/build SHA above.

This document records the delivered native iOS repository state. It does not claim an App Store release, signed-device acceptance, production iOS push delivery, or completion of manual accessibility certification.

## Delivered scope

RocketFlow is a native SwiftUI application for iOS 16 and newer with exactly three top-level tabs: Planner, Calendar, and Focus.

The delivered source includes:

- register/login/logout and restored-session handling with Keychain-backed secrets;
- owned/shared Planner hierarchy, stable scroll restoration, details, editors, checklist/tags, links, sharing, permissions, moves/clones, and origin-aware navigation;
- Calendar month grid, exact `[from,toExclusive)` range loading/cache, marker semantics, selected-day agenda, and task routing;
- current Focus, weighted progress, candidate browse/search, optimistic durable add/remove/reorder, history, rollover, and cadence settings;
- account-scoped GRDB persistence, additive migrations, local/server ID mapping, deterministic pending-operation ordering, offline reads/writes, retry/conflict state, and reset/rebase flows;
- local task reminders with bounded occurrence scheduling, cancellation/reconciliation, durable defaults, account suspension, and task deep links;
- settings, network reachability, background-refresh hooks, remote notification parsing/dedupe, device-registration lifecycle, and task/focus deep-link coordination;
- app-wide Russian/English presentation, durable process restoration, account leases, and stale-response/session-generation guards.

The normative behavior contract remains [`70-native-ios-parity-contract.md`](70-native-ios-parity-contract.md).

## Project and dependency state

- XcodeGen source: `ios/project.yml`, version `2.46.0`.
- Generated project: `ios/RocketFlow.xcodeproj`, committed and parity-checked.
- SwiftPM lock: `ios/RocketFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, committed and parity-checked.
- Firebase iOS SDK: `12.17.0`.
- GRDB: `6.29.3`.
- Deployment target: iOS `16.0`.
- Bundle identifier: `com.rocketflow.companion.ios`.
- App version/build: `0.1.0` / `1`.
- `DEVELOPMENT_TEAM`: blank by design.
- Push entitlement: `aps-environment=development`; the repository contains no Apple Team or provisioning profile.

## Canonical CI evidence

Manual [iOS Verify run 32655691351](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32655691351), job `97233929959`, completed successfully for the canonical app source.

| Check | Result |
|---|---|
| XcodeGen `2.46.0` install and generation | PASS |
| Generated project equals committed `RocketFlow.xcodeproj` | PASS |
| Swift package resolution and committed lock parity | PASS |
| No-sign simulator build/test | PASS |
| Unit tests | `540/540` PASS |
| UI tests | `2/2` PASS |
| Total tests | `542/542` PASS |
| XCTest result artifact | `9497494137` |
| Generated project artifact | `9497494432` |

The xcresult proves automated test execution; it is not a substitute for signed-device notification, VoiceOver, Dynamic Type, or release-network evidence.

## CI trigger policy

On candidate branch `codex/native-ios-companion`, commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` changed verification scheduling to avoid duplicate feature-branch runs and email noise:

- feature branches: manual `workflow_dispatch` only;
- pull requests targeting `master`: automatic;
- pushes to `master`: automatic.

This candidate behavior applies to Backend, Web, Android, and iOS Verify. It is not yet default-branch policy: `origin/master` at `7d1ac74cf8f2bf7935c2578f3675db4ca54764bb` contains neither the CI trigger commit nor `ios-verify`. After merge it becomes the default behavior. On the candidate branch, automatic push runs and their email storm are stopped; genuine manual, pull-request, or later `master` failures may still notify subscribed users.

Production deploy/package/rollback workflows were not changed. GitHub branch protection was not configured or modified, and the recommendations in `docs/58-github-cicd-policy.md` are optional rather than enforced repository settings.

## Mac continuation path

The repository is ready for a Mac user to clone, check out, regenerate, resolve packages, and build without reconstructing project metadata:

```bash
git clone https://github.com/DmtrGoltsev/RocketFlow.git
cd RocketFlow
git checkout codex/native-ios-companion

cd ios
xcodegen generate --spec project.yml
git diff --exit-code -- RocketFlow.xcodeproj
xcodebuild -resolvePackageDependencies \
  -project RocketFlow.xcodeproj \
  -scheme RocketFlow-CI
```

This checks out the latest branch state. To reproduce run `32655691351` exactly, use `git checkout --detach 35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3` instead of the branch checkout. Open `ios/RocketFlow.xcodeproj` for simulator development or run the no-sign test command in [`ios/README.md`](../ios/README.md). XcodeGen `2.46.0` is required for exact parity with the committed project.

## API, signing, and push gates

The current personal/internal configuration explicitly uses the HTTP API endpoint documented in the iOS README. A narrow host-only ATS exception is present; arbitrary HTTP loads are not enabled. Production HTTPS and removal of the exception are mandatory before public/App Store release.

A signed physical-device build requires:

1. an Apple Developer Team and matching signing/provisioning configuration;
2. a bundle identifier registered for the selected team, changing the repository default locally if required;
3. development/production push capabilities appropriate to that profile;
4. an ignored local `GoogleService-Info.plist` matching the Firebase app;
5. Firebase/APNs credentials configured outside the repository.

Firebase Messaging produces the FCM registration token sent to RocketFlow; the API integration does not send a raw APNs token. No credentials, plist contents, token values, or provisioning material belong in repository commits or delivery evidence.

## Production boundary

Production backend/web remains deployed from `50a63270ae094fe08ee57b945be0930cb1115dfe` as release `sha-50a63270ae09`, with Flyway V21 according to [`69-v21-production-rollout.md`](69-v21-production-rollout.md) and [`production/rocketflow-live-status.md`](production/rocketflow-live-status.md).

The feature source contains Flyway/backend V22 support for `platform:"ios"` device registrations. V22 is **not deployed**. No production database inspection was performed for this documentation delivery, and no production iOS registration/push claim is made.

## Readiness verdict

**GO**:

- clone and open the committed Xcode project on Mac;
- regenerate with XcodeGen and verify parity;
- resolve locked packages;
- build and test on an iOS simulator without signing;
- continue native feature/integration work from the canonical app source.

**Not yet GO**:

- App Store or public production release;
- signed physical-device acceptance;
- production APNs/FCM registration and delivery;
- production iOS API use over HTTPS;
- final VoiceOver, largest Dynamic Type, orientation/IME, and notification-delivery evidence on physical supported devices.

Closing those gates requires external Apple/Firebase configuration, an evidenced backend/Flyway V22 production rollout, HTTPS, and archived device/manual accessibility results. Automated green CI alone must not be represented as App Store production readiness.
