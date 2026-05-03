<#
.SYNOPSIS
Runs a two-user RocketFlow sharing smoke against a local backend and database.

.DESCRIPTION
Creates two test accounts, creates private and shared folders/goals/tasks for
the owner, shares one folder, one goal, and one standalone task with the
collaborator, verifies that unshared resources are hidden, and verifies that
task status changes persist through the backend for both users.
#>

param(
    [string]$BaseUrl = "http://localhost:8080/api",
    [string]$OwnerEmail = "styleguch@gmail.com",
    [string]$CollaboratorEmail = "rocketflow.collab@example.test",
    [string]$Password = "ValidationPass123",
    [switch]$ResetAccounts,
    [int]$PostgresPort = 55432,
    [string]$PostgresDatabase = "rocketflow",
    [string]$PostgresBin = ""
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[two-user-sharing-smoke] $Message"
}

function Resolve-PostgresBin([string]$ExplicitBin) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitBin)) {
        return (Resolve-Path -LiteralPath $ExplicitBin).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($env:POSTGRES_BIN)) {
        return (Resolve-Path -LiteralPath $env:POSTGRES_BIN).Path
    }
    $fromPath = Get-Command pg_ctl.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        return Split-Path -Parent $fromPath.Source
    }
    $candidate = Get-ChildItem -LiteralPath "C:\Program Files\PostgreSQL" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "bin" } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ "psql.exe") } |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw "Could not find PostgreSQL tools. Pass -PostgresBin or set POSTGRES_BIN."
    }
    return $candidate
}

function ConvertTo-SqlLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Reset-TestAccounts {
    param([string]$PgBin)

    $psql = Join-Path $PgBin "psql.exe"
    $emails = @($OwnerEmail, $CollaboratorEmail) | ForEach-Object { ConvertTo-SqlLiteral $_ }
    $emailList = $emails -join ","
    Write-Step "Deleting existing test accounts from $PostgresDatabase on port $PostgresPort."
    & $psql -h 127.0.0.1 -p $PostgresPort -U postgres -d $PostgresDatabase -c "delete from users where lower(email) in (lower($($emails[0])), lower($($emails[1])));" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to reset smoke accounts."
    }
}

function Invoke-Json {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int[]]$Expected = @(200),
        [switch]$ReturnRaw
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }
    $uri = "$BaseUrl$Path"
    $json = if ($null -eq $Body) { $null } else { $Body | ConvertTo-Json -Depth 20 }

    try {
        $response = if ($null -eq $json) {
            Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -TimeoutSec 20
        } else {
            Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec 20
        }
        if ($Expected -notcontains [int]$response.StatusCode) {
            throw "Expected HTTP $($Expected -join '/') from $Method $Path, got $($response.StatusCode): $($response.Content)"
        }
        if ($ReturnRaw) {
            return $response
        }
        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            return $null
        }
        return $response.Content | ConvertFrom-Json
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($Expected -contains [int]$status) {
            return $null
        }
        throw
    }
}

function Register-And-Login {
    param([string]$Email, [string]$DisplayName)

    Write-Step "Ensuring account $Email."
    Invoke-Json -Method Post -Path "/auth/register" -Expected @(201, 409) -Body @{
        email = $Email
        password = $Password
        displayName = $DisplayName
        timezone = "Europe/Moscow"
        language = "ru"
    } | Out-Null
    $login = Invoke-Json -Method Post -Path "/auth/login" -Body @{
        email = $Email
        password = $Password
    }
    return $login.tokens.accessToken
}

function New-Folder([string]$Token, [string]$Name, [string]$Description) {
    return Invoke-Json -Method Post -Path "/folders" -Expected @(201) -Token $Token -Body @{
        name = $Name
        description = $Description
    }
}

function New-Goal([string]$Token, [string]$FolderId, [string]$Name) {
    return Invoke-Json -Method Post -Path "/folders/$FolderId/goals" -Expected @(201) -Token $Token -Body @{
        name = $Name
        description = "Smoke goal notes"
    }
}

function New-Task([string]$Token, [string]$GoalId, [string]$Title, [string]$Type, [int]$Priority) {
    return Invoke-Json -Method Post -Path "/goals/$GoalId/tasks" -Expected @(201) -Token $Token -Body @{
        title = $Title
        description = "Task description"
        type = $Type
        priority = $Priority
        status = "todo"
        plannedTime = "2026-05-01T09:00:00Z"
        dueTime = "2026-05-02T18:00:00Z"
    }
}

