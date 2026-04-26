# Wave C DevOps Verification

## Scope

This companion DevOps note defines the minimum verification surface for the current Wave C work:

- web advanced routes
- Android auth/session baseline

It is intentionally narrower than a full release document and exists to keep Wave C from moving ahead without explicit delivery gates.

## Web Delivery Checks

- `web/` keeps a passing production build with `npm run build`
- no new route depends on undocumented runtime configuration
- backend API base URL behavior remains explicit and stable for local/staging use

## Android Delivery Checks

- `android/` now includes Gradle wrapper files and should build through `.\gradlew.bat`
- Android build readiness depends on:
  - installed Android SDK
  - `sdk.dir` in `android/local.properties` or `ANDROID_HOME` / `ANDROID_SDK_ROOT`
  - JDK compatible with the configured Android Gradle Plugin
- emulator/local development currently assumes backend access through:
  - `http://10.0.2.2:8080/api`

## Immediate Environment Expectations

### Required For Android

- Android SDK Platform 34
- Android SDK Build-Tools
- Android Platform-Tools
- Command-line Tools

### Required For Existing Backend/Web Flows

- backend local runtime remains single-instance for current scheduler assumptions
- staging secret handling from Wave B remains the basis for notification and future mobile rollout

## Verification Commands

Web:

- `npm run build`

Android:

- `.\gradlew.bat assembleDebug`

Optional follow-up once SDK is present:

- `.\gradlew.bat tasks`
- `.\gradlew.bat test`

## Risk Notes

- Android should not be treated as CI-ready until SDK provisioning and pipeline lane decisions are documented
- notification-path release confidence still depends on later Android push and staging credential work
- Wave C is not release-ready merely because web routes compile; Android environment readiness must be explicit

## Suggested Next DevOps Follow-Up

After the current Wave C stabilization:

1. document Android SDK setup and local build prerequisites in more operational detail if onboarding pain continues
2. add explicit Android pipeline lane design
3. add notification-path staging verification once push wiring begins

