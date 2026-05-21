# MVP3 design simplification contract

Date: 2026-05-20

Status: product/BA acceptance contract for MVP3 simplification. This document translates the lead designer P0/P1 findings into concrete rules for web/iPhone and Android implementation.

Primary inputs:
- `test-artifacts/2026-05-19/design-review/lead-designer-critical-proposals.md`
- `docs/61-mvp2-hierarchy-links-contract.md`

## Scope

MVP3 is a simplification layer over the MVP2 hierarchy, notes, links, dependencies, move/clone, sharing, and localization contract.

The goal is not to remove capabilities. The goal is to make the default path feel like simple planning:

1. Capture a task.
2. Put it under a clear goal when structure is needed.
3. Open the task and understand the summary first.
4. Reveal links, notes, recurrence, sharing, move/clone, and other advanced controls only on demand.

This contract applies to:
- web mobile/iPhone viewport;
- Android native UI;
- QA acceptance and screenshot review.

## MVP2 Constraints Preserved

Implementation and QA must keep these MVP2 rules unchanged:

- Folders are hierarchy containers and are not link targets.
- Dependencies are task-to-task only.
- Notes can be linked but cannot be dependencies.
- Ideas can be linked but cannot be dependencies.
- Private or inaccessible linked entities must not reveal title, path, type-specific metadata, owner, author, or folder context.
- Folder links must not be introduced in any picker, shortcut, search result, or compact row.
- Non-task dependencies must not be introduced even as disabled UI choices.
- Advanced capabilities stay available through secondary actions: entity picker, links, linked notes, recurrence, sharing, move, clone, archive, settings.
- MVP2 header contract for folder/goal detail keeps Add/Edit/Cancel behavior, but visual weight and placement may be simplified per platform.
- Legacy `folder_notes` must not return as a user-facing concept.

## Product Principle

Every screen has one primary verb.

- Empty plan: create a task.
- Folder/goal: add or organize.
- Task detail: understand or edit the task.
- Links/dependencies: explain what blocks what.
- Sharing: manage access only after the user opens access.
- Settings/profile: configure account and leave the app.

If a screen simultaneously asks the user to create, edit, share, configure recurrence, manage links, archive, move, and understand hierarchy, it fails MVP3 simplicity even if it remains functionally correct.

## Platform Parity Rules

Web/iPhone and Android do not need identical visual components, but they must share the same information architecture:

- Default language for RU users and QA seeds is Russian.
- Primary create action is `+ Задача`.
- Advanced entity picker is secondary.
- Detail screens are summary-first.
- Advanced sections are collapsed or represented as compact rows until opened.
- Sharing is an access row plus sheet, not a permanent inline form.
- Dependency direction is visible in user language.
- DnD valid and invalid targets are explained the same way.
- Settings, language, and logout live in profile/menu, not as equally weighted planning tabs.

## Quick Capture Contract

### Primary Action

The primary create action on plan/mobile surfaces is `+ Задача`.

Acceptance rules:
- Empty state primary CTA is `+ Задача`, not `New folder`, `Папка`, or a list of entity types.
- Global FAB or bottom/right `+` starts task capture first.
- A tap opens a compact inline input or bottom sheet with title field focused: placeholder `Новая задача`.
- Submitting creates a task only after a valid goal parent is resolved.
- Long press, overflow, or secondary `Еще` opens the advanced entity picker.

### Parent Resolution

Tasks still belong to goals. MVP3 must make that rule quiet but explicit.

Parent resolution order:

| Context | Default parent behavior | Required fallback |
| --- | --- | --- |
| Goal detail | Create inside the current goal. | None unless user lacks access. |
| Task detail | Default to the current task's goal. | User can change goal in secondary parent row. |
| Folder detail with exactly one active goal | Create inside that goal. | Parent row shows the goal and can be changed. |
| Folder detail with several active goals | Show compact parent resolver after title input. | User must choose a goal before save. |
| Folder detail with no active goals | Offer `Создать цель` then save task under it. | Do not create orphan tasks. |
| Root/Plan/Today with recent goal | Default to last used accessible goal. | Parent row can be changed before save. |
| Root/Plan/Today with no goal | Ask for goal creation/selection in the same sheet. | Do not teach the whole hierarchy in empty state. |
| Shared subtree with full access | Use the nearest valid accessible goal. | If no valid goal, ask to choose/create within allowed subtree. |
| Read-only/shared without create rights | Disable save and show short reason. | Do not show invalid local draft as saved. |

Required copy:
- Parent row label: `Цель`
- Missing parent state: `Выберите цель`
- No goal state: `Сначала создайте цель`
- No permission state: `Нет доступа на создание`

### Advanced Entity Picker

Advanced picker remains available but secondary.

Acceptance rules:
- Picker order in RU: `Задача`, `Цель`, `Папка`, `Идея`, `Заметка`.
- On folder detail, `Цель` and `Задача` are first; `Папка`, `Идея`, `Заметка` are below.
- On goal detail, primary Add creates or starts a task; advanced picker can still expose compatible actions.
- Picker must not show invalid operations:
  - no folder as link target;
  - no dependency option unless both endpoints are tasks;
  - no create option when permissions forbid it.

