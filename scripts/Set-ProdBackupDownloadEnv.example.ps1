# Example only.
# Copy this file to scripts\Set-ProdBackupDownloadEnv.local.ps1 or
# scripts\Set-ProdBackupDownloadEnv.ps1 and keep that local copy untracked.
# Do not put database passwords, dump files, or private key contents in this file.

$env:ROCKETFLOW_PROD_BACKUP_HOST = "prod-backup.example.com"
$env:ROCKETFLOW_PROD_BACKUP_USER = "rocketflow-backup"

# Optional. Use a local SSH private key path if the default ssh-agent/config is not enough.
$env:ROCKETFLOW_PROD_BACKUP_SSH_KEY_PATH = "C:\Users\you\.ssh\rocketflow-prod-backup"

$env:ROCKETFLOW_PROD_BACKUP_REMOTE_DIR = "/var/backups/rocketflow"
$env:ROCKETFLOW_PROD_BACKUP_REMOTE_PATTERN = "rocketflow_prod_*.dump"
$env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT = "tmp/prod-db-backups"
$env:ROCKETFLOW_PROD_BACKUP_COMMAND = "/usr/local/sbin/rocketflow-backup.sh"

# Usage from repo root:
# . .\scripts\Set-ProdBackupDownloadEnv.local.ps1

# Preview without connecting to production:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-ProdPostgresBackupDownload.ps1 -DryRun -LatestOnly

# Download the newest existing server-side backup:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-ProdPostgresBackupDownload.ps1 -LatestOnly

# Exception only: skip pg_restore -l custom dump readability check when local
# pg_restore is unavailable or an emergency-copy is required.
# powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-ProdPostgresBackupDownload.ps1 -LatestOnly -SkipPgRestoreListCheck

# First request a new server-side backup via sudo, then download the newest dump:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-ProdPostgresBackupDownload.ps1 -RunServerBackup -LatestOnly
