# Scroll Restoration and Task Priority Retirement Delivery

Last updated: 2026-08-22.

## Status boundary

This document describes the backend, web, and Android V21 delivery contract and implementation evidence. Production rollout evidence is recorded separately in `docs/69-v21-production-rollout.md`.

- Production backend and web are jointly deployed from source `50a63270ae094fe08ee57b945be0930cb1115dfe` as release `sha-50a63270ae09`, with Flyway `V21` (`21/21`).
- GitHub Actions run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905) completed successfully; authenticated API smoke passed with `0` unexpected HTTP `5xx` responses.
- Android `0.1.1` (`versionCode 2`) was rolled out by direct sideload and verified as recorded in `docs/69-v21-production-rollout.md`.

## Product contract

Task priority is retired from the product surface and business behavior:

- web and Android do not display or edit task priority;
- task validation, sorting, quick reschedule behavior, and settings do not use priority;
- priority decay settings are hidden and disabled;
- rescheduling still records its audit event, but it does not change priority and reports `priorityDecayApplied=false` while that legacy response field exists;
- the technical FCM/Android notification delivery priority remains `HIGH`; it is a transport concern and is not task priority.

Ordering is deterministic without priority:

- task lists and shared task lists: `createdAt ASC`, then `id ASC`;
- calendar tasks at the same `plannedTime`: `createdAt ASC`, then `id ASC`;
- web plan ordering: `dueTime ASC` with missing/invalid due time last, then `createdAt ASC`, then `id ASC`;
- Android local Planner tasks use scheduled tasks first by `plannedTime ASC`, then `createdAt ASC`, then `id ASC`, with missing `plannedTime` last. Its separate folder-activity ordering also ignores the task priority shadow.

Backend UUID tie-breaking uses unsigned UUID ordering so in-memory Java ordering matches PostgreSQL `uuid ASC`, including values across the signed most-significant-bit boundary.

## Compatibility window

`LEGACY_TASK_PRIORITY=5` is an opaque compatibility shadow only. Keep it until old APK and V20 application rollback support are explicitly ended.

Backend V21 behavior:

- create accepts `priority` as omitted, `null`, or any legacy value and stores/returns `5` for the new task;
- update accepts `priority` as omitted, `null`, or a legacy value and ignores it, preserving the task's stored historical value in responses;
- clone creates a new task with `5`; move-to-goal preserves the existing task's historical shadow;
- list, detail, calendar, sharing, move, and reschedule responses continue to expose the stored shadow for old clients;
- settings update accepts omitted, `null`, or malformed legacy decay-policy objects and ignores them; language and notification settings remain writable;
- settings responses keep deprecated policy objects disabled while retaining stored threshold/amount values for compatibility.

Client behavior across V20 and V21:

- web and Android use `5` when a task response omits `priority`;
- creates send `5` while V20 rollback compatibility is required;
- updates preserve and resend a fetched/local shadow so a V20 backend does not rewrite historical values;
- hidden settings policies are preserved when a client must send the V20 settings shape; V21 ignores those objects;
- historical task and policy values remain stored but have no product meaning, UI, validation, or ordering effect.

Removing the shadow fields, database columns, constraints, historical values, or client preservation code is a separate breaking change. Its gate is explicit confirmation that old APK and V20 rollback support have ended.

## Android scroll restoration

The Planner captures the first visible stable resource row (`folder`, `goal`, `task`, `idea`, or `note`) plus its pixel offset. It restores that anchor after expand/collapse, detail-return, manual or background refresh, insertion above the viewport, and Android instance-state recreation such as rotation.

Fallback order is deterministic:

1. Restore the same row at the captured pixel offset.
2. If the row disappeared or was hidden by collapse/filtering, restore the nearest surviving recorded ancestor with the same offset.
3. If no recorded hierarchy survives, restore the captured absolute scroll Y.
4. Clamp every result to `0..maxScrollY`; an empty Planner resolves to `0`.

The position is intentionally reset when the user explicitly switches top-level tabs, signs out, or planner state is cleared. It does not promise cross-account, cross-session, or arbitrary top-level navigation persistence.

## Android lifecycle and compact editing

The four runtime owners that create short-lived `PlanningLocalStore` instances now close them deterministically: planning sync, Focus sync, task-reminder delivery, and acceptance-data seeding. Unit and instrumented tests also close their owned stores. This removes the observed SQLite connection-leak warnings without changing the on-disk schema version.

Portrait task editing retains the existing `AlertDialog`. In landscape below `600dp`, where the IME previously collapsed the custom form viewport to zero height, editing uses a compact full-screen `Dialog`: a real scrollable form remains on the left, Save/Cancel remain reachable on the right, and IME plus system-bar insets are applied explicitly. Labels remain associated with fields and action targets retain the accessibility size contract.

## V21 migration and rollout

`V21__retire_task_priority.sql` changes metadata defaults only:

- `tasks.priority DEFAULT 5`;
- `task_reschedule_events.priority_before DEFAULT 5`;
- `task_reschedule_events.priority_after DEFAULT 5`;
- green/red priority-decay enabled defaults become `false`.

