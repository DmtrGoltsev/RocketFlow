# Calendar, Weekly Focus, and Web Push Delivery

## Status

This document is the canonical delivery and rollout reference for `codex/weekly-focus-calendar-web-push` as updated on `2026-08-10`.

- Implemented and tested in the feature working tree: backend, web, and Android Calendar/Weekly Focus; server-owned Focus cadence; Android data-only FCM handling; full browser Web Push lifecycle.
- Production backend and web are deployed from source SHA `910c061de4af9395d9bb682624bd966b2977a738` as release `sha-910c061de4af`; Flyway is at `V20` (`20/20`).
- The docs-only follow-up commit that records this state is distinct from the deployed source SHA and must not be read as a second deployment.
- Focus cadence and Web Push remain disabled. Android is not released: the recorded unsigned APK is not installable and has no Firebase configuration.
- Local and public health passed, but authenticated production smoke remains an open evidence gap.

## Product Contract

Web and Android expose the Russian-labeled Home, Calendar, and Focus navigation tabs. Calendar uses a monthly grid: deadline markers are red, planned-work markers are green, and both can appear on one day. Selecting a day lists its tasks; selecting a task opens task details. The server expands recurrence in the requesting user's timezone and returns stable occurrences.

Each user has at most one active Weekly Focus. ISO-week boundaries are calculated in the user's IANA timezone and persisted with a timezone snapshot. Progress is effort-weighted: missing or zero effort has effective weight `1`; only `done` counts as completed. Completed tasks remain through week end. Incomplete tasks are offered for explicit rollover. Prior periods remain available as history.

Accessible shared tasks may be added while access remains valid. Deleted tasks leave active Focus, archived tasks become history-only, and access loss removes shared tasks from active Focus. Optimistic versions and idempotency keys support web concurrency and Android offline rebase/retry.

## Notification Contract

Focus interval presets are off, 30 minutes, 1 hour, 2 hours, and 4 hours. Quiet hours are optional but start/end are an atomic pair. The server sends regular reminders for a non-empty, unfinished active Focus, not only for overdue work.

The server is the only cadence authority. Android must not schedule local repeating Focus alarms. It receives data-only FCM payloads with stable event ids and opens `rocketflow://focus`. Web Push opens `/rocket/app/focus` through the service worker.

Browser registration and logout are account-scoped. Logout attempts subscription deletion while authentication is still available, then revokes auth, unsubscribes the browser, and clears local state. A subscription endpoint cannot transfer across accounts. The default cap is 10 active subscriptions per user.

## Security and Reliability

- Web Push endpoints must be HTTPS on port 443, resolve outside private/special ranges, and match a configured strict allowlist of known provider suffixes. Defaults are FCM, Mozilla, Windows, and Apple push providers; wildcards are invalid.
- VAPID keys and subject are secrets/configuration, never repository data. The subject must be a valid `mailto:` or absolute HTTPS URI.
- FCM connect/read/write timeouts are configurable and validated. Provider failures are classified into retryable, stale-target, configuration, and permanent outcomes.
- A durable outbox uses stable event ids and cadence buckets, claim tokens, leases, heartbeat renewal, stale-lease recovery, bounded attempts, exponential backoff with jitter, and retry fairness. Provider I/O occurs outside database transactions.
- Expired or provider-invalid subscriptions are deactivated. Pending/in-flight delivery state suppresses duplicate work.

## Schema and API

- `V19__weekly_focus.sql`: task soft-delete timestamp, Focus periods/items/settings/idempotency.
- `V20__focus_notifications.sql`: Web Push subscriptions and Focus delivery outbox.
- Calendar: `GET /api/calendar?from=YYYY-MM-DD&toExclusive=YYYY-MM-DD`.
- Focus: `/api/focus/current`, `/api/focus/candidates`, current item add/remove/reorder, rollover resolution, history, and notification settings.
- Web Push: `/api/notifications/web-push/config` and subscription create/delete.

Detailed DTO rules live in `docs/05-api-contracts.md`; domain invariants live in `docs/03-domain-specification.md`.

## Feature-Branch Evidence

