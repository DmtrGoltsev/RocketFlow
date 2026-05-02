# Инструкция для перехода в новый чат

Этот документ заменяет предыдущий стартовый промпт `docs/53-next-chat-orchestrator-corrective-start-prompt.md`.
Файлы правил оркестратора были изменены, поэтому новый чат должен начинаться с их перечитывания.

## Скопировать в новый чат

Ты продолжаешь работу в репозитории:

`<repo-root>`

Сначала обязательно прочитай обновленные правила:

1. `<local-prompts-dir>\Ru_OrchestratorRules.md`
2. `<local-prompts-dir>\Ru_SubagentFirstFinishNew.md`
3. `<repo-root>\docs\54-next-chat-orchestrator-android-functional-start-prompt.md`

Работай строго как оркестратор.

Главное:

- Любая новая пользовательская задача сначала уходит планировщику/декомпозеру. Без исключений.
- Главный поток не является исполнителем, интегратором или тестировщиком.
- Главный поток управляет планом, агентами, приемкой, доказательствами и рисками.
- Не устраивать мультиагентность ради вида. По `Ru_SubagentFirstFinishNew`: один владелец и один поток по умолчанию, параллельность только когда она реально ускоряет или снижает риск.
- Перед распараллеливанием зафиксировать результат, сигнал готовности, владельца, границы, что не делаем сейчас, ограничения, stop/go/kill.
- Если несколько исполнителей меняют код или важна приемка, нужны отдельные роли интеграции и валидации.
- Не заявлять "готово" без свежих проверок и артефактов.

## Текущее состояние проекта

Последний завершенный этап: функциональная Android-интеграция и runtime recovery.

Последний важный отчет:

`<repo-root>\tmp\agent-reports\android-integration-runtime.md`

Статус последнего этапа по отчету:

- Backend был поднят из текущего исходного кода.
- Host/web API: `http://127.0.0.1:18082/api`
- Android API: `http://10.0.2.2:18082/api`
- Temp PostgreSQL 18: `127.0.0.1:55432`, DB `rocketflow_smoke`
- Pixel 7 подтвержден: `emulator-5554`, AVD `Pixel_7`
- Android connected e2e прошел на Pixel 7.
- Gradle gate прошел.
- Backend API smoke прошел.

Важные проверки из последнего отчета:

- `GET /api/health` -> 200
- `POST /api/auth/register` -> 201
- `POST /api/auth/login` -> 200
- `GET /api/folders` с auth работает
- Folder/goal/task sharing by email, userId, link проверены API smoke
- Link resolve/accept работает
- Shared resources возвращает folder/goal/task
- `.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest -ProcketflowApiBaseUrl=http://10.0.2.2:18082/api` PASS
- `.\gradlew.bat :app:connectedDebugAndroidTest -ProcketflowApiBaseUrl=http://10.0.2.2:18082/api` PASS

Android screenshots последнего runtime smoke:

