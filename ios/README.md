# RocketFlow iOS

Native iOS 16 companion bootstrap generated with XcodeGen. `project.yml` is the source of truth; `RocketFlow.xcodeproj` is generated and ignored until the repository explicitly decides to commit it.

## Toolchain

- XcodeGen `2.46.0`.
- Latest stable Xcode available on the CI runner, with the project compatibility baseline set to Swift `5.9`.
- GRDB `6.29.3`, pinned with Swift Package Manager. This is the latest stable GRDB 6 release compatible with the Swift 5.9 toolchain; GRDB 7.11.1 requires Swift tools 6.1.
- iOS deployment target `16.0`.
- App bundle identifier `com.rocketflow.companion.ios`.
- App version `0.1.0` (`CURRENT_PROJECT_VERSION = 1`).

## Generate and verify

On macOS with Xcode selected:

```bash
cd ios
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies \
  -project RocketFlow.xcodeproj \
  -scheme RocketFlow-CI
xcodebuild test \
  -project RocketFlow.xcodeproj \
  -scheme RocketFlow-CI \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

The repository CI selects the latest stable Xcode available on `macos-15`, prints the exact Xcode and Swift versions, installs the exact official XcodeGen release, verifies its SHA-256, generates the project, resolves packages, and runs a no-sign simulator build with both test targets. If project generation succeeds, CI uploads `RocketFlow.xcodeproj` as `RocketFlow-xcodeproj-xcodegen-2.46.0` even when a later package, build, or test step fails.

## Configuration

Debug and Release both default to the current production API:

```text
http://45.10.110.42/rocket-api
```

For a machine-local override, copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig` and change `ROCKETFLOW_API_BASE_URL`. A command-line build setting with the same name also overrides the default.

The production endpoint is HTTP. `Info.plist` therefore contains a temporary, host-scoped ATS exception for `45.10.110.42`; it does not enable arbitrary HTTP loads. Remove this waiver when the API is available over HTTPS.

The `rocketflow` URL scheme and background refresh/processing identifiers are declared for later feature work. The entitlements file is intentionally empty: push, iCloud, keychain groups, associated domains, and other capabilities must only be added together with provisioning and an implemented feature.
