# Wave C DevOps Verification

## Scope

This companion DevOps note defines the minimum verification surface for the current Wave C work:

- web advanced routes
- Android auth/session baseline
- notification-path delivery prerequisites

It is intentionally narrower than a full release document and exists to keep Wave C from moving ahead without explicit delivery gates.

## Web Delivery Checks

- `web/` keeps a passing production build with `npm run build`
- `web/` has a dedicated GitHub Actions build-only lane in `.github/workflows/web-verify.yml`
- no new route depends on undocumented runtime configuration
- backend API base URL behavior remains explicit and stable for local/staging use

## Android Delivery Checks

- `android/` includes Gradle wrapper files for CI use
- the preferred local verification path in the current Windows environment is the installed Gradle distribution documented in `docs/44-android-sdk-assembledebug-verification.md`
- Android build readiness depends on:
  - installed Android SDK
  - `sdk.dir` in `android/local.properties` or `ANDROID_HOME` / `ANDROID_SDK_ROOT`
  - JDK compatible with the configured Android Gradle Plugin
- Android has a dedicated GitHub Actions build-only `assembleDebug` lane in `.github/workflows/android-verify.yml`
- emulator/local development still defaults to:
  - `http://10.0.2.2:8080/api`
- Android API base URL can be overridden without code edits through:
  - Gradle property `rocketflowApiBaseUrl`
  - env var `ROCKETFLOW_ANDROID_API_BASE_URL`
- Android push runtime additionally depends on:
  - either valid default Firebase app resources or explicit build-time Firebase values
  - Google Play services-capable device or emulator
  - Firebase project aligned with app package and backend sender credentials

## Backend Notification Delivery Checks

- backend keeps a passing `mvn test`
- notification config is bound through `rocketflow.notifications.*`
- real Firebase Admin sender code exists and activates only when FCM credentials/config are present
- fallback stub behavior remains explicit when the real sender cannot be created
- scheduler polling now takes a PostgreSQL advisory transaction lock before processing due reminders
- repo-backed backend container baseline now exists via `backend/Dockerfile`, and local `rocketflow-backend:latest` reaches `/actuator/health = UP` against a temporary `postgres:16` smoke runtime
- GitHub Actions `backend-verify` now also builds the backend image and proves `/actuator/health = UP` against a temporary `postgres:16` container runtime
- GitHub Actions `backend-image-publish` now prepares the manual GHCR publish path for `ghcr.io/<owner>/rocketflow-backend`

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

### Required For Real Push

- `ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true`
- `ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID`
- either `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON` or `ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH`
- Android Firebase config kept outside version control as appropriate, either through:
  - `android/app/google-services.json`
  - or `ROCKETFLOW_ANDROID_FIREBASE_APPLICATION_ID`, `ROCKETFLOW_ANDROID_FIREBASE_API_KEY`, `ROCKETFLOW_ANDROID_FIREBASE_PROJECT_ID`, `ROCKETFLOW_ANDROID_FIREBASE_GCM_SENDER_ID`

## Verification Commands

Web:

- `npm run build`

Android:

- preferred local verification path:
  - `C:\Gradle\gradle-9.4.1-bin\gradle-9.4.1\bin\gradle.bat assembleDebug --no-daemon`
- CI lane path:
  - `./gradlew assembleDebug --no-daemon`

Backend:

- `mvn test`
- `docker build -t rocketflow-backend .\backend`
- `powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-BackendDockerRuntimeSmoke.ps1`
- GitHub Actions manual workflow `.github/workflows/backend-image-publish.yml`

Optional follow-up once SDK is present:

- `./gradlew tasks`
- `./gradlew test`

## Risk Notes

- web and Android CI lanes are build-only gates, not runtime or release certification
- Android is CI-lane-ready at the build level, and the local notification proof is already closed, but staging notification certification is still open
- notification-path release confidence now depends on the first remote GHCR publish, staging deploy facts, real staging credentials, and deployed-environment certification, not another local proof rerun
- Wave C is not release-ready merely because backend tests, web build, and Android build are green
- scheduler safety is improved, but not yet a final horizontal-scaling story

## Suggested Next DevOps Follow-Up

After the current Wave C stabilization:

1. execute the first remote backend image publish to GHCR and confirm the resulting package/tag shape
2. wire the staging deployment/runtime facts needed for certification on top of the GHCR-backed image baseline
3. provision the environment-separated staging runtime wiring and secrets needed for certification, especially the staging API URL, allowed origins, and FCM credential path
4. run the staging notification certification path from `docs/45-notification-staging-smoke-runbook.md` once those staging facts are wired
