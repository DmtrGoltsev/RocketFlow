# RocketFlow iOS

Native SwiftUI companion for iOS 16 and newer. Branch `codex/native-ios-companion` is the living delivery branch; canonical app-code/build evidence is pinned to `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`. Later docs-only commits may move branch HEAD without changing that evidence identity.

`project.yml` is the XcodeGen source of truth. The generated `RocketFlow.xcodeproj` and its SwiftPM `Package.resolved` are committed so a Mac checkout can open and build immediately; CI regenerates the project and fails if it differs from the committed copy.

## Delivered application

- Three native tabs: Planner, Calendar, and Focus.
- SwiftUI feature views with MVVM/store-driven state and URLSession async networking.
- Keychain session storage and account-scoped GRDB persistence.
- Local-first planning operations, deterministic sync, conflict/retry recovery, exact Calendar range cache, and durable Focus action queue.
- Native task/folder/goal/idea/note details and editors, checklist/tags, sharing, links, local task reminders, settings, and notification/deep-link routes.
- App-wide Russian and English copy, durable process restoration, and account leases that prevent cross-account cache reuse.

The implementation follows [`docs/70-native-ios-parity-contract.md`](../docs/70-native-ios-parity-contract.md). Delivery evidence and remaining external gates are in [`docs/71-native-ios-delivery.md`](../docs/71-native-ios-delivery.md).

## Toolchain and identity

- XcodeGen `2.46.0`.
- Latest stable Xcode on the `macos-15` CI runner; project compatibility baseline Swift `5.9`.
- Firebase iOS SDK `12.17.0` and GRDB `6.29.3`, pinned by SwiftPM.
- iOS deployment target `16.0`.
- Bundle identifier `com.rocketflow.companion.ios`.
- Version `0.1.0` (`CURRENT_PROJECT_VERSION = 1`).
- `DEVELOPMENT_TEAM` is intentionally blank in the repository.
- `aps-environment` is `development`; device signing/provisioning is not supplied by the repository.

## Clone, generate, and build on Mac

Install Xcode and the official XcodeGen `2.46.0` release, then:

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
xcodebuild test \
  -project RocketFlow.xcodeproj \
  -scheme RocketFlow-CI \
  -destination 'platform=iOS Simulator,name=<available iPhone simulator>' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

The commands above use the latest branch state, including newer documentation or code. To reproduce the canonical CI evidence exactly, replace the branch checkout with:

```bash
git checkout --detach 35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3
```

For ordinary development, open `ios/RocketFlow.xcodeproj` after generation/package resolution and select an available simulator. The committed project is usable directly, but regeneration is the parity check after source or `project.yml` changes.

## Verification evidence

Manual [iOS Verify run 32655691351](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32655691351), job `97233929959`, passed at canonical app-code/build SHA `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`:

- XcodeGen generation and committed-project parity;
- Swift package resolution and committed lock parity;
- no-sign simulator build;
- `540/540` unit tests and `2/2` UI tests (`542` total);
- xcresult artifact `9497494137`;
- generated xcodeproj artifact `9497494432`.

On candidate branch `codex/native-ios-companion`, verification is manual for feature-branch pushes and automatic only for pull requests targeting `master` and pushes to `master`. Commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` and `ios-verify` are not yet present on `origin/master` at `7d1ac74cf8f2bf7935c2578f3675db4ca54764bb`; this becomes default-branch behavior only after merge.

## API configuration and HTTPS limit

Debug and Release currently use the explicitly configured production-compatible API URL:

```text
http://45.10.110.42/rocket-api
```

For a machine-local override, copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig` and set `ROCKETFLOW_API_BASE_URL`. The app treats a missing or invalid explicit URL as startup configuration failure; there is no implicit production fallback.

The current endpoint is HTTP. `Info.plist` contains a temporary host-scoped ATS exception, not `NSAllowsArbitraryLoads`. This is acceptable only for the current personal/internal build. Production HTTPS and removal of the exception are required before App Store or public-release readiness can be claimed.

## Device signing and push prerequisites

Simulator builds require no signing. A personal-device build requires the developer to select an Apple Team, use a unique/provisioned bundle identifier if necessary, and provision the development push entitlement.

Push also requires all of the following external inputs:

- an ignored, machine-local `GoogleService-Info.plist` matching the selected bundle/application;
- Firebase project configuration plus APNs key/certificate and valid Apple provisioning;
- an FCM registration token from Firebase Messaging, never a raw APNs token at the RocketFlow API boundary;
- deployment of the candidate backend/Flyway V22 iOS device-registration support.

Production is still backend source `50a63270ae094fe08ee57b945be0930cb1115dfe` at Flyway V21. V22 exists only in candidate source and was not deployed or inspected during the iOS documentation checkpoint, so production iOS push must not be claimed.

## Readiness statement

Status is **GO** for clone, XcodeGen parity, package resolution, simulator build/test, and continued Mac development. It is not an App Store production-readiness claim. Device signing, real APNs/FCM delivery, production HTTPS, V22 deployment, and manual device accessibility/Dynamic Type evidence remain external release gates.
