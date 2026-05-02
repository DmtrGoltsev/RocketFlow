param(
    [int]$BackendPort = 18080,
    [string]$SpringProfile = "local",
    [string]$MavenCommand = "mvn",
    [switch]$SkipPreflight,
    [switch]$SkipHealthWait,
    [int]$HealthTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

function Test-NonEmptyEnv([string]$name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    return -not [string]::IsNullOrWhiteSpace($value)
}

function Write-Step([string]$message) {
    Write-Host "[notification-smoke] $message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot "backend"
$preflightScript = Join-Path $PSScriptRoot "Invoke-NotificationSmokePreflight.ps1"

if (-not (Test-Path -LiteralPath $backendDir)) {
    throw "Backend directory was not found at $backendDir"
}

$expectedAndroidBaseUrl = "http://10.0.2.2:$BackendPort/api"
$configuredAndroidBaseUrl = [Environment]::GetEnvironmentVariable("ROCKETFLOW_ANDROID_API_BASE_URL")
if ([string]::IsNullOrWhiteSpace($configuredAndroidBaseUrl)) {
    Write-Step "ROCKETFLOW_ANDROID_API_BASE_URL was empty; setting it for this shell to $expectedAndroidBaseUrl"
    [Environment]::SetEnvironmentVariable("ROCKETFLOW_ANDROID_API_BASE_URL", $expectedAndroidBaseUrl)
    $configuredAndroidBaseUrl = $expectedAndroidBaseUrl
} elseif ($configuredAndroidBaseUrl -ne $expectedAndroidBaseUrl) {
    throw "ROCKETFLOW_ANDROID_API_BASE_URL must match the owned backend port. Expected $expectedAndroidBaseUrl but found $configuredAndroidBaseUrl"
}

if (-not (Test-NonEmptyEnv "ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY")) {
    [Environment]::SetEnvironmentVariable("ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY", "PT15S")
    Write-Step "Defaulted ROCKETFLOW_NOTIFICATIONS_SCHEDULER_FIXED_DELAY to PT15S for smoke mode"
}

if (-not (Test-NonEmptyEnv "ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY")) {
    [Environment]::SetEnvironmentVariable("ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY", "PT5S")
    Write-Step "Defaulted ROCKETFLOW_NOTIFICATIONS_SCHEDULER_INITIAL_DELAY to PT5S for smoke mode"
}

if (-not $SkipPreflight) {
    if (-not (Test-Path -LiteralPath $preflightScript)) {
        throw "Required preflight script was not found at $preflightScript"
    }

    Write-Step "Running notification smoke preflight in the same shell context"
    & powershell -ExecutionPolicy Bypass -File $preflightScript
    if ($LASTEXITCODE -ne 0) {
        throw "Notification smoke preflight failed"
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $repoRoot "tmp\notification-smoke"
$stdoutLog = Join-Path $logDir "backend-$timestamp.log"
$stderrLog = Join-Path $logDir "backend-$timestamp.err.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$healthUrl = "http://localhost:$BackendPort/actuator/health"
$mavenArgs = @(
    "-Dspring-boot.run.profiles=$SpringProfile",
    "-Dspring-boot.run.arguments=--server.port=$BackendPort",
    "spring-boot:run"
)

Write-Step "Starting owned backend runtime on http://localhost:$BackendPort"
$process = Start-Process `
    -FilePath $MavenCommand `
    -ArgumentList $mavenArgs `
    -WorkingDirectory $backendDir `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -PassThru `
    -WindowStyle Hidden

Write-Step "Backend PID: $($process.Id)"
Write-Step "stdout log: $stdoutLog"
Write-Step "stderr log: $stderrLog"

if ($SkipHealthWait) {
    Write-Step "Health wait skipped. Manually verify $healthUrl before Android smoke."
    exit 0
}

$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
do {
    Start-Sleep -Seconds 2

    if ($process.HasExited) {
        throw "Backend exited before health became ready. Check $stdoutLog and $stderrLog"
    }

    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
        if ($response.status -eq "UP") {
            Write-Step "Backend health is UP at $healthUrl"
            Write-Step "Owned runtime is ready. Continue with Android install/login and the docs/51 playbook."
            exit 0
        }
    } catch {
        # Keep polling until the timeout expires.
    }
} while ((Get-Date) -lt $deadline)

throw "Timed out waiting for backend health at $healthUrl. Check $stdoutLog and $stderrLog"
