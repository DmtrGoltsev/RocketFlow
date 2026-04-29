param(
    [string]$BackendImage = "rocketflow-backend:latest",
    [int]$BackendPort = 18080,
    [int]$PostgresPort = 15432,
    [switch]$KeepContainers,
    [string]$PostgresImage = "postgres:16",
    [string]$PostgresDatabase = "rocketflow",
    [string]$PostgresUsername = "rocketflow",
    [string]$PostgresPassword = "rocketflow",
    [string]$AllowedOrigins = "http://localhost:5173,http://127.0.0.1:5173",
    [int]$PostgresReadyTimeoutSeconds = 60,
    [int]$BackendHealthTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[docker-smoke] $Message"
}

function Convert-OutputToText([object[]]$Output) {
    if ($null -eq $Output) {
        return ""
    }

    $parts = @(
        $Output |
            Where-Object { $null -ne $_ } |
            ForEach-Object { $_.ToString() }
    )

    if ($parts.Count -eq 0) {
        return ""
    }

    return ($parts -join [Environment]::NewLine).Trim()
}

function Invoke-Docker {
    param(
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $argumentLine = (
        $Arguments |
            ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + $_.Replace('"', '\"') + '"'
                } else {
                    $_
                }
            }
    ) -join " "

    try {
        $startProcessArguments = @{
            FilePath               = "docker"
            ArgumentList           = $argumentLine
            PassThru               = $true
            Wait                   = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError  = $stderrPath
        }

        if ($IsWindows) {
            $startProcessArguments.WindowStyle = "Hidden"
        }

        $process = Start-Process @startProcessArguments

        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath -Raw
        } else {
            ""
        }
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw
        } else {
            ""
        }

        $text = Convert-OutputToText -Output @($stdout, $stderr)
        $exitCode = $process.ExitCode
    } finally {
        Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    }

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        $details = if ([string]::IsNullOrWhiteSpace($text)) {
            "docker exited with code $exitCode."
        } else {
            $text
        }

        throw "docker $($Arguments -join ' ') failed. $details"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $text
    }
}

function Test-ToolAvailable([string]$CommandName) {
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-ContainerExists([string]$ContainerName) {
    $result = Invoke-Docker -Arguments @("container", "inspect", $ContainerName) -IgnoreExitCode
    return $result.ExitCode -eq 0
}

function Get-ContainerState([string]$ContainerName) {
    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        return $null
    }

    $result = Invoke-Docker -Arguments @("inspect", "--format", "{{json .State}}", $ContainerName)
    if ([string]::IsNullOrWhiteSpace($result.Output)) {
        return $null
    }

    return $result.Output | ConvertFrom-Json
}

function Save-ContainerLogs(
    [string]$ContainerName,
    [string]$DestinationPath
) {
    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        Set-Content -LiteralPath $DestinationPath -Value "Container '$ContainerName' was not created." -Encoding utf8
        return $false
    }

    $result = Invoke-Docker -Arguments @("logs", "--timestamps", $ContainerName) -IgnoreExitCode
    $content = if ([string]::IsNullOrWhiteSpace($result.Output)) {
        "(no log output captured)"
    } else {
        $result.Output
    }

    Set-Content -LiteralPath $DestinationPath -Value $content -Encoding utf8
    return $true
}

function Remove-ContainerIfExists([string]$ContainerName) {
    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        return $false
    }

    Invoke-Docker -Arguments @("rm", "-f", $ContainerName) -IgnoreExitCode | Out-Null
    return $true
}

function Remove-NetworkIfExists([string]$NetworkName) {
    $result = Invoke-Docker -Arguments @("network", "inspect", $NetworkName) -IgnoreExitCode
    if ($result.ExitCode -ne 0) {
        return $false
    }

    Invoke-Docker -Arguments @("network", "rm", $NetworkName) -IgnoreExitCode | Out-Null
    return $true
}

