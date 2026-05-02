param(
    [string]$BackendBaseUrl = "http://localhost:18080/api",
    [Parameter(Mandatory = $true)]
    [string]$Email,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$DisplayName = "Notification Smoke",
    [string]$Timezone = "Europe/Moscow",
    [ValidateSet("ru", "en")]
    [string]$Language = "ru",
    [string]$FolderName = "Notification smoke",
    [string]$GoalName = "Owned runtime verification",
    [string]$TaskTitlePrefix = "Smoke push",
    [int]$PlannedLeadMinutes = 3,
    [int]$ReminderOffsetMinutes = 1,
    [int]$DueLeadMinutes = 30,
    [int]$DeliveryTimeoutSeconds = 180,
    [string]$PsqlCommand = "psql",
    [switch]$RegisterIfMissing,
    [switch]$SkipDeviceCheck,
    [switch]$SkipWaitForDelivery
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$message) {
    Write-Host "[notification-smoke] $message"
}

function Get-HttpStatusCode($exception) {
    if ($null -eq $exception) {
        return $null
    }

    $response = $exception.Exception.Response
    if ($null -eq $response) {
        return $null
    }

    try {
        return [int]$response.StatusCode
    } catch {
        return $null
    }
}

function Read-HttpErrorBody($exception) {
    $response = $exception.Exception.Response
    if ($null -eq $response) {
        return $null
    }

    try {
        $stream = $response.GetResponseStream()
        if ($null -eq $stream) {
            return $null
        }

        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    } catch {
        return $null
    }
}

function Invoke-Api(
    [string]$Method,
    [string]$Path,
    $Body,
    [string]$AccessToken
) {
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
        $headers["Authorization"] = "Bearer $AccessToken"
    }

    $uri = "$script:NormalizedBackendBaseUrl$Path"
    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $invokeParams["ContentType"] = "application/json"
        $invokeParams["Body"] = $Body | ConvertTo-Json -Depth 8 -Compress
    }

    return Invoke-RestMethod @invokeParams
}

function Escape-SqlLiteral([string]$value) {
    if ($null -eq $value) {
        return ""
    }

    return $value.Replace("'", "''")
}

function Resolve-PsqlExecutable([string]$commandName) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Parse-PostgresJdbcUrl([string]$jdbcUrl) {
    if ($jdbcUrl -notmatch '^jdbc:postgresql://(?<host>[^/:?]+)(:(?<port>\d+))?/(?<database>[^?]+)') {
        throw "ROCKETFLOW_DB_URL must be a jdbc:postgresql://... URL. Current value: $jdbcUrl"
    }

    return [pscustomobject]@{
        Host     = $matches.host
        Port     = $(if ($matches.port) { [int]$matches.port } else { 5432 })
        Database = $matches.database
    }
}

