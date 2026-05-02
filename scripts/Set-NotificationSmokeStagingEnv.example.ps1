# Example only.
# Copy this file to scripts\Set-NotificationSmokeStagingEnv.ps1, keep that local copy untracked,
# and replace the placeholders below with staging-only values before running smoke commands.

$env:ROCKETFLOW_ANDROID_API_BASE_URL = "https://staging-api.rocketflow.example.com/api"
$env:ROCKETFLOW_DB_URL = "jdbc:postgresql://staging-db.example.internal:5432/rocketflow"
$env:ROCKETFLOW_DB_USERNAME = "replace-with-staging-db-user"
$env:ROCKETFLOW_DB_PASSWORD = "replace-with-staging-db-password"
$env:ROCKETFLOW_ALLOWED_ORIGINS = "https://staging.rocketflow.example.com"
$env:ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED = "true"
$env:ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED = "true"
$env:ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID = "replace-with-staging-firebase-project-id"

# Use a local service-account JSON path, or leave this unset in your local copy
# and provide ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON in the same shell instead.
$env:ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH = "C:\path\to\firebase-service-account.json"

$SmokeUserEmail = "smoke-user@example.com"
$SmokeUserPassword = "replace-with-staging-smoke-password"

# Usage from repo root:
# . .\scripts\Set-NotificationSmokeStagingEnv.ps1

# 1. Preflight
# powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokePreflight.ps1

# 2. HTTP-only bootstrap
# powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-NotificationSmokeTask.ps1 `
#   -BackendBaseUrl $env:ROCKETFLOW_ANDROID_API_BASE_URL `
#   -Email $SmokeUserEmail `
#   -Password $SmokeUserPassword `
#   -RegisterIfMissing `
#   -SkipDeviceCheck `
#   -SkipWaitForDelivery

# The HTTP-only bootstrap is not full send/receive/tap proof.
# It only helps verify auth/register and smoke-task creation against staging.