function Wait-ForPostgresReady(
    [string]$ContainerName,
    [string]$Database,
    [string]$Username,
    [int]$TimeoutSeconds
) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastMessage = $null

    do {
        $state = Get-ContainerState -ContainerName $ContainerName
        if ($null -eq $state) {
            return [pscustomobject]@{
                Success       = $false
                FailureReason = "Postgres container '$ContainerName' was not found while waiting for readiness."
                LastMessage   = $lastMessage
                ContainerState = $null
            }
        }

        if ($state.Status -ne "running") {
            return [pscustomobject]@{
                Success        = $false
                FailureReason  = "Postgres container '$ContainerName' is '$($state.Status)' while waiting for readiness."
                LastMessage    = $lastMessage
                ContainerState = $state
            }
        }

        $result = Invoke-Docker -Arguments @(
            "exec",
            $ContainerName,
            "pg_isready",
            "-h",
            "127.0.0.1",
            "-p",
            "5432",
            "-U",
            $Username,
            "-d",
            $Database
        ) -IgnoreExitCode

        $lastMessage = $result.Output
        if ($result.ExitCode -eq 0) {
            return [pscustomobject]@{
                Success        = $true
                FailureReason  = $null
                LastMessage    = $lastMessage
                ContainerState = $state
            }
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    return [pscustomobject]@{
        Success        = $false
        FailureReason  = "Timed out after $TimeoutSeconds second(s) waiting for postgres readiness."
        LastMessage    = $lastMessage
        ContainerState = Get-ContainerState -ContainerName $ContainerName
    }
}

function Wait-ForBackendHealth(
    [string]$ContainerName,
    [string]$HealthUrl,
    [int]$TimeoutSeconds
) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    $lastResponse = $null
    $attempts = 0

    do {
        $attempts += 1
        $state = Get-ContainerState -ContainerName $ContainerName
        if ($null -eq $state) {
            return [pscustomobject]@{
                Success        = $false
                FailureReason  = "Backend container '$ContainerName' was not found while waiting for health."
                LastError      = $lastError
                LastResponse   = $lastResponse
                Attempts       = $attempts
                ContainerState = $null
            }
        }

        if ($state.Status -ne "running") {
            return [pscustomobject]@{
                Success        = $false
                FailureReason  = "Backend container '$ContainerName' is '$($state.Status)' while waiting for health."
                LastError      = $lastError
                LastResponse   = $lastResponse
                Attempts       = $attempts
                ContainerState = $state
            }
        }

        try {
            $response = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 5 -ErrorAction Stop
            $lastResponse = $response
            if ($response.status -eq "UP") {
                return [pscustomobject]@{
                    Success        = $true
                    FailureReason  = $null
                    LastError      = $null
                    LastResponse   = $lastResponse
                    Attempts       = $attempts
                    ContainerState = $state
                }
            }

            $lastError = "Health endpoint returned status '$($response.status)'."
        } catch {
            $lastError = $_.Exception.Message
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    return [pscustomobject]@{
        Success        = $false
        FailureReason  = "Timed out after $TimeoutSeconds second(s) waiting for backend health UP."
        LastError      = $lastError
        LastResponse   = $lastResponse
        Attempts       = $attempts
        ContainerState = Get-ContainerState -ContainerName $ContainerName
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactDirectory = Join-Path (Join-Path $repoRoot "tmp") "docker-smoke"
New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null

$startedAt = Get-Date
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$networkName = "rocketflow-smoke-net-$runId"
$postgresContainerName = "rocketflow-smoke-pg-$runId"
$backendContainerName = "rocketflow-smoke-backend-$runId"
$postgresLogPath = Join-Path $artifactDirectory "postgres-$runId.log"
$backendLogPath = Join-Path $artifactDirectory "backend-$runId.log"
$reportPath = Join-Path $artifactDirectory "report-$runId.json"
$healthUrl = "http://localhost:$BackendPort/actuator/health"
$databaseUrl = "jdbc:postgresql://{0}:5432/{1}" -f $postgresContainerName, $PostgresDatabase

$success = $false
$failureMessage = $null
$postgresReadyResult = $null
$backendHealthResult = $null
$postgresContainerId = $null
$backendContainerId = $null
$postgresStateBeforeCleanup = $null
$backendStateBeforeCleanup = $null
$postgresLogsSaved = $false
$backendLogsSaved = $false
$postgresRemoved = $false
$backendRemoved = $false
$networkRemoved = $false

try {
    if (-not (Test-ToolAvailable -CommandName "docker")) {
        throw "Docker was not found in PATH."
    }

    Write-Step "Checking that backend image '$BackendImage' exists locally"
    Invoke-Docker -Arguments @("image", "inspect", $BackendImage) | Out-Null

    Write-Step "Creating temporary docker network '$networkName'"
    Invoke-Docker -Arguments @("network", "create", $networkName) | Out-Null

    Write-Step "Starting postgres container '$postgresContainerName' on localhost:$PostgresPort"
    $postgresRunResult = Invoke-Docker -Arguments @(
        "run",
        "-d",
        "--name",
        $postgresContainerName,
        "--network",
        $networkName,
        "--publish",
        "${PostgresPort}:5432",
        "--env",
        "POSTGRES_DB=$PostgresDatabase",
        "--env",
        "POSTGRES_USER=$PostgresUsername",
        "--env",
        "POSTGRES_PASSWORD=$PostgresPassword",
        $PostgresImage
    )
    $postgresContainerId = $postgresRunResult.Output

    Write-Step "Waiting for postgres readiness via pg_isready"
    $postgresReadyResult = Wait-ForPostgresReady `
        -ContainerName $postgresContainerName `
        -Database $PostgresDatabase `
        -Username $PostgresUsername `
        -TimeoutSeconds $PostgresReadyTimeoutSeconds
    if (-not $postgresReadyResult.Success) {
        throw $postgresReadyResult.FailureReason
    }

    Write-Step "Starting backend container '$backendContainerName' on http://localhost:$BackendPort"
    $backendRunResult = Invoke-Docker -Arguments @(
        "run",
        "-d",
        "--name",
        $backendContainerName,
        "--network",
        $networkName,
        "--publish",
        "${BackendPort}:8080",
        "--env",
        "ROCKETFLOW_DB_URL=$databaseUrl",
        "--env",
        "ROCKETFLOW_DB_USERNAME=$PostgresUsername",
        "--env",
        "ROCKETFLOW_DB_PASSWORD=$PostgresPassword",
        "--env",
        "ROCKETFLOW_ALLOWED_ORIGINS=$AllowedOrigins",
        "--env",
        "ROCKETFLOW_NOTIFICATIONS_SCHEDULER_ENABLED=false",
        "--env",
        "ROCKETFLOW_NOTIFICATIONS_FCM_ENABLED=false",
        $BackendImage
    )
    $backendContainerId = $backendRunResult.Output

    Write-Step "Waiting for backend health at $healthUrl"
    $backendHealthResult = Wait-ForBackendHealth `
        -ContainerName $backendContainerName `
        -HealthUrl $healthUrl `
        -TimeoutSeconds $BackendHealthTimeoutSeconds
    if (-not $backendHealthResult.Success) {
        throw $backendHealthResult.FailureReason
    }

    $success = $true
    Write-Step "Backend health is UP"
} catch {
    $failureMessage = $_.Exception.Message
    Write-Step $failureMessage
    throw
} finally {
    $postgresStateBeforeCleanup = Get-ContainerState -ContainerName $postgresContainerName
    $backendStateBeforeCleanup = Get-ContainerState -ContainerName $backendContainerName

    $postgresLogsSaved = Save-ContainerLogs -ContainerName $postgresContainerName -DestinationPath $postgresLogPath
    $backendLogsSaved = Save-ContainerLogs -ContainerName $backendContainerName -DestinationPath $backendLogPath

    if (-not $KeepContainers) {
        $backendRemoved = Remove-ContainerIfExists -ContainerName $backendContainerName
        $postgresRemoved = Remove-ContainerIfExists -ContainerName $postgresContainerName
        $networkRemoved = Remove-NetworkIfExists -NetworkName $networkName
    }

    $completedAt = Get-Date
    $report = [ordered]@{
        generatedAt = $completedAt.ToString("o")
        runId = $runId
        succeeded = $success
        failureMessage = $failureMessage
        keepContainers = [bool]$KeepContainers
        timings = [ordered]@{
            startedAt = $startedAt.ToString("o")
            completedAt = $completedAt.ToString("o")
            durationSeconds = [math]::Round(($completedAt - $startedAt).TotalSeconds, 3)
        }
        backend = [ordered]@{
            image = $BackendImage
            containerName = $backendContainerName
            containerId = $backendContainerId
            hostPort = $BackendPort
            healthUrl = $healthUrl
            allowedOrigins = $AllowedOrigins
            notificationsSchedulerEnabled = $false
            notificationsFcmEnabled = $false
            healthResult = $backendHealthResult
            stateBeforeCleanup = $backendStateBeforeCleanup
            logPath = $backendLogPath
            logSaved = $backendLogsSaved
            removed = $backendRemoved
        }
        postgres = [ordered]@{
            image = $PostgresImage
            containerName = $postgresContainerName
            containerId = $postgresContainerId
            hostPort = $PostgresPort
            database = $PostgresDatabase
            username = $PostgresUsername
            readyResult = $postgresReadyResult
            stateBeforeCleanup = $postgresStateBeforeCleanup
            logPath = $postgresLogPath
            logSaved = $postgresLogsSaved
            removed = $postgresRemoved
        }
        docker = [ordered]@{
            networkName = $networkName
            networkRemoved = $networkRemoved
        }
    }

    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8

    Write-Step "Report written to $reportPath"
    Write-Step "Postgres logs written to $postgresLogPath"
    Write-Step "Backend logs written to $backendLogPath"

    if ($KeepContainers) {
        Write-Step "Temporary containers were kept for inspection."
    } else {
        Write-Step "Temporary containers were removed."
    }
}
