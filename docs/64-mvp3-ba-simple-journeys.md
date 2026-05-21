# MVP3 BA simple journeys

Date: 2026-05-20

Status: BA journey contract for MVP3 simplified planning flows. This document complements `docs/62-mvp3-design-simplification-contract.md` and preserves `docs/61-mvp2-hierarchy-links-contract.md`.

## Scope

These journeys define the user-visible acceptance path for web/iPhone and Android.

The journeys are written for a Russian-first MVP3 experience:
- primary action is task capture;
- structure is available when needed;
- advanced features are not removed, only moved behind clearer entry points;
- MVP2 constraints remain binding.

## Global Acceptance Rules

- RU mode is default for RU QA seeds.
- A journey may expose advanced controls only after the user opens the relevant row, sheet, overflow, or picker.
- Every journey must work on web/iPhone and Android with platform-native visual treatment.
- Every write action must respect permissions and optimistic/concurrent version rules from the implementation contract.
- Every screen must avoid private leaks through links, dependencies, sharing previews, search, picker rows, breadcrumbs, and counters.
- Every mobile flow must have a non-DnD fallback where drag is available.

## Journey 1. New User Empty State

User goal: understand the first useful action.

Preconditions:
- user is logged in;
- account has no folders, goals, tasks, ideas, or notes visible in the planning surface.

Happy path:
1. User opens Plan/Today.
2. User sees `Пока пусто`.
3. User sees `Добавьте первую задачу.`
4. User sees primary CTA `+ Задача`.
5. User can open secondary add menu if they need `Папка`, `Цель`, `Идея`, or `Заметка`.

Acceptance rules:
- No hierarchy lecture is shown in the empty body.
- `New folder` is not the first or only CTA.
- CTA is reachable without scrolling on iPhone mobile viewport and Android.
- If user taps `+ Задача` and no goal exists, the task sheet asks for goal creation/selection without leaving the flow.

Required evidence:
- iPhone/web screenshot of empty state.
- Android screenshot of empty state.
- Screenshot of no-goal parent resolver.

## Journey 2. Create Task

User goal: capture a task quickly.

Preconditions:
- user has create permission in the current context or sees a clear no-permission state.

Happy path:
1. User taps `+ Задача`.
2. Title input is focused with placeholder `Новая задача`.
3. Parent row shows resolved `Цель` or `Выберите цель`.
4. User enters title.
5. If parent is unresolved, user chooses or creates a goal.
6. User saves.
7. New task appears in the list and can be opened.

Acceptance rules:
- One-tap capture starts a task, not an entity-type picker.
- Task is never saved without a goal parent.
- On goal detail, the current goal is used automatically.
- On folder/root, resolver follows `docs/62-mvp3-design-simplification-contract.md`.
- Advanced picker still exists and includes `Задача`, `Цель`, `Папка`, `Идея`, `Заметка`.
- Read-only users cannot create local-looking saved tasks; they see `Нет доступа на создание`.

Required evidence:
- capture sheet/input screenshot;
- saved task row screenshot;
- parent resolver screenshot for ambiguous parent;
- permission-disabled screenshot or test note.

## Journey 3. Organize Into Folder/Goal

User goal: add structure after capture or during planning.

Preconditions:
- user has at least one task or is in a place where they can create structure.

Happy path:
1. User opens advanced add menu or folder detail Add.
2. User creates `Папка` or `Цель`.
3. User moves or creates tasks under the chosen goal.
4. User sees compact hierarchy rows.

Acceptance rules:
- Folder creation remains possible, but it is secondary to task capture.
- Goal creation remains possible from folder context.
- Task creation from folder context resolves a goal.
- Compact rows use three zones: icon/expand, title, one meta slot.
- No row repeats `Полный доступ` for every descendant.
- Nested folders remain supported, but visual depth is controlled.
- Folder is never offered as a link target or dependency participant.

Required evidence:
- advanced add menu screenshot;
- folder/goal creation screenshot;
- compact hierarchy screenshot at iPhone width and Android.

## Journey 4. Open And Edit Task

User goal: understand a task, then edit only when needed.

Preconditions:
- at least one task exists and is visible to the user.

Happy path:
1. User opens a task.
2. User sees summary-first detail: title, status, priority if set, timing if set, goal/path, note preview if any, blocker summary if any.
3. User taps `Изменить`.
4. Editable fields appear.
5. User changes title/notes/priority/status/timing as supported.
6. User saves or cancels.

Acceptance rules:
- View mode does not show `Title` or `Notes` as inputs.
- Title is not duplicated in header and body in a confusing way.
- Empty advanced sections are hidden or compact.
- `Доступ`, `Связи`, `Заметки`, `Повтор`, move/clone/archive remain reachable as rows or overflow.
- Save/cancel are reachable on iPhone and Android.
- Archive/destructive action is not presented as a primary peer of save.

Required evidence:
- task detail view screenshot;
- edit mode screenshot;
- cancel/save behavior test note;
- screenshot showing advanced rows still reachable.

## Journey 5. Link Or Dependency

User goal: connect work and understand blockers.

Preconditions:
- user can access at least two linkable entities;
- for dependency path, both entities are tasks.

Happy path for related link:
1. User opens `Связи`.
2. User chooses an accessible goal/task/idea/note target.
3. User creates `Связано`.
4. Detail shows compact link row.

Happy path for dependency:
1. User opens `Связи` on a task.
2. User chooses another accessible task.
3. User selects `Связать как зависимость`.
4. Current task detail shows `Ждет: <task>` or `Блокирует: <task>` according to direction.
5. Opening the other task shows the opposite direction.

