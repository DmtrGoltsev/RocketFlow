# Переходный промпт для нового чата

Ты продолжаешь работу в репозитории:

`C:\Users\hp\Documents\Codex\RocketFlow`

Текущая дата среды: 2026-05-04, timezone `Europe/Moscow`.

## Обязательный старт

Перед любыми действиями заново прочитай актуальные правила:

1. `C:\Users\hp\Documents\Codex\MyPrompts\Ru_OrchestratorRules.md`
2. `C:\Users\hp\Documents\Codex\MyPrompts\Ru_SubagentFirstFinishNew.md`

Не продолжай по памяти. Главный чат работает как оркестратор: сначала планировщик/декомпозер, затем ограниченные worker'ы, затем отдельная проверка доказательств.

## Git-состояние

Работа запушена в `origin/master`.

Последние коммиты:

- `8f19b6a Allow shared collaborators to create tasks`
- `674474a Checkpoint before shared creation ownership work`
- `54675b3 Fix shared planner hierarchy and status sync`

Checkpoint `674474a` создан специально перед фичей, чтобы можно было откатиться к состоянию до shared-authoring.

Этот handoff-файл является переходным артефактом. Его не нужно коммитить без отдельного запроса пользователя.

## Что реализовано

Добавлен MVP shared-authoring:

- collaborator с active share на папку или цель может создать свою задачу внутри доступной shared-цели;
- direct task share не дает права создавать sibling-задачи в родительской цели;
- task хранит `creatorUserId` отдельно от владельца контейнера;
- существующие задачи backfill'ятся: `creator_user_id = owner_user_id`;
- backend task DTO/list/detail/shared resources возвращают `creatorUserId`, `creatorEmail`, `creatorName`;
- Android New Task flow получает `createTaskGoalIds` и показывает shared-цели, где разрешено создавать задачи;
- Android task detail показывает строку `Создал` / `Creator`.

Ключевые файлы:

- `backend/src/main/resources/db/migration/V11__task_creator_tracking.sql`
- `backend/src/main/java/com/rocketflow/sharing/SharingAccessService.java`
- `backend/src/main/java/com/rocketflow/tasks/TaskService.java`
- `backend/src/main/java/com/rocketflow/tasks/TasksApi.java`
- `backend/src/main/java/com/rocketflow/sharing/SharingService.java`
- `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`
- `android/app/src/main/java/com/rocketflow/companion/MainActivity.kt`
- `android/app/src/main/java/com/rocketflow/companion/planning/PlanningRepository.kt`
- `android/app/src/main/java/com/rocketflow/companion/planning/PlanningLocalStore.kt`
- `android/app/src/main/java/com/rocketflow/companion/detail/TaskDetailRepository.kt`

## Проверки

Проверки после реализации:

- `cd backend; mvn -Dtest=SharingIntegrationTest test`
  - `BUILD SUCCESS`
  - `Tests run: 6, Failures: 0, Errors: 0`
- `cd backend; mvn test`
  - `BUILD SUCCESS`
  - `Tests run: 37, Failures: 0, Errors: 0, Skipped: 0`
  - Flyway применил и проверил 11 миграций, включая V11.
- `cd android; .\gradlew.bat :app:assembleDebug -ProcketflowApiBaseUrl=http://10.0.2.2:8081/api`
  - `BUILD SUCCESSFUL`
- `scripts/Invoke-TwoUserSharingSmoke.ps1 -BaseUrl http://localhost:8081/api -ResetAccounts`
  - `Status: OK`
  - Первый запуск без `-ResetAccounts` упал из-за старых данных в локальной БД; с reset прошел.
- Android device-login smoke на свежем APK:
  - `emulator-5554`, `styleguch@gmail.com`, `ValidationPass123`: `Status: OK`, дошел до planner screen.
  - `emulator-5556`, `rocketflow.collab@example.test`, `ValidationPass123`: `Status: OK`, дошел до planner screen.
- `git diff --cached --check`
  - чисто перед feature-коммитом.

## Тестовые аккаунты

Локальные smoke-аккаунты:

- owner: `styleguch@gmail.com`
- collaborator: `rocketflow.collab@example.test`
- пароль для обоих: `ValidationPass123`

## Текущее продуктовое решение

Разрешено:

- создавать задачу в shared goal;
- создавать задачу в goal, которая лежит внутри shared folder;
- видеть автора задачи в detail.

Не расширено в MVP:

- direct task share не дает create-доступ к parent goal;
- collaborator-created task пока не получает расширенные права полного редактирования/удаления сверх существующей read/status-only семантики, кроме уже поддержанной синхронизации статуса.

## Что первым проверить в новом чате

Если пользователь продолжит эту тему, первый практический smoke:

1. Поднять backend на локальной БД.
2. Запустить два эмулятора.
3. Войти:
   - левый/owner: `styleguch@gmail.com`
   - правый/collaborator: `rocketflow.collab@example.test`
4. На owner создать folder -> goal и поделиться folder или goal.
5. На collaborator создать задачу внутри shared goal.
6. Проверить у owner:
   - задача появилась в той же иерархии;
   - в detail видно `Создал: rocketflow.collab@example.test` или имя;
   - статус задачи синхронизируется в обе стороны.
7. Проверить negative:
   - если поделились только отдельной задачей, collaborator не должен получать create-доступ к parent goal.

## Риски

- Android после этой фичи прошел compile/build и device-login smoke на двух эмуляторах. Полноценный manual two-emulator UX-smoke именно для создания collaborator-задачи в shared goal все еще полезно повторить первым делом, если пользователь жалуется на UI.
- Local smoke зависит от чистоты локальной БД; при странных результатах запускать с `-ResetAccounts`.
- Handoff-файл может быть untracked; это ожидаемо для переходного документа.