- Backend: 135 tests, including tenant-scoped candidate processing above 5,000 rows, full Flyway `V1` through `V20` and Hibernate validation, successful package.
- Web: 54 tests, production build, and `npm audit --audit-level=low` with no reported vulnerabilities at the checkpoint.
- Android: 77 unit tests, including terminal `401` handling without session resurrection, `assembleDebug`, `lintDebug`, and debug Android-test APK assembly.
- The updated client evidence includes final mobile accessibility and deep-link regression fixes.
- Web runtime QA covered desktop/tablet/mobile routes, Calendar markers and deep links, Focus progress/history/picker/settings, reload behavior, console, and network behavior. The final release gate must include a clean responsive rerun after any UI fixes.

These numbers are point-in-time evidence, not hard-coded future thresholds.

## Production Rollout Evidence

- Deploy: GitHub Actions run [31357406631](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/31357406631), conclusion `success`.
- Runtime: local and public health passed; captured post-deploy evidence found zero application errors, HTTP `5xx` responses, and service restarts.
- Database: Flyway `V20`, `20/20` migrations present.
- Backup: `rocketflow_prod_20260810T045958Z.dump`, `223191` bytes, SHA-256 `783590b8fa26f6d2882aab0a5cf670b483be5895fd80b6a915cd4c9946841b39`; `pg_restore -l` listed `238` entries and passed.
- Rollback: workflow ID `330828165` is active; it was not used.
- Android artifact: unsigned APK SHA-256 `1763de390dd587c686fe84152c521a2d92e65b747fb2689ec2076c0560c576d7`; not installable, no Firebase configuration, not deployed.
- Residual gap: authenticated production smoke was not completed. No production FCM or Web Push delivery is claimed.

The canonical immutable record is `docs/67-weekly-focus-production-rollout-evidence.md`.

## CI and Local Verification

Web requires Node `>=22.12 <23`.

```powershell
Set-Location web
npm ci
npm test
npm audit --audit-level=low
npm run build
```

```powershell
Set-Location backend
mvn --batch-mode --no-transfer-progress test
mvn --batch-mode --no-transfer-progress package -DskipTests
```

```powershell
Set-Location android
.\gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug --no-daemon
```

Do not print QA credentials, access tokens, Firebase service-account data, VAPID private keys, or subscription key material in logs or reports.

## Production Rollout

1. Confirm a database backup and rollback decision owner.
2. Build from the reviewed commit and pass backend, web, Android, dependency-audit, and documentation gates.
3. Provision production VAPID/FCM secrets out of version control. Verify allowed provider suffixes, HTTPS/443 policy, subscription cap, cadence settings, and FCM timeouts.
4. Before promotion, require the documented production source baseline of at least 18 Flyway history rows. The release manifest must require at least 20 rows; do not require that target state before the new JAR starts.
5. Promote the backend with Focus cadence and Web Push disabled. Its startup Flyway lifecycle applies `V19` and `V20`; post-deploy readiness must then require at least 20 Flyway history rows and verify Hibernate validation, health, and authentication.
6. Deploy web and APK from the same contract version. Confirm service-worker scope and Focus deep links.
7. Run authenticated Calendar/Focus CRUD, rollover/history, shared-access lifecycle, and offline Android reconciliation smoke.
8. Enable Web Push for a controlled account and prove subscribe, delivery, Focus open, logout cleanup, account switching, and stale-subscription deactivation.
9. Enable Focus cadence for controlled accounts and prove quiet hours, non-overdue regular delivery, FCM/Web Push event deduplication, retry/backoff, and outbox recovery.
10. Review provider/config/permanent failures and stale leases before broad enablement.
11. Record commit, artifact hashes, pre/post migration state, configuration owner, smoke evidence, and rollback decision in the production runbook.

## Rollback

Disable Focus cadence and Web Push first; this stops new delivery without deleting user Focus data. Roll back web/APK routing if necessary while keeping the backend API compatible. After the V20 release has run, the application rollback workflow still requires at least 20 Flyway history rows because it does not roll back the database. Prefer a forward application fix over reversing `V19`/`V20`; database rollback requires an explicit data-retention decision because periods, history, subscriptions, and delivery evidence are user/operational state.

## Release Gate

The backend/web and database rollout is complete for source SHA `910c061de4af9395d9bb682624bd966b2977a738`. Notification enablement remains blocked until real FCM and Web Push provider smoke passes with production-equivalent credentials. Android release remains blocked until an installable configured artifact and device smoke exist. Authenticated production smoke is still required; successful health checks do not close that gap.
