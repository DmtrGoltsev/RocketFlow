# QA report 2026-05-25

Workspace: `C:\Users\style\Documents\Codex\RocketFlow`

## Findings

- P1 fixed: idea deletion is creator-only in backend, but Web and Android UI hid delete behind edit/full-access affordances. A creator with read-only/shared access could be authorized by backend but unable to delete from UI.
  - Web fixed at `web/src/features/planning/routes/TasksRoute.tsx:3366`.
  - Android fixed at `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt:1687`.

No remaining backend permission defect was found in the targeted idea review. Evidence checked:

- Creator-only idea delete: `backend/src/main/java/com/rocketflow/ideas/IdeaService.java:101`.
- Idea note edit own only: `backend/src/main/java/com/rocketflow/ideas/IdeaService.java:177` and `:286`.
- Idea note delete by idea creator: `backend/src/main/java/com/rocketflow/ideas/IdeaService.java:192` and `:290`.
- Direct idea share access through `IdeaShare`, not folder-wide content access: `backend/src/main/java/com/rocketflow/sharing/SharingAccessService.java:228`.
- Migration creates scoped `idea_shares`: `backend/src/main/resources/db/migration/V16__idea_sharing.sql:13`.
- Tests cover creator delete, note permissions, direct idea share scoping:
  - `backend/src/test/java/com/rocketflow/IdeasFolderNotesIntegrationTest.java:195`
  - `backend/src/test/java/com/rocketflow/IdeasFolderNotesIntegrationTest.java:233`
  - `backend/src/test/java/com/rocketflow/IdeasFolderNotesIntegrationTest.java:426`

## Fixes made

- Web: added a standalone idea delete action when `canDeleteSelectedIdea` is true and the edit panel is not open, so delete is independent from edit/full access.
- Android: idea detail action bar now shows delete when `canDeleteIdea(idea)` is true even if `canEditIdea(idea)` is false.

## Checks

- Backend targeted tests passed:
  - Command: `cd backend; mvn test -Dtest=*Idea*,SharingIntegrationTest`
  - Result: 13 tests, 0 failures, 0 errors, BUILD SUCCESS.
  - Log: `test-artifacts/qa-20260525-20260525-013654/logs/backend-targeted-tests-after-fix.log`
- Web build passed:
  - Command: `cd web; npm.cmd run build`
  - Result: TypeScript and Vite production build succeeded.
  - Log: `test-artifacts/qa-20260525-20260525-013654/logs/web-build-after-fix.log`
- Android unit tests and debug assemble passed:
  - Command: `cd android; $env:ANDROID_HOME='C:\Users\style\AppData\Local\Android\Sdk'; .\gradlew.bat :app:testDebugUnitTest :app:assembleDebug "-Pkotlin.incremental=false" --no-build-cache`
  - Result: BUILD SUCCESSFUL in 36s.
  - Log: `test-artifacts/qa-20260525-20260525-013654/logs/android-gradle-after-fix.log`
- Web/iPhone Playwright route-mocked screenshots passed:
  - Result: 27 screenshots, 0 recorded console errors.
  - Log: `test-artifacts/qa-20260525-20260525-013654/logs/web-screenshots.log`

## Screenshots

Directory: `test-artifacts/qa-20260525-20260525-013654/screenshots`

Index: `test-artifacts/qa-20260525-20260525-013654/web-screenshots-index.json`

Captured for desktop 1440x1000, iPhone 390x844, and iPhone 430x932:

- main long list top and bottom
- create task fullscreen
- create goal fullscreen
- goal detail Plan
- idea detail delete top
- idea detail share/delete/history actions
- reminders/status
- settings

## Remaining risks and blockers

- Android device/emulator was unavailable. `adb devices -l` returned no connected devices, so Android UI screenshots, APK install verification, and closed-app notification delivery matrix were not physically verified.
- Web screenshots used route-mocked API data to bypass auth and exercise the requested states. This is useful for layout/regression coverage, but not a substitute for a live end-to-end browser session against real backend auth.
- Existing working tree contained many pre-existing modified/untracked files. Only the Web and Android local defects listed above were intentionally fixed here; no commit or push was made.
