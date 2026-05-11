# Переходный промпт для нового чата: Android two-emulator smoke

Ты продолжаешь работу в репозитории:

`C:\Users\style\Documents\Codex\RocketFlow`

Дата последней проверки: `2026-05-11`, timezone `Europe/Moscow`.

Этот файл описывает не новую разработку, а фактический runtime-smoke, выполненный на новой Windows-машине пользователя с PostgreSQL, backend RocketFlow и двумя Android-эмуляторами.

## Скопировать в новый чат

```md
Продолжи RocketFlow в `C:\Users\style\Documents\Codex\RocketFlow`.

Сначала прочитай:
- `README.md`
- `android/README.md`
- `docs/54-next-chat-orchestrator-android-functional-start-prompt.md`
- `docs/55-next-chat-transition-prompt.md`
- `docs/56-next-chat-emulator-smoke-transition-prompt.md`

Текущий подтвержденный статус:
- исходный код приложения в ходе smoke не менялся;
- backend health был `UP` на `http://localhost:8081/api/health`;
- два Android-эмулятора были активны: `emulator-5554` и `emulator-5556`;
- через UI эмуляторов созданы 2 аккаунта;
- через UI владельца созданы 3 папки, 10 целей и минимум 5 задач на каждую цель;
- через UI владельца созданы 3 ссылки общего доступа на задачи;
- через UI второго пользователя эти ссылки приняты;
- на втором пользователе общие задачи видны и статус одной общей задачи успешно переключен `todo -> done`.

Перед любыми новыми действиями заново проверь:
- `git status --short --branch`
- `GET http://localhost:8081/api/health`
- `adb devices`
- состояние БД `rocketflow_emulator_smoke`

Не считай runtime-процессы вечными: backend, PostgreSQL и эмуляторы могли быть остановлены после предыдущего чата.
```

## Что было сделано

1. Прочитана документация проекта:
   - `README.md`
   - `android/README.md`
   - `docs/54-next-chat-orchestrator-android-functional-start-prompt.md`
   - `docs/55-next-chat-transition-prompt.md`
2. Проверена локальная среда:
   - Android SDK: `C:\Users\style\AppData\Local\Android\Sdk`
   - ADB: `C:\Users\style\AppData\Local\Android\Sdk\platform-tools\adb.exe`
   - JDK 21: `C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot`
   - Maven 3.9.15 установлен вручную в `C:\Users\style\Tools\apache-maven-3.9.15`
   - PostgreSQL 18 работает локально на `5432`
3. Создана чистая локальная БД для smoke:
   - database: `rocketflow_emulator_smoke`
   - role: `rocketflow_emulator`
   - password: `rocketflow`
4. Backend поднят на `localhost:8081` через Maven `spring-boot:run` с env:
   - `ROCKETFLOW_DB_URL=jdbc:postgresql://localhost:5432/rocketflow_emulator_smoke`
   - `ROCKETFLOW_DB_USERNAME=rocketflow_emulator`
   - `ROCKETFLOW_DB_PASSWORD=rocketflow`
   - `SERVER_PORT=8081`
5. Android debug APK собран с API URL для эмулятора:
   - `http://10.0.2.2:8081/api`
6. APK установлен на два эмулятора.
7. Для надежного ввода кириллицы установлена ADBKeyBoard:
   - `com.android.adbkeyboard/.AdbIME`
   - источник: `https://github.com/senzhk/ADBKeyBoard`
8. Все пользовательские сущности создавались через Android UI, не прямой вставкой в БД.

## Команды и проверки

Backend tests:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\backend
mvn --batch-mode --no-transfer-progress test
```

Результат:

- `BUILD SUCCESS`
- `Tests run: 39, Failures: 0, Errors: 0, Skipped: 0`

Android build/lint/test APK:

```powershell
cd C:\Users\style\Documents\Codex\RocketFlow\android
.\gradlew.bat :app:assembleDebug :app:lintDebug :app:assembleDebugAndroidTest -ProcketflowApiBaseUrl=http://10.0.2.2:8081/api
```

Результат:

- exit code `0`
- debug APK: `android\app\build\outputs\apk\debug\app-debug.apk`
- androidTest APK: `android\app\build\outputs\apk\androidTest\debug\app-debug-androidTest.apk`

Runtime health в конце проверки:

- `GET http://localhost:8081/api/health` -> `{"status":"UP"}`
- port `8081` слушал process id `34600` на момент фиксации этого файла
- `adb devices` показывал `emulator-5554` и `emulator-5556` как `device`
- `sys.boot_completed=1` на обоих

## Эмуляторы

AVD:

- `1_Pixel_6_Pro` -> `emulator-5554`
- `2_Pixel_6_Pro` -> `emulator-5556`

Обычный запуск AVD зависал без ADB-портов, рабочий запуск был headless:

