# Переходный промпт для нового чата: MVP2 Android reminders

Скопируй этот текст в новый чат, чтобы продолжить работу без потери контекста.

## Стартовый текст для нового чата

Ты оркестратор. Работай в репозитории:

`C:\Users\style\Documents\Codex\RocketFlow`

Сначала прочитай базовые правила пользователя:

- `C:\Users\style\Documents\Codex\myprompt\Ru_OrchestratorRules.md`
- `C:\Users\style\Documents\Codex\myprompt\Ru_SubagentFirstFinishNew.md`

Также прочитай проектные переходные документы:

- `C:\Users\style\Documents\Codex\RocketFlow\docs\56-next-chat-emulator-smoke-transition-prompt.md`
- `C:\Users\style\Documents\Codex\RocketFlow\docs\58-github-cicd-policy.md`
- `C:\Users\style\Documents\Codex\RocketFlow\docs\59-next-chat-mvp2-reminders-transition-prompt.md`

Продолжай работу в ветке `MVP2`. Не откатывай и не перетирай существующие незакоммиченные изменения. Пользователь требует оркестрацию, проверки, скриншоты и короткие русские объяснения. Финалом работы должны быть доказательства: тесты, команды, скриншоты или понятное описание того, что не удалось проверить.

## Текущее состояние

Ветка: `MVP2`.

Фича напоминаний для задач реализована, но изменения еще не закоммичены.

Правильная продуктовая логика:

- Бэкенд хранит только дедлайн задачи.
- Пользователь Android сам на устройстве выбирает время напоминания и повтор.
- Частота и локальное время напоминаний не должны храниться в бэкенде.
- iPhone/browser web-приложение не должно показывать серверные настройки напоминаний.
- Старый backend endpoint `/api/tasks/{taskId}/reminders` закрыт и для владельца возвращает `410 reminders_not_supported`.
- Логика задач, папок, целей и сроков должна ориентироваться на Android как эталон.
- В интерфейсах сроки называются понятнее: `Когда делать` и `Дедлайн`.

## Измененные файлы

Android:

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- `android/app/src/main/java/com/rocketflow/companion/RocketFlowCompanionApp.kt`
- `android/app/src/main/java/com/rocketflow/companion/notifications/NotificationRuntime.kt`
- `android/app/src/main/java/com/rocketflow/companion/planning/PlanningRepository.kt`

Новые Android-файлы:

- `android/app/src/main/java/com/rocketflow/companion/notifications/TaskReminderAlarmReceiver.kt`
- `android/app/src/main/java/com/rocketflow/companion/notifications/TaskReminderAlarmScheduler.kt`
- `android/app/src/main/java/com/rocketflow/companion/notifications/TaskReminderBootReceiver.kt`
- `android/app/src/main/java/com/rocketflow/companion/notifications/TaskReminderModels.kt`
- `android/app/src/main/java/com/rocketflow/companion/notifications/TaskReminderStore.kt`
- `android/app/src/test/java/com/rocketflow/companion/notifications/TaskReminderScheduleUnitTest.kt`

Backend:

- `backend/src/main/java/com/rocketflow/tasks/TaskController.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`
- `backend/src/test/java/com/rocketflow/NotificationDeliveryIntegrationTest.java`
- `backend/src/test/java/com/rocketflow/RecurrenceReminderIntegrationTest.java`
- `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`

Web:

- `web/src/features/planning/planning-api.ts`
- `web/src/features/planning/planning-copy.ts`
- `web/src/features/planning/planning-utils.ts`
- `web/src/features/planning/routes/TasksRoute.tsx`
- `web/src/features/planning/types.ts`

## Что уже проверено

Web build:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\web
npm.cmd run build
```

Результат: успешно.

Backend tests:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\backend
mvn.cmd --batch-mode --no-transfer-progress clean test
```

Результат: `Tests run: 39, Failures: 0, Errors: 0, Skipped: 0`, `BUILD SUCCESS`.