function Share-And-Accept([string]$OwnerToken, [string]$CollaboratorToken, [string]$Path) {
    $invitation = Invoke-Json -Method Post -Path $Path -Expected @(201) -Token $OwnerToken -Body @{
        email = $CollaboratorEmail
    }
    Invoke-Json -Method Post -Path "/shares/invitations/$($invitation.id)/accept" -Token $CollaboratorToken | Out-Null
    return $invitation.id
}

function Assert-ContainsOnlyIds([object[]]$Items, [string[]]$ExpectedIds, [string]$Label) {
    $actual = @($Items | ForEach-Object { "$($_.id)" } | Sort-Object)
    $expected = @($ExpectedIds | Sort-Object)
    if (($actual -join ",") -ne ($expected -join ",")) {
        throw "$Label mismatch. Expected [$($expected -join ', ')], got [$($actual -join ', ')]."
    }
}

function Assert-NotFound([string]$Token, [string]$Path) {
    Invoke-Json -Method Get -Path $Path -Token $Token -Expected @(404) | Out-Null
}

$health = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/health" -TimeoutSec 5
if ($health.StatusCode -ne 200) {
    throw "Backend is not healthy at $BaseUrl."
}

if ($ResetAccounts) {
    Reset-TestAccounts -PgBin (Resolve-PostgresBin -ExplicitBin $PostgresBin)
}

$ownerToken = Register-And-Login -Email $OwnerEmail -DisplayName "Styleguch Owner"
$collaboratorToken = Register-And-Login -Email $CollaboratorEmail -DisplayName "Sharing Collaborator"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Write-Step "Creating owner data set $stamp."

$folderShared = New-Folder -Token $ownerToken -Name "Smoke Shared Folder $stamp" -Description "Shared folder notes"
$folderPrivate = New-Folder -Token $ownerToken -Name "Smoke Private Folder $stamp" -Description "Private folder notes"
$folderForGoal = New-Folder -Token $ownerToken -Name "Smoke Goal Scope Folder $stamp" -Description "Goal scope notes"
$folderForTask = New-Folder -Token $ownerToken -Name "Smoke Task Scope Folder $stamp" -Description "Task scope notes"

$goalInSharedFolder = New-Goal -Token $ownerToken -FolderId $folderShared.id -Name "Smoke Goal In Shared Folder $stamp"
$taskInSharedFolder = New-Task -Token $ownerToken -GoalId $goalInSharedFolder.id -Title "Smoke Task Via Folder $stamp" -Type "green" -Priority 7
$privateGoal = New-Goal -Token $ownerToken -FolderId $folderPrivate.id -Name "Smoke Private Goal $stamp"
$privateTask = New-Task -Token $ownerToken -GoalId $privateGoal.id -Title "Smoke Private Task $stamp" -Type "red" -Priority 4

$sharedGoal = New-Goal -Token $ownerToken -FolderId $folderForGoal.id -Name "Smoke Direct Goal $stamp"
$siblingGoal = New-Goal -Token $ownerToken -FolderId $folderForGoal.id -Name "Smoke Sibling Goal $stamp"
$taskInSharedGoal = New-Task -Token $ownerToken -GoalId $sharedGoal.id -Title "Smoke Task Via Goal $stamp" -Type "green" -Priority 6
$siblingGoalTask = New-Task -Token $ownerToken -GoalId $siblingGoal.id -Title "Smoke Sibling Goal Task $stamp" -Type "red" -Priority 5

$taskShareGoal = New-Goal -Token $ownerToken -FolderId $folderForTask.id -Name "Smoke Direct Task Goal $stamp"
$sharedTask = New-Task -Token $ownerToken -GoalId $taskShareGoal.id -Title "Smoke Direct Shared Task $stamp" -Type "green" -Priority 8
$siblingTask = New-Task -Token $ownerToken -GoalId $taskShareGoal.id -Title "Smoke Unshared Sibling Task $stamp" -Type "red" -Priority 3

Write-Step "Sharing selected folder, goal, and task."
Share-And-Accept -OwnerToken $ownerToken -CollaboratorToken $collaboratorToken -Path "/folders/$($folderShared.id)/share" | Out-Null
Share-And-Accept -OwnerToken $ownerToken -CollaboratorToken $collaboratorToken -Path "/goals/$($sharedGoal.id)/share" | Out-Null
Share-And-Accept -OwnerToken $ownerToken -CollaboratorToken $collaboratorToken -Path "/tasks/$($sharedTask.id)/share" | Out-Null