Acceptance rules:
- Folder is not present in the link picker.
- Dependency option appears only for task-to-task.
- Direction is visible and tested from both sides.
- Related links are visually secondary to blockers.
- Inaccessible targets display only `Недоступный объект`.
- Closing a task blocked by incomplete dependency still fails per MVP2 rules.

Required evidence:
- related link picker screenshot without folders;
- dependency creation screenshot;
- two task details showing opposite direction;
- blocked-close rejection evidence;
- private redaction evidence.

## Journey 6. Note

User goal: write or open supporting notes without confusing notes with task body.

Preconditions:
- user is in a folder or entity detail that can show/create/link notes.

Happy path:
1. User creates `Заметка` from advanced add menu in a folder.
2. User opens note detail and edits title/body.
3. User links the note to a goal/task/idea.
4. Linked entity detail shows compact row `Заметки 1`.
5. User opens the linked note from the row.

Acceptance rules:
- `Заметка задачи` or task note/body is distinct from `Связанные заметки`.
- Linked notes section is hidden when count is zero.
- Linked notes are compact when count is greater than zero.
- Legacy `folder_notes`, `Folder note`, `List`, `Заметка папки`, `Список` do not appear.
- Notes are not dependency endpoints.

Required evidence:
- note creation screenshot;
- linked note row screenshot;
- linked note open screenshot;
- localization audit note for banned legacy labels.

## Journey 7. Share And Revoke

User goal: invite someone or remove access without seeing an admin form all the time.

Preconditions:
- user owns or has permission to manage access for the selected entity;
- second test account exists for QA.

Happy path:
1. User opens entity detail.
2. User sees access row: `Доступ: Личный`, `Доступ: Общий`, or `Доступ: Полный`.
3. User opens the row.
4. Share sheet appears with `Email`, `Просмотр` / `Полный`, invite list, and revoke actions.
5. User enters valid email and sends invite.
6. Collaborator receives expected access.
7. Owner revokes access.
8. Collaborator loses access on next request/refresh.

Acceptance rules:
- Inline share form is not visible in detail before user opens `Доступ`.
- Invite action is not enabled for invalid email.
- `Полный доступ` is explicit.
- Revoke is visible in the sheet.
- Sharing does not expose private linked entities.
- Folder/goal/task inheritance and full-access behavior follow MVP2.

Required evidence:
- detail access row screenshot;
- share sheet before valid email screenshot;
- invite created screenshot;
- revoke screenshot;
- collaborator after-revoke evidence;
- private linked entity redaction evidence.

## Journey 8. Mobile DnD And Fallback Move

User goal: reorganize items by drag or by explicit move.

Preconditions:
- hierarchy contains at least one folder, goal, task, idea, and note where possible;
- user has move permission for valid examples.

Happy path:
1. User drags a task over goals.
2. Valid goal targets highlight.
3. User drops task on a goal.
4. Task moves and detail/list path updates.
5. User can perform the same move through overflow `Переместить`.

Invalid path:
1. User drags task over folder.
2. Folder is not presented as a valid target.
3. Drop is rejected.
4. Feedback says `Задачу можно перенести только в цель.`
5. No pending local change is created.

Acceptance rules:
- Valid matrix:
  - folder -> folder;
  - goal -> folder;
  - task -> goal;
  - idea -> folder;
  - note -> folder.
- Invalid feedback uses rule-specific copy from `docs/62-mvp3-design-simplification-contract.md`.
- Android snackbar/toast and web/iPhone feedback are short and do not occupy the main screen permanently.
- Fallback move uses the same rules as DnD.
- No cross-owner or inaccessible target move is allowed.

Required evidence:
- valid DnD screenshot or video note;
- invalid DnD screenshot;
- fallback move screenshot;
- assertion or report note that invalid drop created no data change.

## Journey 9. Settings/Profile/Logout

User goal: change preferences or leave the app without settings competing with planning.

Preconditions:
- user is logged in.

Happy path:
1. User opens profile/menu.
2. User sees `Настройки`, `Язык`, and `Выйти`.
3. User changes language.
4. UI updates and preference persists.
5. User logs out.

Acceptance rules:
- Settings, language, and logout are not primary bottom-nav peers of planning actions.
- RU settings copy is concise.
- Debug/version details are not in the main top area.
- Language switch remains available and synchronized with EN copy.
- Logout is explicit and reachable.

Required evidence:
- mobile navigation/profile screenshot;
- settings screenshot;
- language switch evidence;
- logout evidence.

## Cross-Journey QA Checklist

QA must reject MVP3 simplification if any of these occur:

- Empty state teaches the full hierarchy instead of starting with `+ Задача`.
- Task can be saved without a goal parent.
- Advanced picker disappears entirely.
- Folder appears as link target.
- Dependency can be created with any non-task endpoint.
- Inaccessible linked entity reveals title, path, or type-specific private detail.
- Detail view shows large edit inputs before `Изменить`.
- Share form is permanently embedded in task/folder/goal detail.
- DnD invalid drop changes local or backend data.
- RU mode leaks English labels from the glossary for new MVP3 surfaces.

## Open Items For Implementers

The product contract intentionally leaves these implementation choices open:

- Whether quick capture is inline, bottom sheet, or modal per platform.
- Whether parent resolver defaults to last used goal or current route selection when both are available. The chosen rule must be deterministic and documented in QA notes.
- Whether share sheet is full-screen on small Android devices or a bottom sheet. It must still hide the form until `Доступ` is opened.
- Whether deep hierarchy uses breadcrumb, collapsed indentation, or a focused subtree view. It must still avoid overloaded rows.