Android tests/build/lint:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\android
$env:ANDROID_HOME='C:\Users\style\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT='C:\Users\style\AppData\Local\Android\Sdk'
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:lintDebug -ProcketflowApiBaseUrl=http://10.0.2.2:8081/api
```

Результат: `BUILD SUCCESSFUL`. Были только существующие deprecation warnings.

Runtime API:

- Backend был поднят на `8081`.
- `GET http://localhost:8081/api/health` вернул `UP`.
- Тестовая задача: `3d661d01-bdbe-4d32-9932-de7c83ba5b40`.
- `GET /api/tasks/{id}` не содержит свойства `reminders`.
- `PUT /api/tasks/{id}/reminders` вернул `410`, код `reminders_not_supported`.

Проверочный вывод:

```text
TaskId: 3d661d01-bdbe-4d32-9932-de7c83ba5b40
HasRemindersProperty: false
ReminderPutStatus: 410
ReminderPutCode: reminders_not_supported
```

## Скриншоты и артефакты

Папка:

`C:\Users\style\Documents\Codex\RocketFlow\tmp\mvp2-reminders-smoke`

Ключевые скриншоты:

- `web-iphone-task-detail-fresh.png`
- `web-iphone-task-scheduling-fresh.png`
- `web-desktop-task-detail-fresh.png`
- `android-detail-expanded-final.png`
- `android-reminder-dialog-future.png`
- `android-reminder-saved-future.png`
- `android-notification-shade.png`
- `android-notification-opened-task.png`

Логи:

- `backend-8081.out.log`
- `backend-8081.err.log`
- `web-5174.out.log`
- `web-5174.err.log`

Тестовые пользователи:

- owner: `owner.rocketflow.20260511@example.test`
- collaborator: `collab.rocketflow.20260511@example.test`
- password: `ValidationPass123`

Тестовая задача:

- title: `MVP2 alarm smoke 195435`
- id: `3d661d01-bdbe-4d32-9932-de7c83ba5b40`
- dueTime: `2026-05-14T17:01:35.648379Z`

Доказательство Android-уведомления:

- `dumpsys notification` показывал `importance=4`, `category=alarm`, channel `rocketflow.task.alarms`, title `MVP2 alarm smoke 195435`.
- `dumpsys alarm` до срабатывания показывал `RTC_WAKEUP`, `Alarm clock`, action `com.rocketflow.companion.notifications.TASK_REMINDER`, trigger `2026-05-14 17:01:00.000`.
- Уведомление было видно в шторке Android и по тапу открывало задачу.

## Что сделать первым в новом чате

1. Проверить состояние ветки:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow
git status --short --branch
```

2. Проверить backend или перезапустить его:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\backend
$env:ROCKETFLOW_DB_URL='jdbc:postgresql://localhost:5432/rocketflow_emulator_smoke'
$env:ROCKETFLOW_DB_USERNAME='rocketflow_emulator'
$env:ROCKETFLOW_DB_PASSWORD='rocketflow'
$env:SERVER_PORT='8081'
mvn.cmd --batch-mode --no-transfer-progress spring-boot:run
```

3. Проверить Android emulator:

```powershell
adb devices
```

4. Если нужна повторная Android-проверка, перед запуском дать разрешения:

```powershell
adb -s emulator-5554 shell pm grant com.rocketflow.companion android.permission.POST_NOTIFICATIONS
adb -s emulator-5554 shell cmd appops set com.rocketflow.companion SCHEDULE_EXACT_ALARM allow
```

5. Если нужно зафиксировать изменения, коммитить только осознанные изменения кода и документацию. Не добавлять `tmp/` со скриншотами в коммит, если пользователь явно не попросит.

## Важные предупреждения

- Не использовать `git reset --hard`, `git checkout --` и другие откаты без прямой просьбы пользователя.
- Не откатывать чужие или уже существующие изменения.
- Простые правки файлов делать через `apply_patch`.
- Для Android screenshot в PowerShell лучше использовать:

```powershell
adb -s emulator-5554 shell screencap -p /sdcard/screen.png
adb -s emulator-5554 pull /sdcard/screen.png C:\Users\style\Documents\Codex\RocketFlow\tmp\mvp2-reminders-smoke\screen.png
```

Не использовать `adb exec-out screencap -p > file` в PowerShell: PNG может повреждаться.

- Старые backend-таблицы и миграции для reminder/notification могут оставаться в проекте из предыдущей архитектуры. В текущем MVP2 публичная логика напоминаний для задач закрыта на backend: backend хранит дедлайн, Android хранит локальные настройки будильника.
