# Production DB Backup Local Download Runbook

Дата добавления: 2026-05-31.

## Назначение

Этот runbook описывает безопасный способ забрать production backup PostgreSQL на локальную машину и, при отдельном emergency-процессе, восстановить данные на сервере.

Модель намеренно ограничена:

- локальная машина не подключается напрямую к production PostgreSQL;
- локальный скрипт не знает DB password и не использует JDBC/psql-доступ к production DB;
- download копирует уже созданный server-side custom dump по SSH/SCP;
- server-side dump создается существующим backup-механизмом `rocketflow-backup.timer` или ручным wrapper-командным запуском на сервере;
- локальные dump-файлы считаются PII-bearing артефактами и хранятся только в ignored/local encrypted location.

Production backup-файлы на сервере:

```text
/var/backups/rocketflow/rocketflow_prod_*.dump
```

Ручной server-side backup command:

```bash
/usr/local/sbin/rocketflow-backup.sh
```

## Access Model

Предпочтительная модель доступа - отдельный restricted backup user, например `rocketbackup`.

Минимальные права:

- SSH/SCP-доступ только по отдельному ключу;
- read-only доступ к `/var/backups/rocketflow/rocketflow_prod_*.dump`;
- возможность выполнить fresh backup только через строго ограниченный sudo-wrapper;
- отсутствие прямого доступа к PostgreSQL socket, DB password, application secrets и deploy-директориям;
- отсутствие прав на изменение `/opt/rocketflow`, `/var/www/rocketflow-web`, systemd unit-файлов и application config.

Не расширять пользователя `rocketdeploy` без необходимости. `rocketdeploy` предназначен для CI/CD deploy и promote, а не для резервного администрирования данных.

Если отдельный user пока не создан, допустимый временный вариант - строго ограниченный sudo-wrapper для существующего административного пользователя. Такой вариант должен быть явно помечен как временный и не должен давать wildcard sudo на shell, `pg_dump`, `psql`, `systemctl`, `cp`, `rm` или произвольные paths.

Рекомендуемый shape для sudoers:

```text
rocketbackup ALL=(root) NOPASSWD: /usr/local/sbin/rocketflow-backup.sh
```

Проверка и копирование dump должны оставаться read-only. Fresh backup - единственная privileged операция.

## Local Configuration

Скрипт download будет находиться в:

```text
scripts/Invoke-ProdPostgresBackupDownload.ps1
```

Пример env-файла будет находиться в:

```text
scripts/Set-ProdBackupDownloadEnv.example.ps1
```

Рабочая локальная конфигурация должна храниться вне git-tracked files. Рекомендуемый локальный файл:

```text
scripts/Set-ProdBackupDownloadEnv.local.ps1
```

В локальном env допустимы только параметры доступа и пути. DB password и production application secrets туда не добавлять.

Пример формы локальных значений:

```powershell
$env:ROCKETFLOW_PROD_BACKUP_HOST = "45.10.110.42"
$env:ROCKETFLOW_PROD_BACKUP_USER = "rocketbackup"
$env:ROCKETFLOW_PROD_BACKUP_SSH_KEY_PATH = "$HOME\.ssh\rocketflow_prod_backup"
$env:ROCKETFLOW_PROD_BACKUP_REMOTE_DIR = "/var/backups/rocketflow"
$env:ROCKETFLOW_PROD_BACKUP_REMOTE_PATTERN = "rocketflow_prod_*.dump"
$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT = "$HOME\RocketFlowBackups\prod"
$env:ROCKETFLOW_PROD_BACKUP_COMMAND = "/usr/local/sbin/rocketflow-backup.sh"
```

`ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT` должен указывать на локальную encrypted/locked-down директорию, которая не находится внутри repo. Если используется директория внутри workspace, она должна быть ignored и не должна попадать в commits, archives, screenshots или test artifacts.

## PowerShell Usage

Перед запуском загрузить локальные env-параметры:

```powershell
. .\scripts\Set-ProdBackupDownloadEnv.local.ps1
```

Dry-run без изменения локальных файлов и без fresh backup:

```powershell
.\scripts\Invoke-ProdPostgresBackupDownload.ps1 -LatestOnly -DryRun
```

Download latest existing server-side dump:

```powershell
.\scripts\Invoke-ProdPostgresBackupDownload.ps1 -LatestOnly
```

Download all matching existing server-side dumps, newest first:

```powershell
.\scripts\Invoke-ProdPostgresBackupDownload.ps1
```

Запустить fresh server-side backup через restricted wrapper, затем скачать самый новый dump:

```powershell
.\scripts\Invoke-ProdPostgresBackupDownload.ps1 -RunServerBackup -LatestOnly
```

Exception-only flag:

```powershell
.\scripts\Invoke-ProdPostgresBackupDownload.ps1 -LatestOnly -SkipPgRestoreListCheck
```

Use `-SkipPgRestoreListCheck` only when local `pg_restore` is unavailable or an emergency-copy is required. The flag skips the local `pg_restore -l` readability check for the downloaded custom dump, so the default path should keep the check enabled.

Ожидаемое поведение скрипта:

- использовать `ssh` только для list/checksum/stat/run wrapper;
- использовать `scp` или совместимый SSH copy для скачивания dump;
- не открывать TCP connection к PostgreSQL;
- не запрашивать и не логировать DB password;
- писать локальный файл только в `ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT`;
- выводить remote path, local path, byte size и SHA-256 evidence.