function Invoke-PsqlJson([string]$sql) {
    if ($null -eq $script:PsqlExecutable) {
        throw "psql was not found. Install it or pass -PsqlCommand with a valid executable path."
    }

    $previousPgPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $script:DbPassword
        $output = & $script:PsqlExecutable `
            -X `
            -q `
            -t `
            -A `
            -h $script:DbHost `
            -p $script:DbPort `
            -U $script:DbUsername `
            -d $script:DbName `
            -c $sql 2>&1

        if ($LASTEXITCODE -ne 0) {
            $joinedOutput = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "psql query failed: $joinedOutput"
        }

        $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        return $text | ConvertFrom-Json
    } finally {
        if ($null -eq $previousPgPassword) {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        } else {
            $env:PGPASSWORD = $previousPgPassword
        }
    }
}

function Get-LatestSmokeLog() {
    if (-not (Test-Path -LiteralPath $script:SmokeDir)) {
        return $null
    }

    return Get-ChildItem -Path $script:SmokeDir -Filter "backend-*.log" -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-LogTail([string]$path, [int]$lines = 40) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        return @()
    }

    return @(Get-Content -LiteralPath $path -Tail $lines)
}

function Ensure-Folder([string]$accessToken, [string]$name) {
    $folders = Invoke-Api -Method "GET" -Path "/folders" -Body $null -AccessToken $accessToken
    $existing = @($folders.items) |
        Where-Object { $_.name -eq $name -and -not $_.archived } |
        Select-Object -First 1
    if ($null -ne $existing) {
        Write-Step "Reusing folder '$name' ($($existing.id))"
        return $existing
    }

    Write-Step "Creating folder '$name'"
    return Invoke-Api -Method "POST" -Path "/folders" -AccessToken $accessToken -Body @{
        name        = $name
        description = "Repeatable notification smoke tasks"
    }
}

function Ensure-Goal([string]$accessToken, [string]$folderId, [string]$name) {
    $goals = Invoke-Api -Method "GET" -Path "/folders/$folderId/goals" -Body $null -AccessToken $accessToken
    $existing = @($goals.items) |
        Where-Object { $_.name -eq $name -and -not $_.archived } |
        Select-Object -First 1
    if ($null -ne $existing) {
        Write-Step "Reusing goal '$name' ($($existing.id))"
        return $existing
    }

    Write-Step "Creating goal '$name'"
    return Invoke-Api -Method "POST" -Path "/folders/$folderId/goals" -AccessToken $accessToken -Body @{
        name        = $name
        description = "Owned-runtime reminder -> push -> tap verification"
    }
}

function Get-ActiveDeviceRegistrations([string]$userId) {
    $userIdLiteral = Escape-SqlLiteral $userId
    $sql = @"
select coalesce(json_agg(row_to_json(device_rows) order by device_rows."updatedAt" desc), '[]'::json)
from (
    select
        id,
        device_name as "deviceName",
        platform,
        push_token as "pushToken",
        installation_id as "installationId",
        created_at as "createdAt",
        updated_at as "updatedAt"
    from device_registrations
    where user_id = '$userIdLiteral'::uuid
      and active = true
) device_rows;
"@
    $rows = Invoke-PsqlJson $sql
    return @($rows)
}

function Get-LatestNotificationDelivery([string]$taskId) {
    $taskIdLiteral = Escape-SqlLiteral $taskId
    $sql = @"
select row_to_json(delivery_row)
from (
    select
        id,
        task_id as "taskId",
        reminder_rule_id as "reminderRuleId",
        device_registration_id as "deviceRegistrationId",
        scheduled_at as "scheduledAt",
        attempted_at as "attemptedAt",
        status,
        provider_response as "providerResponse",
        created_at as "createdAt"
    from notification_deliveries
    where task_id = '$taskIdLiteral'::uuid
    order by created_at desc
    limit 1
) delivery_row;
"@
    return Invoke-PsqlJson $sql
}

if ($PlannedLeadMinutes -le $ReminderOffsetMinutes) {
    throw "PlannedLeadMinutes must be greater than ReminderOffsetMinutes so the reminder lands in the future."
}

if ($DueLeadMinutes -lt $PlannedLeadMinutes) {
    throw "DueLeadMinutes must be greater than or equal to PlannedLeadMinutes."
}

$NormalizedBackendBaseUrl = $BackendBaseUrl.TrimEnd("/")
if (-not $NormalizedBackendBaseUrl.EndsWith("/api")) {
    throw "BackendBaseUrl must point at the backend API root, for example http://localhost:18080/api"
}

$BackendHealthUrl = "$($NormalizedBackendBaseUrl.Substring(0, $NormalizedBackendBaseUrl.Length - 4))/actuator/health"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SmokeDir = Join-Path $RepoRoot "tmp\notification-smoke"
New-Item -ItemType Directory -Force -Path $SmokeDir | Out-Null

$needsDatabaseAccess = (-not $SkipDeviceCheck) -or (-not $SkipWaitForDelivery)
if ($needsDatabaseAccess) {
    $DbUrl = [Environment]::GetEnvironmentVariable("ROCKETFLOW_DB_URL")
    $DbUsername = [Environment]::GetEnvironmentVariable("ROCKETFLOW_DB_USERNAME")
    $DbPassword = [Environment]::GetEnvironmentVariable("ROCKETFLOW_DB_PASSWORD")

    if ([string]::IsNullOrWhiteSpace($DbUrl) -or [string]::IsNullOrWhiteSpace($DbUsername) -or [string]::IsNullOrWhiteSpace($DbPassword)) {
        throw "ROCKETFLOW_DB_URL, ROCKETFLOW_DB_USERNAME, and ROCKETFLOW_DB_PASSWORD must be present when device checks or delivery waiting are enabled."
    }

    $jdbcParts = Parse-PostgresJdbcUrl $DbUrl
    $DbHost = $jdbcParts.Host
    $DbPort = $jdbcParts.Port
    $DbName = $jdbcParts.Database
    $PsqlExecutable = Resolve-PsqlExecutable $PsqlCommand

    if ($null -eq $PsqlExecutable) {
        throw "psql was not found. Install it or pass -PsqlCommand with a valid executable path."
    }
}

Write-Step "Checking backend health at $BackendHealthUrl"
try {
    $health = Invoke-RestMethod -Uri $BackendHealthUrl -TimeoutSec 10 -ErrorAction Stop
} catch {
    throw "Backend health check failed at $BackendHealthUrl. Start the owned backend runtime first."
}

if ($health.status -ne "UP") {
    throw "Backend health endpoint returned '$($health.status)' instead of 'UP'."
}

Write-Step "Logging in as $Email"
$loginBody = @{
    email    = $Email
    password = $Password
}

$authResponse = $null
$loginFailure = $null
try {
    $authResponse = Invoke-Api -Method "POST" -Path "/auth/login" -Body $loginBody -AccessToken $null
} catch {
    $loginFailure = $_
}

if ($null -eq $authResponse) {
    if (-not $RegisterIfMissing) {
        $statusCode = Get-HttpStatusCode $loginFailure
        $errorBody = Read-HttpErrorBody $loginFailure
        throw "Login failed for $Email (status: $statusCode). If this is a fresh smoke user, rerun with -RegisterIfMissing. Backend response: $errorBody"
    }

    Write-Step "Login failed; attempting to register the smoke user first"
    try {
        Invoke-Api -Method "POST" -Path "/auth/register" -Body @{
            email       = $Email
            password    = $Password
            displayName = $DisplayName
            timezone    = $Timezone
            language    = $Language
        } -AccessToken $null | Out-Null
    } catch {
        $registerStatus = Get-HttpStatusCode $_
        $registerBody = Read-HttpErrorBody $_
        throw "Smoke-user registration failed for $Email (status: $registerStatus). Backend response: $registerBody"
    }

    $authResponse = Invoke-Api -Method "POST" -Path "/auth/login" -Body $loginBody -AccessToken $null
}

$accessToken = $authResponse.tokens.accessToken
$userId = $authResponse.user.id
Write-Step "Authenticated smoke user $Email ($userId)"

$settings = Invoke-Api -Method "GET" -Path "/me/settings" -Body $null -AccessToken $accessToken
if (-not $settings.notificationsEnabled) {
    throw "Smoke user $Email currently has notifications disabled in /api/me/settings. Enable them before creating a smoke reminder."
}

$activeDevices = @()
if (-not $SkipDeviceCheck) {
    $activeDevices = Get-ActiveDeviceRegistrations $userId
    if ($activeDevices.Count -eq 0) {
        throw "No active device registration exists for $Email. Log in on Android first, confirm a real token, and rerun this script."
    }

    Write-Step "Found $($activeDevices.Count) active device registration(s) for $Email"
} else {
    Write-Step "Skipping active-device verification"
}

$folder = Ensure-Folder -accessToken $accessToken -name $FolderName
$goal = Ensure-Goal -accessToken $accessToken -folderId $folder.id -name $GoalName

$now = [DateTimeOffset]::UtcNow
$plannedAt = $now.AddMinutes($PlannedLeadMinutes)
$dueAt = $now.AddMinutes($DueLeadMinutes)
$expectedReminderAt = $plannedAt.AddMinutes(-$ReminderOffsetMinutes)
$taskTitle = "{0} {1}" -f $TaskTitlePrefix, (Get-Date -Format "yyyyMMdd-HHmmss")

Write-Step "Creating smoke task '$taskTitle' with planned time $($plannedAt.ToString('o'))"
$task = Invoke-Api -Method "POST" -Path "/goals/$($goal.id)/tasks" -AccessToken $accessToken -Body @{
    title       = $taskTitle
    description = "Owned runtime notification smoke created by scripts/Invoke-NotificationSmokeTask.ps1"
    type        = "green"
    priority    = 6
    status      = "todo"
    plannedTime = $plannedAt.ToString("o")
    dueTime     = $dueAt.ToString("o")
    tagIds      = @()
}

Write-Step "Attaching one reminder rule offset $ReminderOffsetMinutes minute(s) before planned time"
$reminderResponse = Invoke-Api -Method "PUT" -Path "/tasks/$($task.id)/reminders" -AccessToken $accessToken -Body @{
    reminders = @(
        @{
            mode          = "before_planned_time"
            offsetMinutes = $ReminderOffsetMinutes
            active        = $true
        }
    )
}

$delivery = $null
if (-not $SkipWaitForDelivery) {
    Write-Step "Waiting up to $DeliveryTimeoutSeconds second(s) for notification_deliveries evidence"
    $deadline = (Get-Date).AddSeconds($DeliveryTimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        $delivery = Get-LatestNotificationDelivery $task.id
        if ($null -ne $delivery) {
            Write-Step "Delivery row observed with status '$($delivery.status)'"
            break
        }
    } while ((Get-Date) -lt $deadline)

    if ($null -eq $delivery) {
        Write-Step "Timed out before notification_deliveries produced a row for task $($task.id)"
    }
} else {
    Write-Step "Skipping delivery wait"
}

$latestLog = Get-LatestSmokeLog
$reportTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $SmokeDir "smoke-task-$reportTimestamp.json"
$report = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    backend = [ordered]@{
        apiBaseUrl = $NormalizedBackendBaseUrl
        healthUrl  = $BackendHealthUrl
        latestLog  = $(if ($null -ne $latestLog) { $latestLog.FullName } else { $null })
    }
    smokeUser = [ordered]@{
        email = $Email
        id    = $userId
    }
    task = [ordered]@{
        folderId               = $folder.id
        folderName             = $folder.name
        goalId                 = $goal.id
        goalName               = $goal.name
        id                     = $task.id
        title                  = $task.title
        plannedTime            = $task.plannedTime
        dueTime                = $task.dueTime
        reminderOffsetMinutes  = $ReminderOffsetMinutes
        expectedReminderAt     = $expectedReminderAt.ToString("o")
        reminderResponse       = $reminderResponse
    }
    activeDeviceRegistrations = @($activeDevices)
    latestDelivery = $delivery
    latestBackendLogTail = @(
        $(if ($null -ne $latestLog) { Get-LogTail -path $latestLog.FullName -lines 40 } else { @() })
    )
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath

Write-Step "Smoke task report written to $reportPath"
Write-Step "Background Android before $($expectedReminderAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')) and watch for the notification."
$report | ConvertTo-Json -Depth 8