V21 does not update or delete rows, drop columns, remove constraints/indexes, or rewrite historical task, reschedule-event, or settings values.

Executed rollout order:

1. Preflight confirmed release `sha-910c061de4af` at Flyway `20`.
2. Manifest `rocketflow-release-manifest-sha-50a63270ae09.json` targeted Flyway `21`; the existing helper jointly promoted backend and web.
3. Post-start Flyway reached `21`, the service was active, backend/web symlinks resolved to release `sha-50a63270ae09`, and public backend/web checks returned HTTP `200`.
4. Authenticated compatibility smoke passed, including priority-shadow preservation, with `0` unexpected HTTP `5xx` responses.
5. Android `0.1.1` was installed separately with `adb install -r`; UID and `firstInstallTime` were preserved, cold launch passed, and captured crashes / ANRs were `0 / 0`.

The rollout had no duplicate deployment and used no rollback. It proceeded under a user-approved one-time waiver without a fresh backup/recovery point; this is not precedent, and a future-deploy backup/rollback task was recorded in Obsidian.

Application rollback is forward-schema rollback. The workflow starts from Flyway `>=20`, records the pre-rollback row count, and fails closed unless the target release has a readable manifest whose `flyway_history_min_rows` is a JSON integer `>=20` and `<=` that pre-count. Equality to the pre-count and lower compatible values are accepted; missing/unreadable manifests, missing fields, string/boolean values, values below 20, and values above the pre-count are rejected. The approved backend/web target is then promoted jointly, after which Flyway must remain `>=20` and not decrease from the recorded count. A V20 target declaring minimum 20 is forward-compatible with retained schema V21 because V21 keeps the old columns, wire shape, constraints, historical values, and compatible defaults. The workflow must never run Flyway migrate/undo/repair, downgrade schema, or restore a database backup; database recovery remains a separate operator-approved procedure.

Rollback contract verification passed `7/7` accepted cases and `4/4` invalid cases; YAML parsing and Bash syntax checks passed. `actionlint` and `shellcheck` were unavailable in the verification environment.

## Verification evidence

Current branch evidence:

- backend: `142/142` tests;
- web: `61/61` tests, production build PASS, dependency audit PASS;
- Android: `90/90` debug unit tests, `assembleDebug` PASS, `lintDebug` PASS with `0` errors and `34` existing warnings, `assembleDebugAndroidTest` PASS;
- backend covers V20-to-V21 no-rewrite migration, old/new wire shapes, historical-shadow preservation, disabled settings policies, no decay, and priority-free deterministic ordering;
- web covers hidden UI/settings, V20 request shadows, V21 missing-field fallback, and priority-free sorting;
- Android covers stable anchor/offset restoration and fallbacks, SQLite shadow preservation/defaulting and lifecycle ownership, hidden settings policy preservation, compact-form window policy, and priority-free ordering.

Visual/runtime evidence:

- scroll restoration: `C:\Users\style\AppData\Local\Temp\RocketFlow-QA-V21-20260821-180623\android-ui-20260821-182719\terminal-report.md`; expand/collapse, detail + Back, insert above/manual refresh, background refresh, rotation, deletion fallback to the nearest parent, and intentional top-tab reset passed;
- priority compatibility and UI absence: `C:\Users\style\AppData\Local\Temp\RocketFlow-QA-V21-20260821-180623\followup-terminal-20260821-231308`; create used canonical `5`, and editing a historical priority `2` task preserved `2` in DB/API;
- compact editor/IME: `C:\Users\style\AppData\Local\Temp\RocketFlow-Visual-QA-20260822-005335\executor-ime-followup-20260822-005854\qa-run-20260822-010539`; portrait, landscape Title, and landscape Details checks passed with the IME open.

The latest IME rerun did not repeat anchor or full logcat scenarios. The earlier dedicated anchor run remains passing, and the compact-form diff did not touch anchor restoration. Treat these as two complementary evidence sets rather than claiming one end-to-end rerun covered both.

Counts are checkpoint evidence, not permanent suite requirements. Provider FCM/Web Push certification and Play Store production release remain separate gates. Production deploy, authenticated API smoke, and direct Android sideload evidence are recorded in `docs/69-v21-production-rollout.md`.

## Recorded release evidence

V21 production delivery is supported by:

- deployed source `50a63270ae094fe08ee57b945be0930cb1115dfe` and release `sha-50a63270ae09`;
- successful workflow run [32551808905](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32551808905);
- manifest `rocketflow-release-manifest-sha-50a63270ae09.json`, artifact `9470293960`, recorded ZIP SHA-256 `54b9994e...f49e`, and passing packaged checksums;
- preflight Flyway `20`, manifest target `21`, and post-start Flyway `21`;
- joint backend/web promotion followed by separate Android sideload rollout;
- authenticated API smoke including compatibility-shadow preservation;
- no duplicate deployment and no rollback;
- current production truth in `docs/production/rocketflow-live-status.md`.
