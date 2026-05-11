# Настройка GitHub CI/CD для RocketFlow

Этот файл сам по себе не выполняется GitHub.

Исполняемые CI/CD-файлы находятся в `.github/workflows/*.yml`. Этот документ объясняет, что именно выполняют workflow, и какие настройки GitHub нельзя зафиксировать обычным markdown-файлом.

## Что GitHub выполняет автоматически

Эти workflow уже запускаются на каждый `push`, каждый `pull_request`, а также вручную:

- `Backend Verify` / обязательный job `backend-verify`
  - запускает Maven tests backend;
  - проверяет Flyway migrations через test suite;
  - собирает backend Docker image;
  - запускает container health smoke backend против временного PostgreSQL.
- `Web Verify` / обязательный job `web-verify`
  - устанавливает web dependencies;
  - запускает `npm run build`.
- `Android Verify` / обязательный job `android-verify`
  - устанавливает Android SDK packages;
  - запускает `./gradlew assembleDebug`.

Workflow для production-деплоя тоже является исполняемым, но запускается только вручную:

- workflow: `Деплой backend в Yandex Cloud Prod`;
- trigger: `workflow_dispatch`;
- GitHub environment: `production`.

Production-деплой намеренно не запускается автоматически на каждый `push`.

## Что нужно применить в настройках GitHub

Защита ветки является настройкой репозитория GitHub, а не обычным файлом в репозитории. Ее нужно применить через GitHub UI, GitHub API, GitHub CLI или инфраструктурный инструмент.

Минимальная branch protection для `master`:

- требовать status checks перед merge;
- требовать актуальную ветку перед merge;
- обязательные checks:
  - `backend-verify`
  - `web-verify`
  - `android-verify`
- запретить force push;
- запретить удаление ветки;
- требовать resolution всех conversations.

Когда команда начнет стабильно работать через pull requests, нужно дополнительно включить требование pull request перед merge.

## Применить branch protection скриптом

В репозитории есть исполняемый helper:

```powershell
$env:GITHUB_TOKEN = "<token-with-repository-admin-permission>"
./scripts/Set-GitHubBranchProtection.ps1
```

Вариант с обязательными pull requests:

```powershell
$env:GITHUB_TOKEN = "<token-with-repository-admin-permission>"
./scripts/Set-GitHubBranchProtection.ps1 -RequirePullRequest
```

Скрипт вызывает GitHub REST API и применяет обязательные checks:

- `backend-verify`
- `web-verify`
- `android-verify`

## Настроить защиту production environment

GitHub environment `production` тоже нужно настроить в GitHub settings:

- требовать ручное approval перед deployment;
- хранить production secrets в environment `production`, когда это возможно;
- не раскрывать production secrets для pull request workflows.

Deploy workflow уже содержит `environment: production`, поэтому GitHub сможет применять approvals после настройки environment rule.

## Production secrets

Обязательные secrets:

- `YC_SERVICE_ACCOUNT_KEY_JSON`
- `YC_CLOUD_ID`
- `YC_FOLDER_ID`
- `YC_PROD_REGISTRY_ID`
- `YC_PROD_BACKEND_INSTANCE_ID`
- `ROCKETFLOW_PROD_DB_URL`
- `ROCKETFLOW_PROD_DB_USERNAME`
- `ROCKETFLOW_PROD_DB_PASSWORD`

Опциональные secrets:

- `ROCKETFLOW_PROD_FCM_CREDENTIALS_JSON`

Рекомендуемые variables:

- `ROCKETFLOW_PROD_ALLOWED_ORIGINS`
- `ROCKETFLOW_PROD_ALLOWED_ORIGIN_PATTERNS`
- `ROCKETFLOW_PROD_HEALTH_URL`
- `ROCKETFLOW_PROD_NOTIFICATIONS_SCHEDULER_ENABLED`
- `ROCKETFLOW_PROD_NOTIFICATIONS_FCM_ENABLED`
- `ROCKETFLOW_PROD_FCM_PROJECT_ID`

## Нормальный promotion flow

1. Запушить код в feature branch.
2. Открыть pull request в `master`.
3. Дождаться `backend-verify`, `web-verify` и `android-verify`.
4. Merge делать только после зеленых обязательных checks.
5. Вручную запустить `Деплой backend в Yandex Cloud Prod`.
6. Подтвердить зеленый production health check.

## Текущие ограничения

- Web и Android gates пока являются build-only, а не runtime certification на устройстве/в браузере.
- Terraform validation все еще требует локальную или CI-установку Terraform.
- Production HTTPS в этом baseline еще не настроен.
- Горизонтальное масштабирование backend остается заблокированным, пока scheduler и уведомления не сертифицированы для нескольких инстансов.