$resources = Invoke-Json -Method Get -Path "/shares/resources" -Token $collaboratorToken
Assert-ContainsOnlyIds -Items @($resources.folders) -ExpectedIds @("$($folderShared.id)") -Label "Shared folders"
Assert-ContainsOnlyIds -Items @($resources.goals) -ExpectedIds @("$($goalInSharedFolder.id)", "$($sharedGoal.id)") -Label "Shared goals"
Assert-ContainsOnlyIds -Items @($resources.tasks) -ExpectedIds @("$($taskInSharedFolder.id)", "$($taskInSharedGoal.id)", "$($sharedTask.id)") -Label "Shared tasks"

Write-Step "Verifying private resources stay hidden."
Assert-NotFound -Token $collaboratorToken -Path "/folders/$($folderPrivate.id)/goals"
Assert-NotFound -Token $collaboratorToken -Path "/goals/$($privateGoal.id)"
Assert-NotFound -Token $collaboratorToken -Path "/tasks/$($privateTask.id)"
Assert-NotFound -Token $collaboratorToken -Path "/goals/$($siblingGoal.id)"
Assert-NotFound -Token $collaboratorToken -Path "/tasks/$($siblingGoalTask.id)"
Assert-NotFound -Token $collaboratorToken -Path "/goals/$($taskShareGoal.id)"
Assert-NotFound -Token $collaboratorToken -Path "/tasks/$($siblingTask.id)"

Write-Step "Verifying collaborator can change only shared task status."
$collaboratorTask = Invoke-Json -Method Get -Path "/tasks/$($sharedTask.id)" -Token $collaboratorToken
$statusUpdate = Invoke-Json -Method Patch -Path "/tasks/$($sharedTask.id)" -Token $collaboratorToken -Body @{
    title = $collaboratorTask.title
    description = $collaboratorTask.description
    type = $collaboratorTask.type
    priority = $collaboratorTask.priority
    status = "done"
    plannedTime = $collaboratorTask.plannedTime
    dueTime = $collaboratorTask.dueTime
    archived = $collaboratorTask.archived
    tagIds = @($collaboratorTask.tags | ForEach-Object { $_.id })
    version = $collaboratorTask.version
}
if ($statusUpdate.status -ne "done") {
    throw "Collaborator status update did not return done."
}
$ownerReadsDone = Invoke-Json -Method Get -Path "/tasks/$($sharedTask.id)" -Token $ownerToken
if ($ownerReadsDone.status -ne "done") {
    throw "Owner did not read collaborator status change."
}

$badEdit = @{
    title = "$($ownerReadsDone.title) renamed"
    description = $ownerReadsDone.description
    type = $ownerReadsDone.type
    priority = $ownerReadsDone.priority
    status = "in_progress"
    plannedTime = $ownerReadsDone.plannedTime
    dueTime = $ownerReadsDone.dueTime
    archived = $ownerReadsDone.archived
    tagIds = @($ownerReadsDone.tags | ForEach-Object { $_.id })
    version = $ownerReadsDone.version
}
Invoke-Json -Method Patch -Path "/tasks/$($sharedTask.id)" -Token $collaboratorToken -Expected @(404) -Body $badEdit | Out-Null

$ownerReset = Invoke-Json -Method Patch -Path "/tasks/$($sharedTask.id)" -Token $ownerToken -Body @{
    title = $ownerReadsDone.title
    description = $ownerReadsDone.description
    type = $ownerReadsDone.type
    priority = $ownerReadsDone.priority
    status = "in_progress"
    plannedTime = $ownerReadsDone.plannedTime
    dueTime = $ownerReadsDone.dueTime
    archived = $ownerReadsDone.archived
    tagIds = @($ownerReadsDone.tags | ForEach-Object { $_.id })
    version = $ownerReadsDone.version
}
$collaboratorReadsReset = Invoke-Json -Method Get -Path "/tasks/$($sharedTask.id)" -Token $collaboratorToken
if ($ownerReset.status -ne "in_progress" -or $collaboratorReadsReset.status -ne "in_progress") {
    throw "Owner status update did not sync back to collaborator."
}

$summary = [pscustomobject]@{
    Status = "OK"
    BaseUrl = $BaseUrl
    OwnerEmail = $OwnerEmail
    CollaboratorEmail = $CollaboratorEmail
    Password = $Password
    SharedFolder = $folderShared.name
    SharedGoal = $sharedGoal.name
    SharedTask = $sharedTask.title
    PrivateFolderHidden = $folderPrivate.name
    PrivateGoalHidden = $privateGoal.name
    PrivateTaskHidden = $privateTask.title
    FinalSharedTaskStatusForOwner = $ownerReset.status
    FinalSharedTaskStatusForCollaborator = $collaboratorReadsReset.status
}

$summary | Format-List | Out-String | Write-Host