`<repo-root>\tmp\agent-reports\android-integration-runtime\`

В папке есть скриншоты:

- `01-ru-auth.png`
- `02-planner.png`
- `04-task-detail.png`
- `05-task-metadata.png`
- `06-edit-task-dialog.png`
- `07-tags-dialog.png`
- `08-recurrence-dialog.png`
- `09-reminders-dialog.png`
- `10-quick-reschedule-dialog.png`
- `11-task-sharing-dialog.png`
- `12-settings-diagnostics.png`
- `13-priority-decay-dialog.png`
- `14-accept-link-dialog.png`
- `15-folder-sharing-dialog.png`
- `16-goal-sharing-dialog.png`

## Что было сделано

Backend sharing/API:

- Добавлен sharing для folder/goal/task по email, `userId`, authenticated link.
- Основные endpoints:
  - `POST /api/folders/{folderId}/share`
  - `POST|GET /api/folders/{folderId}/share-links`
  - `POST|GET /api/goals/{goalId}/share-links`
  - `POST|GET /api/tasks/{taskId}/share-links`
  - `GET /api/shares/links/{token}`
  - `POST /api/shares/links/{token}/accept`
  - `POST /api/shares/links/{linkId}/revoke`
- `mvn --batch-mode --no-transfer-progress -Dtest=SharingIntegrationTest test` PASS.
- `mvn --batch-mode --no-transfer-progress test` PASS, 36 tests.
- Отчет: `tmp/agent-reports/backend-sharing-api.md`

Android:

- RU/EN локализация добавлена как базовое поведение: русский по умолчанию, есть переключение на английский.
- Исправлен RU mojibake.
- Добавлены priority, planned, due в create/edit task flow.
- Добавлены native date/time picker controls.
- Добавлены `/me/settings` client и UI для priority decay.
- Добавлен quick reschedule через `/tasks/{taskId}/reschedule`.
- Добавлены tags, recurrence, per-task reminders.
- Добавлена Android sharing UI/client:
  - folder/goal/task share;
  - email/userId/link options;
  - create/list/revoke link;
  - accept link input в settings;
  - task detail share icon.
- Отчеты:
  - `tmp/agent-reports/android-localization-priority-scheduling.md`
  - `tmp/agent-reports/android-task-metadata.md`
  - `tmp/agent-reports/android-sharing-followup.md`
  - `tmp/agent-reports/android-integration-runtime.md`

Design/UI:

- Пользователь недоволен текущим дизайном и просил минимализм, теплые тона, понятность, готический стиль, меньше текста, больше иконок.
- Последняя зафиксированная дизайн-грамматика: task rows, folder -> goal -> task visual hierarchy, icon-first actions, color/dots/chips/check boxes вместо лишних слов, warm paper + graphite + muted signals, gothic only brand/header.
- Ранее были QA отчеты:
  - `tmp/agent-reports/final-planner-grammar-qa.md`
  - `tmp/agent-reports/final-v2-qa.md`
- Важно: Android-функциональные изменения после дизайн-прохода могли снова затронуть UI. Не считать дизайн финально принят без новой проверки.

## Что должен сделать следующий чат первым

Первое действие главного потока:

1. Прочитать обновленные RU rules.
2. Отдать текущую задачу планировщику/декомпозеру.
3. Планировщик должен вернуть:
   - цель;
   - сигнал готовности;
   - владельца;
   - границы;
   - что не делаем сейчас;
   - ограничения;
   - stop/go/kill;
   - нужные роли агентов.
4. Только после этого запускать исполнителей.

Если пользователь просит "статус":

- Не запускать широкую работу.
- Дать короткий статус по последним отчетам.
- Ясно сказать, что последний доказанный Android runtime stage завершен PASS на Pixel 7.
- Сказать, что runtime-процессы могли уже остановиться и для новой финальной приемки нужны свежие проверки.

Если пользователь просит "доделать до готовности":

- Сначала планировщик.
- Затем минимум такие роли:
  - context-reader: прочитать только последние отчеты и git status;
  - integration-owner: если есть незавершенные изменения или конфликтующие поверхности;
  - Android QA owner: Pixel 7 only, Gradle gate, connected e2e, screenshots;
  - backend QA owner: если backend затронут, полный Maven test и sharing smoke;
  - web QA/design owner: если пользователь просит web/design или если shared contracts затронули web.

## Обязательные Android QA требования

Для Android использовать именно Pixel 7.

Нельзя засчитывать Android e2e без:

- подтверждения AVD `Pixel_7`;
- `assembleDebug`;
- `lintDebug`;
- `assembleDebugAndroidTest`;
- `connectedDebugAndroidTest`;
- runtime screenshots.

Функциональность, которую надо проверять скриншотами при полной Android-приемке:

- авторизация;
- RU по умолчанию;
- переключение RU/EN;
- folders;
- goals;
- tasks;
- create/edit task;
- priority;
- planned/due;
- priority decay settings;
- quick reschedule;
- tags;
- recurrence;
- reminders;
- folder sharing by email/userId/link;
- goal sharing by email/userId/link;
- task sharing by email/userId/link;
- link accept flow;
- offline/local DB behavior;
- sync/recovery после возвращения связи.

## Известные риски

- Worktree очень грязный. Не откатывать чужие изменения.
- Runtime backend/PostgreSQL из прошлого этапа может уже не работать.
- Был host BSOD: Windows log показывал `Bugcheck 0x00000080`, `NMI_HARDWARE_FAILURE`, `Kernel-Power 41`, `volmgr 161`. Это похоже на host/driver/firmware/virtualization issue, не доказанный баг RocketFlow.
- Android `testDebugUnitTest` может быть `NO-SOURCE`; не считать это отдельным unit-test покрытием.
- Не заявлять production-ready без свежей финальной приемки.

## Формат ответа пользователю в новом чате

Отвечать на русском.

Каждый итоговый ответ должен содержать:

- цель;
- результат планировщика;
- какие агенты работали;
- что сделано параллельно/последовательно;
- какие проверки пройдены;
- где артефакты и скриншоты;
- риски/блокеры;
- следующий шаг.

Короткий статус допустим, если пользователь просит только статус.
