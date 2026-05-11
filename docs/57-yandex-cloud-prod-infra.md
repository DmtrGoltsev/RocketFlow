# Production-инфраструктура RocketFlow в Yandex Cloud

Этот документ описывает первый production-ready базовый вариант разворачивания backend RocketFlow в Yandex Cloud.

## Целевая архитектура

- Yandex Container Registry хранит Docker-образы backend.
- Виртуальная машина Yandex Compute Cloud запускает backend через Container Optimized Image.
- Yandex Managed Service for PostgreSQL хранит данные приложения.
- GitHub Actions собирает образ, прогоняет smoke-проверку, публикует образ и разворачивает backend-контейнер.
- Первая production-топология намеренно использует один backend-инстанс, пока работа scheduler и push-уведомлений не будет сертифицирована для горизонтального масштабирования.
- Container Optimized Image запускает контейнеры в host network, поэтому backend слушает порт VM `8080`; публичный доступ к этому порту контролирует security group.

## Почему такой baseline

Это минимальная production-схема, которая уже дает managed PostgreSQL, приватную сеть до базы, неизменяемые container-deploy и проверяемый CI/CD-путь. Kubernetes откладываем до момента, когда понадобятся несколько backend-реплик, rolling orchestration или отдельные worker-процессы.

## Bootstrap через Terraform

На машине оператора нужно установить и авторизовать `yc` и Terraform, затем выполнить:

```bash
cd infra/yandex/prod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Локальный файл `terraform.tfvars` и Terraform state содержат чувствительные значения, включая пароль базы данных. До того как production начнут обслуживать несколько людей или автоматизация, state нужно перенести в защищенный backend.

Ожидаемые outputs Terraform:

- `registry_id`
- `backend_repository`
- `backend_instance_id`
- `backend_instance_public_ip`
- `postgresql_host_fqdn`
- `rocketflow_db_url`
- `deployer_service_account_id`

## Ключ сервисного аккаунта

После `terraform apply` нужно создать authorized key для сервисного аккаунта `rocketflow-prod-github-deployer`:

```bash
yc iam key create \
  --service-account-id "$(terraform output -raw deployer_service_account_id)" \
  --output yc-prod-github-deployer-key.json
```

Весь JSON-документ нужно сохранить в GitHub secret `YC_SERVICE_ACCOUNT_KEY_JSON`.

## GitHub Secrets

Нужно создать эти secrets на уровне GitHub environment или repository:

- `YC_SERVICE_ACCOUNT_KEY_JSON`: JSON authorized key сервисного аккаунта deployer.
- `YC_CLOUD_ID`: id облака Yandex Cloud.
- `YC_FOLDER_ID`: id каталога Yandex Cloud.
- `YC_PROD_REGISTRY_ID`: Terraform output `registry_id`.
- `YC_PROD_BACKEND_INSTANCE_ID`: Terraform output `backend_instance_id`.
- `ROCKETFLOW_PROD_DB_URL`: Terraform output `rocketflow_db_url`.
- `ROCKETFLOW_PROD_DB_USERNAME`: Terraform variable `db_user`.
- `ROCKETFLOW_PROD_DB_PASSWORD`: Terraform variable `db_password`.
- `ROCKETFLOW_PROD_FCM_CREDENTIALS_JSON`: опционально, minified JSON сервисного аккаунта Firebase.

## GitHub Variables

Нужно создать эти variables на уровне GitHub environment или repository:

- `ROCKETFLOW_PROD_ALLOWED_ORIGINS`: явные browser origins через запятую.
- `ROCKETFLOW_PROD_ALLOWED_ORIGIN_PATTERNS`: pattern origins через запятую, если нужны.
- `ROCKETFLOW_PROD_HEALTH_URL`: `http://<backend_public_ip>:8080/actuator/health`, пока не добавлен HTTPS ingress.
- `ROCKETFLOW_PROD_NOTIFICATIONS_SCHEDULER_ENABLED`: `true` только после production-проверок уведомлений.
- `ROCKETFLOW_PROD_NOTIFICATIONS_FCM_ENABLED`: `true` только после настройки production-credentials Firebase.
- `ROCKETFLOW_PROD_FCM_PROJECT_ID`: id Firebase project, если FCM включен.

## Деплой

Запускается GitHub Actions workflow `Деплой backend в Yandex Cloud Prod`.

Workflow делает следующее:

1. Запускает backend tests.
2. Собирает Docker image из `backend/Dockerfile`.
3. Поднимает временный PostgreSQL-контейнер и проверяет `/actuator/health`.
4. Публикует image в Yandex Container Registry.
5. Обновляет backend-контейнер на VM через `yc compute instance update-container`.
6. Проверяет production health endpoint.

По умолчанию image tag имеет формат `sha-<short-git-sha>`. Ручной input `image_tag` может его переопределить.

## Что еще нужно до жесткого production

- Добавить HTTPS termination через Yandex Application Load Balancer или другой reverse proxy.
- Перенести Terraform state в защищенный remote backend.
- Решить, должен ли production SSH оставаться закрытым или быть ограниченным фиксированным office/VPN CIDR.
- Добавить тренировку восстановления backup базы и зафиксировать RPO/RTO.
- Сертифицировать scheduler и уведомления перед включением более чем одного backend-инстанса.
