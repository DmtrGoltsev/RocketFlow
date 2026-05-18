# Настройка GitHub CI/CD для RocketFlow

Этот файл не выполняется GitHub напрямую. Исполняемые сценарии лежат в `.github/workflows/*.yml`.

## Что проверяется автоматически

На каждый `push`, `pull_request` и ручной запуск должны проходить проверки:

- `backend-verify`: Maven tests backend, Flyway migrations через тесты, сборка backend Docker image, container health smoke против временного PostgreSQL.
- `web-verify`: установка зависимостей web и `npm run build`.
- `android-verify`: установка Android SDK packages, `:app:testDebugUnitTest`, `:app:assembleDebug` и `:app:lintDebug`.

## Production Deploy

Production deploy работает только через HexCore-сервер:

- workflow: `Деплой backend в HexCore Prod`;
- файл: `.github/workflows/backend-hexcore-prod-deploy.yml`;
- сервер: `45.10.110.42`;
- пользователь деплоя: `rocketdeploy`;
- backend runtime: jar + `systemd`, без Docker;
- web runtime: статическая сборка Vite через Nginx;
- backend service: `rocketflow-backend`;
- health check: `http://45.10.110.42/rocket-api/health`.

Workflow запускается:

- вручную через `workflow_dispatch`;
- автоматически на `push` в ветку `release_1`.

Это и есть деплой после принятия pull request: PR из `MVP2` вливается в `release_1`, GitHub создаёт push в `release_1`, после чего стартует production deploy. На каждый push в `MVP2` production deploy намеренно не запускается.

## GitHub Secrets

Для production environment или repository secrets нужны:

- `HEXCORE_PROD_SSH_HOST`: `45.10.110.42`
- `HEXCORE_PROD_SSH_USER`: `rocketdeploy`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`: приватный deploy-ключ из `C:\Users\style\.ssh\rocketflow_prod_deploy`

Приватный ключ нельзя коммитить в репозиторий. Его нужно добавить только в GitHub secrets.

## Branch Protection

Минимальная защита для `release_1`:

- требовать status checks перед merge;
- требовать актуальную ветку перед merge;
- обязательные checks: `backend-verify`, `web-verify`, `android-verify`;
- запретить force push;
- запретить удаление ветки;
- требовать resolution всех conversations;
- требовать pull request перед merge.

## Нормальный Promotion Flow

1. Работать в `MVP2`.
2. Открыть pull request из `MVP2` в `release_1`.
3. Дождаться зелёных checks: `backend-verify`, `web-verify`, `android-verify`.
4. Делать merge только после зелёных checks.
5. После merge GitHub запускает deploy на HexCore.
6. Workflow выкладывает backend jar и web build.
7. Workflow проверяет `http://45.10.110.42/rocket-api/health` и доступность web root `http://45.10.110.42/rocket/`.

## Текущие ограничения

- GitHub secrets и branch protection являются настройками GitHub, а не файлами репозитория.
- HTTPS ещё не настроен, потому что домен пока не привязан.
- Android APK для пользователя собирается локально или отдельным release workflow, которого пока нет.