## RU-First Copy Glossary

RU is the source language for MVP3 UI review.

| Concept | RU copy | Avoid in RU mode |
| --- | --- | --- |
| Plan | `План` or `Сегодня` depending on route | `Plan` |
| Empty title | `Пока пусто` | `Nothing here yet` |
| Empty help | `Добавьте первую задачу.` | Long hierarchy explanation |
| Add task | `+ Задача` | `New folder` as first action |
| Folder | `Папка` | `Folder` |
| Goal | `Цель` | `Goal` |
| Task | `Задача` | `Task` |
| Idea | `Идея` | `Idea` |
| Note | `Заметка` | `Note` when RU mode is active |
| Links | `Связи` | `Links` |
| Related | `Связано` | `Related` |
| Waits for blocker | `Ждет` | `Dependency` badge only |
| Blocks another task | `Блокирует` | Ambiguous dependency direction |
| Access | `Доступ` | `Share` as section title |
| Private | `Личный` | `Private` |
| Shared | `Общий` | `Shared` |
| Full access | `Полный доступ` | `Full access` in RU |
| View access | `Просмотр` | `Read only` in RU |
| Edit | `Изменить` | Mixed `Edit` |
| Save | `Сохранить` | Mixed `Save` |
| Cancel/back | `Назад` or `Отмена` by context | Mixed `Cancel` |
| Email | `Email` | `User email` |
| Enabled | `Вкл.` | `Enabled` |

English can remain supported, but RU screenshots must not mix RU and EN labels except technical seed titles intentionally created by QA.

## Empty State Rules

Acceptance rules:
- Empty state has one heading, one short sentence, one primary button.
- Required RU baseline:
  - heading: `Пока пусто`
  - sentence: `Добавьте первую задачу.`
  - CTA: `+ Задача`
- Do not list `Папка`, `Цель`, `Идея`, `Заметка` in empty state body.
- Do not use a large illustration if it pushes the CTA below the first mobile viewport.
- Secondary structure actions are allowed behind `Еще`, `+` menu, or overflow.

## Detail Summary-First Contract

### View Mode

Task detail first viewport must show the task summary, not an object admin form.

Required first-screen content for task detail:
- title once;
- status/checkbox;
- priority if set;
- due/planned/recurrence summary only if set;
- parent path or goal context;
- note preview only if non-empty;
- blocker/link summary only if non-empty;
- access state as one compact row if relevant.

Collapsed/compact rows below summary:
- `Детали`
- `Связи`
- `Заметки`
- `Повтор`
- `Доступ`
- `Переместить`
- `Клонировать`
- `Архив`

Acceptance rules:
- `Title` and `Notes` inputs are not visible in view mode.
- `Creator` is not in the main content area. It may appear inside access/audit/overflow if needed.
- Empty sections are hidden or represented by one compact disabled/secondary row, never by large blank blocks.
- A user can understand what the task is and whether it is blocked before scrolling.

### Edit Mode

Edit mode is the only mode that exposes editable fields.

Acceptance rules:
- Entering `Изменить` replaces read-only summary fields with inputs.
- `Отмена` returns to previous values without partial visual save.
- `Сохранить` is enabled only when changes are valid.
- Archive/destructive actions are not large peers of `Сохранить`; they live in overflow or a lower secondary zone.
- On mobile, save/cancel remain reachable above browser or system bottom bars.
- Recurrence, reminders, links, and access can remain separate rows/sheets from edit mode; they are not removed.

## Compact Row Contract

Mobile hierarchy rows must fit 390px iPhone and common Android widths without horizontal competition.

Required row zones:
1. expand/icon zone;
2. title block;
3. one compact meta slot.

Acceptance rules:
- A row shows no more than two text fragments at once: title plus one meta.
- `Полный доступ` is not repeated on every child row. Show it only on shared root/folder or in access surface.
- Type labels are hidden when the icon already communicates type.
- Counters such as `0/2` appear only for folders/goals where they help scan children.
- Tasks do not show empty counters or noisy metadata.
- Long titles wrap or truncate without colliding with access labels, counters, drag handles, or checkboxes.
- Visual nesting lines are limited to two visible levels; deeper nesting uses breadcrumb, collapsed indentation, or parent path in detail.

Web/iPhone-specific:
- Passing `scrollWidth` checks is not enough; QA must review readable screenshots.
- Bottom nav must not compete with row content or hide primary actions.

Android-specific:
- Native row density may differ, but the same three-zone model applies.
- FAB must not cover row meta, snackbar, or invalid DnD feedback.

## Sharing Contract

Sharing is a permission surface, not a permanent detail form.

### Detail Access Row

Acceptance rules:
- Detail shows one row: `Доступ: Личный`, `Доступ: Общий`, or `Доступ: Полный`.
- The row opens the share sheet.
- No inline email input is visible until the share sheet is opened.
- Permission state is visible without exposing unrelated collaborator/private entity data.

### Share Sheet