## Download Verification

Каждый скачанный dump проверяется до любых restore-действий.

Remote SHA-256:

```powershell
ssh $env:ROCKETFLOW_PROD_BACKUP_USER@$env:ROCKETFLOW_PROD_BACKUP_HOST "sha256sum /var/backups/rocketflow/rocketflow_prod_20260531_030000.dump"
```

Local SHA-256:

```powershell
Get-FileHash "$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT\rocketflow_prod_20260531_030000.dump" -Algorithm SHA256
```

Remote size:

```powershell
ssh $env:ROCKETFLOW_PROD_BACKUP_USER@$env:ROCKETFLOW_PROD_BACKUP_HOST "stat -c '%n %s bytes' /var/backups/rocketflow/rocketflow_prod_20260531_030000.dump"
```

Local size:

```powershell
Get-Item "$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT\rocketflow_prod_20260531_030000.dump" | Select-Object FullName, Length, LastWriteTime
```

Custom dump catalog smoke:

```powershell
pg_restore -l "$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT\rocketflow_prod_20260531_030000.dump"
```

Expected verification evidence:

- remote SHA-256 equals local SHA-256;
- remote byte size equals local byte size;
- `pg_restore -l` exits successfully and lists objects;
- dump filename timestamp is the intended backup, not an older accidental file.

Do not skip the `pg_restore -l` custom dump catalog smoke check in routine runs. `-SkipPgRestoreListCheck` is reserved for local tooling gaps or emergency-copy scenarios, and any evidence note for such a run should explicitly record that custom dump readability was not checked locally.

## Local Restore Drill

Restore drill must use a separate local test DB, never a production-like shared database.

Example:

```powershell
createdb rocketflow_restore_drill
pg_restore --clean --if-exists --no-owner --dbname=rocketflow_restore_drill "$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT\rocketflow_prod_20260531_030000.dump"
psql --dbname=rocketflow_restore_drill --command "select count(*) from flyway_schema_history;"
dropdb rocketflow_restore_drill
```

Do not run local app against this DB unless the environment is isolated and clearly marked as production-derived data. Production dumps may contain PII, identifiers, tokens, audit history, and user content.

## Production Recovery Guarded Runbook

Production restore is not one-click. Treat it as an incident procedure with explicit approval and operator notes.

Preconditions:

- recovery objective and target backup are approved;
- maintenance window is active;
- users are notified if required;
- write traffic is stopped or blocked;
- intended target DB name is written down;
- at least one second operator has reviewed the selected dump filename, timestamp, byte size and SHA-256.

Guarded sequence:

1. Announce maintenance window and freeze deploys.
2. Stop backend writes by stopping `rocketflow-backend` or otherwise blocking application traffic.
3. Confirm current backend is stopped and health endpoint no longer serves write-capable traffic.
4. Create a fresh pre-restore backup on the server with `/usr/local/sbin/rocketflow-backup.sh`.
5. Record pre-restore backup filename, byte size and SHA-256.
6. Verify checksum and size for the restore dump on the server.
7. Verify the intended target DB name before running any restore command.
8. Restore only into the intended RocketFlow production DB.
9. Run Flyway/application migrations according to the deployed backend version.
10. Check `flyway_schema_history`, backend logs and `/rocket-api/health`.
11. Start `rocketflow-backend`.
12. Run smoke checks for login, planning read path and a minimal non-destructive API read.
13. End maintenance only after smoke checks pass.

Restore command shape, intentionally left with placeholders:

```bash
# Review placeholders before execution:
# <INTENDED_DB_NAME>
# <RESTORE_DUMP_PATH>
pg_restore --clean --if-exists --no-owner --dbname=<INTENDED_DB_NAME> <RESTORE_DUMP_PATH>
```

Do not paste this command blindly. Resolve placeholders in an incident note first, then have another operator review the final command.

Rollback notes:

- keep the pre-restore backup until the incident is closed;
- if restore causes a worse state, repeat the guarded sequence using the pre-restore backup;
- if schema/app compatibility is the issue, consider rolling backend to the matching release before re-opening traffic;
- never delete the selected restore dump or pre-restore dump during the incident.

## PII Handling

Production dumps are sensitive. Minimum handling rules:

- store local dumps only in an encrypted user-controlled location;
- do not commit dumps, hashes with customer identifiers, restore logs containing row data, or screenshots of production-derived data;
- do not upload dumps to chat, issue trackers, CI artifacts, cloud drives or test-artifact folders;
- delete local copies when the recovery drill or incident window is complete and retention is no longer required;
- use sanitized or synthetic data for development whenever possible.

## Evidence Checklist

For a routine local download:

- script command used;
- remote dump path;
- local dump path;
- remote and local byte size;
- remote and local SHA-256;
- successful `pg_restore -l` output summary;
- if `-SkipPgRestoreListCheck` was used, the reason and an explicit note that local custom dump readability was not checked;
- local restore drill result, if performed.

For production recovery:

- incident approval and maintenance window;
- selected restore dump metadata;
- pre-restore backup metadata;
- checksum verification;
- exact reviewed restore command;
- migration result;
- health check result;
- smoke check result;
- rollback decision or closure note.