```powershell
emulator -avd <AVD_NAME> -no-window -no-audio -no-snapshot-load -wipe-data -no-boot-anim -gpu swiftshader_indirect -skip-adb-auth -adb-path C:\Users\style\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

Важно: для стабилизации использовался `-wipe-data`, поэтому состояние AVD до smoke было очищено.

## Тестовые аккаунты

Созданы именно через UI Android-приложения:

- owner: `owner.rocketflow.20260511@example.test`
- collaborator: `collab.rocketflow.20260511@example.test`
- password для обоих: `ValidationPass123`

Первичная проверка после регистрации:

- оба пользователя дошли до экрана `RF План`
- в БД было `2` пользователя
- кириллица display name была сохранена корректно в UTF-8; ранний mojibake был только проблемой вывода PowerShell без UTF-8

## Данные, созданные через UI владельца

Папки:

- `Работа`
- `Дом`
- `Здоровье`

Цели:

- `Запуск проекта`
- `Отчеты`
- `Команда`
- `Клиенты`
- `Ремонт кухни`
- `Семейный бюджет`
- `Порядок`
- `Тренировки`
- `Сон`
- `Питание`

Задачи создавались по паттерну:

- `<Цель>: шаг 1 - план`
- `<Цель>: шаг 2 - подготовка`
- `<Цель>: шаг 3 - действие`
- `<Цель>: шаг 4 - проверка`
- `<Цель>: шаг 5 - итог`

Из-за медленного UI/повторного сохранения в нескольких местах получилось `58` задач вместо ровно `50`. Требование "не меньше 5 задач в каждой цели" выполнено. Распределение по целям в конце было от `5` до `8` задач на цель.

## Sharing-smoke

Владелец через UI открыл действия задач и создал share-link для трех задач:

- `Запуск проекта: шаг 2 - подготовка`
- `Отчеты: шаг 1 - план`
- `Команда: шаг 1 - план`

Созданные ссылки были приняты вторым пользователем через Android UI:

- `Настройки`
- `Принять ссылку`
- ввод ссылки в поле `Токен или ссылка`
- `Принять`

Примечание: первая попытка принять ссылку не сработала, потому что ADBKeyBoard отправила текст без явного фокуса в `EditText`. После явного тапа по `EditText` все 3 ссылки были приняты успешно.

Итог:

- `share_links=3`
- `task_shares=3`
- на collaborator появился раздел `Общие`
- видны папка `Работа`, цели `Запуск проекта`, `Отчеты`, `Команда` и 3 общие задачи
- на collaborator статус задачи `Запуск проекта: шаг 2 - подготовка` переключен через UI
- БД подтвердила `todo -> done` для task id `e9cab443-7145-4128-9be5-9db1ba0089ef`

## Финальный счетчик БД

На момент завершения smoke:

```text
users=2
folders=3
goals=10
tasks=58
share_links=3
task_shares=3
shared_done=1
```

## Артефакты

Основная папка runtime-smoke:

`C:\Users\style\Documents\Codex\RocketFlow\tmp\manual-emulator-smoke`

Ключевые файлы:

- `owner-current.png`
- `owner-after-folders.png`
- `owner-after-bulk.png`
- `owner-current-aftertasks.png`
- `collab-current.png`
- `collab-after-accept-planner.png`
- `collab-after-toggle.png`
- `backend-8081.out.log`
- `backend-8081.err.log`

Скриншоты были сняты через `adb shell screencap -p` и `adb pull`, потому что `adb exec-out screencap -p > file` в PowerShell дал поврежденные PNG из-за кодировки/перенаправления.

## Важные замечания для нового чата

- До создания этого handoff-файла `git status --short --branch` был чистым: `## master...origin/master`.
- В ходе smoke исходный код RocketFlow не менялся.
- Этот файл сам является новым docs-артефактом; если он untracked, это ожидаемо.
- Build artifacts и tmp-файлы не нужно коммитить без отдельной просьбы.
- Backend и эмуляторы на момент проверки были запущены, но новый чат обязан заново проверить runtime.
- ADBKeyBoard уже установлен на оба эмулятора, но после `-wipe-data` или пересоздания AVD его нужно ставить заново.
- Android `adb shell input text` не подходил для Unicode: для кириллицы использовался broadcast `ADB_INPUT_B64`.
- БД `rocketflow_emulator_smoke` содержит smoke-данные; при повторном тесте лучше либо переиспользовать ее осознанно, либо пересоздать.

## Рекомендуемый первый шаг в новом чате

Если пользователь просит продолжить runtime/QA:

1. Проверить `git status --short --branch`.
2. Проверить backend health на `http://localhost:8081/api/health`.
3. Проверить `adb devices`.
4. Проверить счетчики БД.
5. Снять свежий screenshot с нужного эмулятора.
6. Только после этого продолжать тестирование или менять код.

Если пользователь просит разработку:

1. Не считать результаты этого smoke заменой свежей проверки после изменения кода.
2. Делать изменения узко.
3. После изменения повторить backend tests и Android build/lint.
4. Для Android-функциональности повторить two-emulator smoke хотя бы на критическом пути.