Required contents:
- `Email` input;
- permission segmented choice: `Просмотр` / `Полный`;
- invite/send action enabled only after valid email;
- existing invite/access list;
- explicit `Отозвать` action;
- clear state after revoke.

Acceptance rules:
- `Полный доступ` remains explicit and cannot be softened into ambiguous wording.
- Revoke must be discoverable in the sheet.
- Sharing previews must not reveal private linked entities.
- Folder/goal/task sharing behavior follows MVP2 inheritance and permission rules.

## Links And Dependencies Contract

### Links

Acceptance rules:
- UI label is `Связи`.
- Link picker never shows folders as link targets.
- Related links use compact rows: icon, title if accessible, type if useful, remove action if allowed.
- Path is secondary and only shown when it helps distinguish accessible entities.
- Inaccessible related entity displays `Недоступный объект` with no title/path/type-specific detail.

### Dependencies

Acceptance rules:
- Dependency creation is available only task-to-task.
- UI wording is task-language:
  - `Ждет задачу`
  - `Блокирует задачу`
  - `Связать как зависимость`
- Detail displays direction:
  - current task waits for another task: `Ждет: <task title>`
  - current task blocks another task: `Блокирует: <task title>`
- If the other task is inaccessible, display `Недоступный объект`.
- Closing a blocked task must preserve MVP2 backend behavior: blocked closure is rejected until active blockers are done.
- QA must verify direction from both sides of the same dependency.

## Notes Contract

Acceptance rules:
- `Заметка задачи` means task body/description.
- `Связанные заметки` means separate note entities linked to goal/task/idea.
- If linked notes count is zero, hide the section in view mode.
- If linked notes count is greater than zero, show compact row `Заметки N`.
- Opening linked notes remains available from the compact row.
- Do not reintroduce legacy `folder_notes`, `Folder note`, `List`, `Заметка папки`, or `Список`.

## Private Redaction Contract

For any inaccessible linked/shared entity, UI and API display must be privacy-safe.

Allowed display:
- `Недоступный объект`
- generic unavailable icon;
- remove/unlink action only if the actor has permission on the visible side.

Forbidden display:
- title;
- path;
- folder name;
- goal name;
- note body/title;
- owner/collaborator email;
- type-specific phrase such as `Недоступная задача` if the type is not otherwise allowed to be known;
- counts that allow inference of private structure.

## DnD And Move Feedback Contract

DnD remains supported, but fallback move is required.

Valid target matrix:
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
- folder into itself or descendant.

Acceptance rules:
- During drag, valid targets are visually highlighted.
- Invalid targets are visually de-emphasized or reject on hover/drop.
- Invalid drop does not create pending local changes.
- Feedback is short and rule-specific:
  - task invalid target: `Задачу можно перенести только в цель.`
  - goal invalid target: `Цель можно перенести только в папку.`
  - folder invalid target: `Папку можно перенести только в папку.`
  - idea/note invalid target: `Можно перенести только в папку.`
  - no permission: `Нет доступа на перемещение.`
- Snackbar/toast is preferred over a large persistent banner.
- `three dots -> Move` or equivalent overflow uses the same move rules and endpoints as drag.

## Settings/Profile Contract

Acceptance rules:
- Planning bottom nav should not expose settings, language, and logout as equally weighted planning destinations.
- Settings, language, profile, and logout live behind profile/menu.
- Settings copy is concise:
  - heading: `Настройки`
  - language: `Язык`
  - logout: `Выйти`
- Debug/system details such as `Version: 0` are not shown in the main settings top area.
- Language switch remains available and persists.

## Required Evidence

Implementers and QA must provide:
- web/iPhone screenshots for empty state, quick capture, compact list, task detail view, task edit mode, share sheet, links/dependencies, invalid DnD/fallback;
- Android screenshots for the same flows;
- redaction evidence with two-user scenario;
- dependency direction evidence from both task sides;
- DnD invalid target evidence with rule-specific copy;
- localization evidence that RU mode does not leak English labels from the glossary;
- confirmation that advanced picker and advanced sections still exist.

## Definition Of Done

MVP3 simplification is accepted when:
- a new RU user can create the first task without reading hierarchy instructions;
- quick capture never creates orphan tasks and always resolves a goal parent;
- web/iPhone and Android use the same UX vocabulary and progressive disclosure model;
- task detail first viewport is summary-first and not an edit/admin form;
- compact rows do not collide or overload at mobile widths;
- sharing is opened from `Доступ`, not shown as a permanent large form;
- dependencies explain `Ждет` / `Блокирует` and remain task-to-task only;
- private linked entities are redacted;
- DnD invalid feedback states the rule and does not mutate data;
- advanced features remain reachable through secondary actions.

## Explicit Non-Goals

- No new entity model.
- No folder links.
- No goal/folder/idea/note dependencies.
- No migration back to legacy folder notes/lists.
- No removal of sharing, links, recurrence, move, clone, notes, ideas, or advanced picker.
- No privacy tradeoff for prettier previews.
- No desktop-only simplification that leaves Android behind.
