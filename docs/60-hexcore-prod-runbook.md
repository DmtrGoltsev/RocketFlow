# HexCore Prod Runbook

Дата первичной настройки: 2026-05-16.

## Сервер

- Провайдер: HexCore.
- Сервер: `rocketflow-prod-01`.
- IPv4: `45.10.110.42`.
- ОС: Ubuntu 26.04 LTS.
- Ресурсы: 1 CPU, 2 GB RAM, 20 GB SSD.
- Публичный health endpoint: `http://45.10.110.42/rocket-api/health`.

## Что установлено

- Java 21.
- PostgreSQL 18.
- Nginx.
- UFW firewall.
- Swap 2 GB.
- Systemd-сервис backend: `rocketflow-backend`.
- Ежедневный backup PostgreSQL: `rocketflow-backup.timer`.

Backend слушает только `127.0.0.1:8080`. Снаружи API открыт через Nginx на `http://45.10.110.42/rocket-api/...`.

Web-приложение отдается Nginx с того же сервера:

`http://45.10.110.42/rocket/`

## Текущий backend

Первый ручной деплой выполнен из чистой committed-ветки `release_1`, commit `ec54c05`.

На сервере jar лежит в:

`/opt/rocketflow/releases/rocketflow-backend-release_1-ec54c05.jar`

Текущий symlink:

`/opt/rocketflow/current/rocketflow-backend.jar`

Web-релизы загружаются в:

`/opt/rocketflow/web-releases`

Активная web-сборка:

`/var/www/rocketflow-web/current`

## Проверка

С локального компьютера:

```powershell
Invoke-RestMethod -Uri http://45.10.110.42/rocket-api/health
```

На сервере:

```bash
systemctl status rocketflow-backend
journalctl -u rocketflow-backend -n 100 --no-pager
curl http://127.0.0.1:8080/api/health
curl http://127.0.0.1/rocket-api/health
curl http://127.0.0.1/rocket/
```

## Backup

Backup-файлы:

`/var/backups/rocketflow/rocketflow_prod_*.dump`

Ручной запуск:

```bash
/usr/local/sbin/rocketflow-backup.sh
```

Проверка timer:

```bash
systemctl list-timers --all | grep rocketflow-backup
```

## CI/CD

Workflow:

`.github/workflows/backend-hexcore-prod-deploy.yml`

Запуск вручную через GitHub Actions:

`Деплой backend в HexCore Prod`

Нужные GitHub secrets для environment/repository:

- `HEXCORE_PROD_SSH_HOST`: `45.10.110.42`
- `HEXCORE_PROD_SSH_USER`: `rocketdeploy`
- `HEXCORE_PROD_SSH_PRIVATE_KEY`: содержимое приватного ключа `C:\Users\style\.ssh\rocketflow_prod_deploy`

Опционально можно передать `health_url` при ручном запуске workflow:

`http://45.10.110.42/rocket-api/health`

## SSH

Root-вход по паролю отключен. Root-вход по SSH-ключу оставлен.

Для CI/CD создан отдельный пользователь:

`rocketdeploy`

Он может:

- писать jar в `/opt/rocketflow/releases`;
- писать web-архивы в `/opt/rocketflow/web-releases`;
- вызвать только `/usr/local/sbin/rocketflow-promote-latest`;
- проверить статус `rocketflow-backend`.

Он не должен использоваться для обычного администрирования сервера.

## Важные команды

Перезапуск backend:

```bash
systemctl restart rocketflow-backend
```

Проверка сервисов:

```bash
systemctl is-active rocketflow-backend postgresql nginx
systemctl is-enabled rocketflow-backend postgresql nginx
```

Проверка ресурсов:

```bash
free -h
df -h /
```

Проверка firewall:

```bash
ufw status
```

Открыты только:

- SSH;
- HTTP 80;
- HTTPS 443.

HTTPS еще не настроен, потому что домен пока не привязан.
