param(
    [switch]$RequireAdb
)

$ErrorActionPreference = "Stop"

function Test-NonEmptyEnv([string]$name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    return -not [string]::IsNullOrWhiteSpace($value)
}

function Add-CheckResult(
    [System.Collections.Generic.List[object]]$results,
    [string]$scope,
    [string]$name,
    [bool]$ok,
    [string]$details
) {
    $results.Add([pscustomobject]@{
        Scope   = $scope
        Check   = $name
        Status  = $(if ($ok) { "OK" } else { "MISSING" })
        Details = $details
    }) | Out-Null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidGoogleServices = Join-Path $repoRoot "android\app\google-services.json"
$androidLocalProperties = Join-Path $repoRoot "android\local.properties"

$results = New-Object 'System.Collections.Generic.List[object]'

Add-CheckResult $results "backend" "ROCKETFLOW_DB_URL" (Test-NonEmptyEnv "ROCKETFLOW_DB_URL") "PostgreSQL connection string"
Add-CheckResult $results "backend" "ROCKETFLOW_DB_USERNAME" (Test-NonEmptyEnv "ROCKETFLOW_DB_USERNAME") "Backend database username"
Add-CheckResult $results "backend" "ROCKETFLOW_DB_PASSWORD" (Test-NonEmptyEnv "ROCKETFLOW_DB_PASSWORD") "Backend database password"
Add-CheckResult $results "backend" "ROCKETFLOW_ALLOWED_ORIGINS" (Test-NonEmptyEnv "ROCKETFLOW_ALLOWED_ORIGINS") "Allowed staging or local web origin"
Add-CheckResult $results "backend" "ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=true" (([Environment]::GetEnvironmentVariable("ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED")) -eq "true") "Reminder polling must be enabled for smoke"
Add-CheckResult $results "backend" "ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=true" (([Environment]::GetEnvironmentVariable("ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED")) -eq "true") "Real Firebase sender path must be enabled"
Add-CheckResult $results "backend" "ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID" (Test-NonEmptyEnv "ROCKETFLOW_NOTIFICATIONS_FCM_PROJECT_ID") "Firebase project id for backend sender"

$hasCredentialsJson = Test-NonEmptyEnv "ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON"
$hasCredentialsPathEnv = Test-NonEmptyEnv "ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH"
$credentialsPath = [Environment]::GetEnvironmentVariable("ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH")
$credentialsPathExists = $false
if ($hasCredentialsPathEnv) {
    $credentialsPathExists = Test-Path -LiteralPath $credentialsPath
}
$hasBackendCredentials = $hasCredentialsJson -or $credentialsPathExists
$credentialsDetails = if ($hasCredentialsJson) {
    "Credentials JSON env var is present"
} elseif ($hasCredentialsPathEnv) {
    if ($credentialsPathExists) {
        "Credentials path exists: $credentialsPath"
    } else {
        "Credentials path env var is set but file is missing: $credentialsPath"
    }
} else {
    "Set ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON or ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH"
}
Add-CheckResult $results "backend" "FCM credentials" $hasBackendCredentials $credentialsDetails

Add-CheckResult $results "android" "ROCKETFLOW_ANDROID_API_BASE_URL" (Test-NonEmptyEnv "ROCKETFLOW_ANDROID_API_BASE_URL") "Android build target backend base URL"
Add-CheckResult $results "android" "android/local.properties" (Test-Path -LiteralPath $androidLocalProperties) "Local SDK wiring for Android build"

$hasGoogleServices = Test-Path -LiteralPath $androidGoogleServices
$manualFirebaseVars = @(
    "ROCKETFLOW_ANDROID_FIREBASE_APPLICATION_ID",
    "ROCKETFLOW_ANDROID_FIREBASE_API_KEY",
    "ROCKETFLOW_ANDROID_FIREBASE_PROJECT_ID",
    "ROCKETFLOW_ANDROID_FIREBASE_GCM_SENDER_ID"
)
$missingManualVars = $manualFirebaseVars | Where-Object { -not (Test-NonEmptyEnv $_) }
$hasManualFirebase = $missingManualVars.Count -eq 0
$hasAndroidFirebaseConfig = $hasGoogleServices -or $hasManualFirebase
$androidFirebaseDetails = if ($hasGoogleServices) {
    "google-services.json exists"
} elseif ($hasManualFirebase) {
    "All manual Firebase env vars are present"
} else {
    "Missing manual vars: $($missingManualVars -join ', ')"
}
Add-CheckResult $results "android" "Firebase bootstrap config" $hasAndroidFirebaseConfig $androidFirebaseDetails

if ($RequireAdb) {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    Add-CheckResult $results "android" "adb" ($null -ne $adb) "Optional connected-device tooling"
}

$results | Format-Table -AutoSize | Out-String | Write-Host

$missing = @($results | Where-Object { $_.Status -ne "OK" })
if ($missing.Count -gt 0) {
    Write-Host "Notification smoke preflight failed. Fix the missing items above before running the real smoke."
    exit 1
}

Write-Host "Notification smoke preflight passed. Continue with docs/45-notification-staging-smoke-runbook.md."
