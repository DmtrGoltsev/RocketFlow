# MVP3 critical QA model

Date: 2026-05-20  
Owner: MVP3 Critical QA Lead  
Status: test model only; no tests executed in this task.

Primary inputs:
- `docs/62-mvp3-design-simplification-contract.md`
- `docs/64-mvp3-ba-simple-journeys.md`
- `test-artifacts/2026-05-19/design-review/lead-designer-critical-proposals.md`
- `docs/61-mvp2-hierarchy-links-contract.md`
- MVP2 gate closure reports under `test-artifacts/2026-05-18/**` and `test-artifacts/2026-05-19/**`

Artifact package:
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/README.md`
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/acceptance-matrix.md`
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/device-evidence-requirements.md`
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/screenshot-checklist.md`
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/severity-rules-and-risks.md`
- `test-artifacts/2026-05-20/mvp3-design-simplification/qa-model/execution-runsheet.md`

## QA Position

MVP3 can pass only if it makes RocketFlow visibly simpler without weakening any MVP2 data, sharing, link, dependency, move, auth, localization, or privacy invariant.

QA must fail closed. A flow is not accepted because it "probably still works"; it is accepted only with device evidence, two-user evidence where relevant, and screenshots proving that the simplified UI did not hide a broken permission or data rule.

No implementation source was changed while creating this model.

## Non-Negotiable Release Gates

These conditions block MVP3 release even if the UI looks simpler:

- A task can be saved without a valid goal parent.
- Empty state starts with folder/hierarchy education instead of `+ Задача`.
- Folder appears as a link target in any picker, shortcut, search result, compact row action, or API-backed UI list.
- Dependency can be created with folder, goal, idea, or note as either endpoint.
- Dependency direction is ambiguous, reversed, or not verified from both task sides.
- Private or inaccessible linked/shared entities reveal title, path, folder, goal, note body/title, owner/collaborator email, type-specific detail, or structure-inference counts.
- Read/status-only collaborator can edit title, description, priority, due/planned fields, links, dependencies, sharing, move, clone, archive, or create descendants beyond the explicitly allowed legacy status-only surface.
- Full-access collaborator cannot perform the documented full-access actions inside the shared subtree, or newly created descendants get the wrong owner semantics.
- Logout leaves protected data visible after refresh/back navigation, cache restore, or Android process restart.
- RU MVP3 primary surfaces leak English labels from the MVP3 glossary.
- Invalid DnD or fallback move mutates local or backend data.
- Android keeps the old overloaded model while web/iPhone is simplified.

## Scope

In scope:
- web/iPhone mobile QA, including 390 px and 430 px widths;
- Android native QA;
- two-user sharing, redaction, and permission semantics;
- quick capture, empty state, compact hierarchy rows, detail view/edit mode, sharing sheet, links, dependencies, notes, ideas, DnD, fallback move, settings/profile/logout;
- security/auth/cache/privacy regressions that can be triggered through MVP3 flows.

Out of scope for this model:
- changing production source;
- staging or committing;
- accepting a backend or client contract change without updating MVP2/MVP3 docs;
- treating screenshots as a substitute for API/state evidence on permission, move, link, dependency, logout, or privacy cases.

## Required Test Data

QA must seed or create the following accounts and objects before final execution:

| Name | Purpose |
| --- | --- |
| Owner A | Owns primary hierarchy, links, dependencies, notes, ideas, and shares. |
| Full-access collaborator B | Receives `Полный доступ`; must create/edit/move/clone descendants inside shared subtree without becoming owner. |
| Status-only/read collaborator C | Receives non-full access; must be limited to documented read/status-only behavior. |
| Outsider D | Has no access; used for private redaction, direct URL/API attempts, cache/logout checks. |
| Empty RU account | Verifies first-run empty state and no-goal quick capture. |

Minimum object graph:
- empty root with no visible entities;
- root with no recent goal;
- root with a recent accessible goal;
- folder with exactly one active goal;
- folder with multiple active goals;
- folder with no active goals;
- shared subtree with full access;
- shared/read-only subtree without create rights;
- two tasks with dependency A waits for B and reverse view B blocks A;
- at least one goal, task, idea, and note available for related links;
- one private linked entity visible only to Owner A;
- long RU titles, long mixed-language seed titles, and narrow mobile rows;
- archived/inactive goal where parent resolution must not silently choose an invalid parent.

## Critical Coverage Model

### 1. Simplicity And Readability

Acceptance target:
- a new RU user can create a first task without reading the hierarchy model;
- every primary screen has one dominant action;
- advanced features remain available but are not presented as the default task capture path.

Required checks:
- empty state shows one heading `Пока пусто`, one sentence `Добавьте первую задачу.`, and one primary CTA `+ Задача`;
- empty state does not list `Папка`, `Цель`, `Идея`, `Заметка` in the body;
- first tap on primary add starts task capture, not entity-type selection;
- title input is focused and uses `Новая задача`;
- advanced picker remains reachable through secondary action and has the RU order `Задача`, `Цель`, `Папка`, `Идея`, `Заметка`;
- no screen uses long hierarchy instructions as the first-run explanation.

Fail conditions:
- P0 if empty state or primary add prevents the first task journey;
- P0 if quick capture can create an orphan task;
- P1 if advanced picker disappears or its route is not discoverable;
- P1 if the flow works but requires avoidable scroll on iPhone 390 or Android small width.

### 2. Parent Resolution And No Orphan Task

Every task creation path must resolve a valid goal parent before save. This is a data integrity gate, not a UX preference.

QA must cover:
- goal detail creates inside current goal;
- task detail defaults to the current task goal and lets user change it through secondary parent row;
- folder with one active goal resolves automatically and shows `Цель`;
- folder with multiple active goals blocks save until `Выберите цель` is resolved;
- folder with no active goals offers `Сначала создайте цель` and then saves under the created goal;
- root/Plan/Today with recent goal defaults deterministically and allows parent change;
- root/Plan/Today with no goal asks for goal creation/selection in the same flow;
- shared full-access subtree uses nearest valid accessible goal or asks within allowed subtree;
- read-only/shared without create rights disables save and shows `Нет доступа на создание`.

Evidence must include screenshots plus state/API proof that saved task has a non-null goal id and no orphan record exists.

### 3. Mobile Row Density And No Overflow

Web/iPhone and Android rows must use the same three-zone model:
- expand/icon zone;
- title block;
- one compact meta slot.

QA must reject rows that pass `scrollWidth` but remain unreadable. The screenshot is authoritative for readability.

Required device checks:
- iPhone width 390;
- iPhone width 430;
- Android small device/emulator;
- Android medium/common device/emulator.

Assertions:
- no row shows more than title plus one meta text fragment;
- `Полный доступ` is not repeated on every child row;
- type label is hidden when icon already communicates the type;
- folders/goals may show useful counters; tasks must not show empty counters/noisy metadata;
- long titles wrap or truncate without colliding with access labels, counters, checkboxes, drag handles, or bottom nav;
- bottom nav and FAB do not cover row meta, snackbar, invalid DnD feedback, or primary actions;
- visual nesting lines are limited to two visible levels or replaced by breadcrumb/collapsed context.

### 4. Detail Summary-First And Edit Mode

Task detail view mode is accepted only if the first viewport answers: what is this task, what is its state, where does it belong, and is it blocked?

View mode must show:
- title once;
- status/checkbox;
- priority only if set;
- due/planned/recurrence summary only if set;
- parent path or goal context;
- note/body preview only if non-empty;
- blocker/link summary only if non-empty;
- compact access row where relevant.

View mode must not show:
- `Title` input;
- `Notes` textarea;
- large always-open `Details`;
- permanent sharing form;
- `Creator` as main content;
- empty advanced sections as large blank blocks.

Edit mode must be explicit:
- only after `Изменить`;
- `Отмена` restores previous values;
- `Сохранить` is enabled only for valid changes;
- destructive actions are overflow/lower secondary actions;
- save/cancel remain reachable above browser/system bars on iPhone and Android.

### 5. Sharing Sheet And Access Semantics

Sharing must be an access surface, not a permanent form in every detail screen.

Detail acceptance:
- one row: `Доступ: Личный`, `Доступ: Общий`, or `Доступ: Полный`;
- row opens the share sheet;
- no inline email input before the sheet is opened;
- permission state is visible without leaking unrelated private linked entities.

Sheet acceptance:
- `Email` input;
- segmented permission choice `Просмотр` / `Полный`;
- invite/send disabled until valid email;
- existing invite/access list;
- explicit `Отозвать`;
- state clears after revoke.

Permission semantics:
- Owner has full access to owned entities.
- Full-access collaborator can create/edit/archive/move/clone descendants inside shared subtree and create links/dependencies only when they have access to both sides and full access on the source side.
- Full-access collaborator does not become owner; descendants created in shared subtree inherit the shared root owner semantics from MVP2.
- Status-only/read collaborator cannot full-edit. Any title/body/priority/time/link/dependency/share/move/clone/archive mutation by non-full access is P0 unless explicitly documented in MVP2 as allowed.
- Sharing a visible entity does not grant access to unrelated private linked entities.

### 6. Links, Dependencies, And Redaction

Links:
- section label is `Связи`;
- folder never appears as link target;
- accessible links use compact rows with icon, title, type only if useful, and remove action only when allowed;
- path is secondary and only shown for accessible entities when it helps distinguish them;
- inaccessible link displays only `Недоступный объект`.

Dependencies:
- creation is task-to-task only;
- wording is `Ждет задачу`, `Блокирует задачу`, `Связать как зависимость`;
- detail direction is verified from both task sides: `Ждет: <task>` and `Блокирует: <task>`;
- inaccessible dependency target displays only `Недоступный объект`;
- closing blocked task remains rejected until active blockers are done;
- dependency cycles are rejected.

Redaction is P0 privacy. Forbidden text includes title, path, folder name, goal name, note body/title, owner/collaborator email, type-specific unavailable phrase, and counts that reveal private structure.

### 7. Notes, Ideas, And Tasks Differentiation

QA must prevent the simplified design from reintroducing old vocabulary or mixing concepts.

Assertions:
- `Заметка задачи` means task body/description;
- `Связанные заметки` means separate note entities linked to task/goal/idea;
- linked notes section is hidden when count is zero;
- linked notes appear as compact `Заметки N` row when count is greater than zero;
- note entities can be linked but cannot be dependency endpoints;
- ideas can be linked but cannot be dependency endpoints;
- tasks are the only dependency endpoints;
- legacy `folder_notes`, `Folder note`, `List`, `Заметка папки`, and `Список` do not appear in UI/API-visible copy.

### 8. DnD, Valid/Invalid Targets, And Fallback Move

Valid move matrix:
- folder -> folder;
- goal -> folder;
- task -> goal;
- idea -> folder;
- note -> folder.

Invalid examples:
- task -> folder;
- goal -> goal;
- folder -> goal;
- idea/note -> goal;
- any move into inaccessible target;
- folder into itself or descendant;
- cross-owner move unless a future backend contract explicitly allows ownership re-parenting.

Required behavior:
- valid targets are visually highlighted during drag;
- invalid targets are visually rejected or de-emphasized;
- invalid drop does not create pending local changes;
- invalid feedback uses rule-specific copy;
- Android snackbar/toast and web/iPhone feedback are short and not persistent banners;
- overflow `Переместить` uses the same rules and endpoints as DnD.

Invalid DnD data mutation is P0. Missing visual feedback with state preserved is at least P1 until real-device evidence proves users can understand the rejection.

### 9. Android Parity

Android may use native controls, but it cannot lag behind the MVP3 information architecture.

Android must prove:
- RU-first copy parity;
- primary task capture;
- no orphan task;
- summary-first detail;
- edit mode exposes inputs only after edit;
- compact rows;
- access row plus share sheet;
- full-access vs status-only semantics;
- links/dependencies wording and task-only dependency;
- `Недоступный объект` redaction;
- notes/ideas/tasks differentiation;
- valid and invalid DnD;
- fallback move;
- logout/cache/session cleanup.

If web/iPhone passes and Android keeps old detail form, inline sharing, English labels, or entity-overloaded rows, MVP3 is not done.

### 10. Security, Auth, Logout, Cache, Privacy

MVP3 simplification touches surfaces that commonly regress permissions. QA must include abuse-style checks:

- direct URL/API attempts by Outsider D against shared/private object ids;
- protected route after logout, browser back, refresh, and cache restore;
- Android logout followed by process kill/restart;
- collaborator B full-access mutation boundaries;
- collaborator C status-only mutation boundaries;
- revoked collaborator cannot use stale detail, cached list, local pending operation, DnD, fallback move, link creation, or share sheet;
- private linked entities remain redacted in list, detail, picker, share preview, dependency row, note row, breadcrumb, search, counters, and screenshots;
- invalid email invite cannot be submitted;
- sharing revoke clears visible access state;
- language switch does not reveal English fallback labels in RU mode after refresh/restart.

## Device Evidence Rules

Minimum evidence is documented in `device-evidence-requirements.md` and `screenshot-checklist.md`.

At release gate, QA must have:
- iPhone/web screenshots at 390 px and 430 px for core mobile density and overflow risks;
- Android screenshots for every matching journey;
- two-user evidence for owner, full-access collaborator, status-only/read collaborator, and outsider where relevant;
- API/state proof for no orphan task, invalid DnD no mutation, fallback move, dependencies, blocked-close rejection, sharing revoke, logout/session cleanup, and private redaction;
- localization audit output proving no banned English/RU legacy labels on MVP3 surfaces.

Missing evidence is not neutral. Missing evidence is a WARN only for P2 areas; it is P1/P0 when the missing proof covers privacy, permissions, data integrity, auth, dependencies, or no-orphan creation.

## Failure Severity Summary

Full rules live in `severity-rules-and-risks.md`.

P0 examples:
- privacy leak;
- orphan task;
- invalid data mutation;
- auth/logout leak;
- wrong sharing permission semantics;
- non-task dependency;
- folder link target;
- Android parity failure on a core MVP3 journey;
- primary RU journey blocked by English/missing copy or inaccessible CTA.

P1 examples:
- advanced feature reachable only through confusing navigation;
- compact row readable only on one iPhone width;
- edit/save controls reachable on web but hidden under Android system UI;
- fallback move missing while DnD works;
- share sheet exists but revoke is hard to find;
- screenshots incomplete for a critical device but state evidence exists.

P2 examples:
- minor copy inconsistency outside primary surfaces;
- visual polish issue that does not hide meaning, data, or actions;
- redundant metadata in desktop-only view not covered by MVP3 mobile gate.

## Definition Of Done

MVP3 QA can recommend PASS only when:
- all P0 rows in the acceptance matrix have direct evidence and no open failures;
- all P1 failures are fixed or explicitly waived by product/QA with residual risk;
- no P0 is waived without written product/security acceptance;
- iPhone 390, iPhone 430, and Android evidence proves parity;
- private redaction is proven with two-user/outsider data;
- quick capture creates no orphan tasks in every parent context;
- detail view is summary-first and edit inputs appear only in edit mode;
- sharing is access row plus sheet, with correct full-access/status-only semantics;
- links/dependencies keep MVP2 constraints;
- notes/ideas/tasks remain distinct;
- DnD and fallback move share the same valid/invalid rules;
- logout/cache/privacy regressions are explicitly checked.

## Current Critical Risks Before Execution

- MVP2 closed with waivers around iPhone network telemetry and visible settings/privacy controls; MVP3 security/cache/privacy checks must not inherit those as silent pass.
- Existing evidence shows old UI patterns: English labels, hierarchy-first empty state, inline sharing, dense mobile rows, and overloaded detail. MVP3 acceptance must require fresh screenshots, not reuse MVP2 screenshots as proof of improvement.
- Android DnD had a targeted pass, but MVP3 still needs rule-specific RU feedback, fallback move parity, and no-mutation proof under the simplified UI.
- Simplifying sharing copy can accidentally weaken `Полный доступ`; QA must verify semantics through mutations, not labels only.
- Hiding advanced controls can break discoverability of links, notes, recurrence, move, clone, archive, and entity picker; QA must require secondary access paths.
- Redaction can regress through new compact rows, breadcrumbs, pickers, counters, and share previews even if old detail rows were safe.
- RU-first localization can fail through fallback English labels after refresh, Android restart, empty state, share sheet, and error/snackbar paths.
