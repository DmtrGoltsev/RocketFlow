# RocketFlow iOS

Native SwiftUI companion for iOS 16 and newer. Branch `codex/native-ios-companion` is the living delivery branch; canonical behavior/build evidence is pinned to `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3` and run `32655691351`. Mac tooling is separately pinned to `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149` and run `32669924719`. The later docs commit B records A/run A without self-pinning; docs HEAD is never interchangeable with either evidence SHA.

`project.yml` is the XcodeGen source of truth. The generated `RocketFlow.xcodeproj` and its SwiftPM `Package.resolved` are committed so a Mac checkout can open and build immediately; CI regenerates the project and fails if it differs from the committed copy.

## Delivered application

- Three native tabs: Planner, Calendar, and Focus.
- SwiftUI feature views with MVVM/store-driven state and URLSession async networking.
- Keychain session storage and account-scoped GRDB persistence.
- Local-first planning operations, deterministic sync, conflict/retry recovery, exact Calendar range cache, and durable Focus action queue.
- Native task/folder/goal/idea/note details and editors, checklist/tags, sharing, links, local task reminders, settings, and notification/deep-link routes.
- App-wide Russian and English copy, durable process restoration, and account leases that prevent cross-account cache reuse.

The implementation follows [`docs/70-native-ios-parity-contract.md`](../docs/70-native-ios-parity-contract.md). Delivery evidence and remaining external gates are in [`docs/71-native-ios-delivery.md`](../docs/71-native-ios-delivery.md). Physical-device preparation is described for humans in [`docs/72-native-ios-mac-device-handoff.md`](../docs/72-native-ios-mac-device-handoff.md); the full copyable Mac Codex instruction is [`docs/ios-native-mac-codex-install-prompt.md`](../docs/ios-native-mac-codex-install-prompt.md).

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

The commands above use the latest branch state, including newer documentation or code. To reproduce the canonical behavior CI evidence exactly, replace the branch checkout with:

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

Separate Mac tooling evidence is manual [iOS Verify run 32669924719](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32669924719), job `97269056380`, at exact tooling SHA `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149`:

- Mac handoff contracts `174/174` PASS, `0` skipped;
- XcodeGen `2.46.0` generation, committed-project parity, package resolution and lock parity PASS;
- no-sign simulator build PASS;
- unit `540` passed / `0` failed, UI `2` passed / `0` failed, total `542` passed / `0` failed;
- `RocketFlow-xcresult`, artifact ID `9501177125`, `1,317,064` bytes;
- `RocketFlow-xcodeproj-xcodegen-2.46.0`, artifact ID `9501179599`, `25,070` bytes.

On candidate branch `codex/native-ios-companion`, verification is manual for feature-branch pushes and automatic only for pull requests targeting `master` and pushes to `master`. Commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` and `ios-verify` are not yet present on `origin/master` at `7d1ac74cf8f2bf7935c2578f3675db4ca54764bb`; this becomes default-branch behavior only after merge.

## Mac physical-device handoff

The repository handoff uses `ios/scripts/mac-preflight.sh`, `mac-verify.sh`, `mac-build-device.sh`, and `mac-install-device.sh`, plus an ignored and untracked local `Config/Device.xcconfig` copied from `Config/Device.xcconfig.example`. Tooling A identity is exactly `.github/workflows/ios-verify.yml`, `.gitignore`, `ios/Config/Device.xcconfig.example`, `ios/scripts/mac-handoff-common.sh`, those four Mac scripts, and `ios/scripts/tests/mac-handoff-tests.sh`. The workflow validation step runs shell syntax plus the expanded handoff test suite. The scripts are pinned to XcodeGen `2.46.0`; read each script's `--help` instead of assuming flags. Valid tooling A must fail closed on iPhoneOS SDK >=16, the exact API/ATS contract, config/redaction rules, and pre-install bundle/codesign/entitlements, Team/application-id, and embedded provisioning checks, with the expanded shell contract suite green in run A.

Device mode defaults to `no-push`. It supports a signed personal development install without requiring Firebase/APNs or production backend V22. Optional `push` is a separate explicit opt-in requiring a matching `GoogleService-Info.plist` outside the repository or proven ignored and untracked, Apple push provisioning and Firebase/APNs setup. V22 is not deployed, so push cannot block or redefine a successful no-push installation.

Tooling A is immutable SHA `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149`, proven by manual run `32669924719`; the final prompt records both. Docs commit B is not expected to equal A. A Mac checkout uses the latest candidate/docs, verifies A is an ancestor, and proves the tooling paths have not changed after A. No signed physical-device build/install/launch has yet been recorded; only a later redacted Mac evidence report may change that status.

## API configuration and HTTPS limit

Debug and Release currently use the explicitly configured production-compatible API URL:

```text
http://45.10.110.42/rocket-api
```

The Mac device handoff does not create or use `Config/Local.xcconfig`. Its scripts must verify this exact endpoint and the ATS structure fail closed; any endpoint/ATS change is a stop condition requiring separate security review. The app treats a missing or invalid explicit URL as startup configuration failure, with no implicit production fallback.

The current endpoint is HTTP. `Info.plist` uses a strict ATS allowlist: `NSExceptionDomains` contains only `45.10.110.42`, without subdomains; broad-load keys and additional exception domains are forbidden. This is acceptable only for the current personal/internal build. Production HTTPS and removal of the exception are required before App Store or public-release readiness can be claimed.

## Device signing and push prerequisites

Simulator builds require no signing. For a personal-device build, the Apple Account is added only through Xcode UI. The selected Team ID and unique owner-controlled bundle identifier are written only to ignored `Config/Device.xcconfig` for the scripted build, never to the tracked project. Before install, tooling must verify an iPhoneOS device app, Team/application-id alignment, embedded provisioning/device match and mode-specific signed entitlements without exposing identifiers. Default `no-push` does not require a push entitlement. These gates are not evidence of a successful physical install.

Push also requires all of the following external inputs:

- a machine-local `GoogleService-Info.plist` outside the repository or proven ignored and untracked, matching the selected bundle/application;
- Firebase project configuration plus APNs key/certificate and valid Apple provisioning;
- an FCM registration token from Firebase Messaging, never a raw APNs token at the RocketFlow API boundary;
- deployment of the candidate backend/Flyway V22 iOS device-registration support.

Production is still backend source `50a63270ae094fe08ee57b945be0930cb1115dfe` at Flyway V21. V22 exists only in candidate source and was not deployed or inspected during the iOS documentation checkpoint, so production iOS push must not be claimed.

## Readiness statement

Status is **GO** for clone, XcodeGen parity, package resolution, simulator build/test, and continued Mac development. It is not an App Store production-readiness claim. Device signing, real APNs/FCM delivery, production HTTPS, V22 deployment, and manual device accessibility/Dynamic Type evidence remain external release gates.
