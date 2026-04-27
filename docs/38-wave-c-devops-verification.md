# Wave C DevOps Verification

## Scope

This companion DevOps note defines the minimum verification surface for the current Wave C work:

- web advanced routes
- Android auth/session baseline

It is intentionally narrower than a full release document and exists to keep Wave C from moving ahead without explicit delivery gates.

## Web Delivery Checks

- `web/` keeps a passing production build with `npm run build`
- `web/` now also has a dedicated GitHub Actions build-only lane in `.github/workflows/web-verify.yml`
- no new route depends on undocumented runtime configuration
- backend API base URL behavior remains explicit and stable for local/staging use

## Android Delivery Checks

- `android/` now includes Gradle wrapper files and should build through `.\gradlew.bat`
- Android build readiness depends on:
  - installed Android SDK
  - `sdk.dir` in `android/local.properties` or `ANDROID_HOME` / `ANDROID_SDK_ROOT`
  - JDK compatible with the configured Android Gradle Plugin
- Android now also has a dedicated GitHub Actions build-only `assembleDebug` lane in `.github/workflows/android-verify.yml`
- emulator/local development still defaults to:
  - `http://10.0.2.2:8080/api`
- Android API base URL can now be overridden without code edits through:
  - Gradle property `rocketflowApiBaseUrl`
  - env var `ROCKETFLOW_ANDROID_API_BASE_URL`

## Immediate Environment Expectations

### Required For Android

- Android SDK Platform 34
- Android SDK Build-Tools
- Android Platform-Tools
- Command-line Tools

### Required For Existing Backend/Web Flows

- backend local runtime remains single-instance for current scheduler assumptions
- staging secret handling from Wave B remains the basis for notification and future mobile rollout
- backend CORS/origin handling is now an explicit runtime contract through `ROCKETFLOW_ALLOWED_ORIGINS`

## Verification Commands

Web:

- `npm run build`

Android:

- `.\gradlew.bat assembleDebug`

Backend:

- `mvn test`

Optional follow-up once SDK is present:

- `.\gradlew.bat tasks`
- `.\gradlew.bat test`

## Risk Notes

- web and Android CI lanes are build-only gates, not runtime or release certification
- Android is now CI-lane-ready at the build level, but still not runtime-notification-ready
- notification-path release confidence still depends on later Android push and staging credential work
- Wave C is not release-ready merely because backend tests, web build, and Android build are green
- runtime notification delivery still depends on real provider credentials, sender implementation, and staging validation

## Suggested Next DevOps Follow-Up

After the current Wave C stabilization:

1. document Android SDK setup and local build prerequisites in more operational detail if onboarding pain continues
2. strengthen build-only lanes with additional lint/test coverage when the runtime path stabilizes
3. add notification-path staging verification once push wiring begins
