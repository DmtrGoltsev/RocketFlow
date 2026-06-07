[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias("Host")]
    [string]$SshHost = $env:ROCKETFLOW_PROD_BACKUP_HOST,

    [Alias("User")]
    [string]$SshUser = $env:ROCKETFLOW_PROD_BACKUP_USER,

    [Alias("SshKey")]
    [string]$SshKeyPath = $env:ROCKETFLOW_PROD_BACKUP_SSH_KEY_PATH,

    [string]$RemoteBackupDir = $env:ROCKETFLOW_PROD_BACKUP_REMOTE_DIR,
    [string]$RemotePattern = $env:ROCKETFLOW_PROD_BACKUP_REMOTE_PATTERN,
    [string]$LocalOutputRoot = $env:ROCKETFLOW_PROD_BACKUP_LOCAL_ROOT,
    [string]$RemoteBackupCommand = $env:ROCKETFLOW_PROD_BACKUP_COMMAND,

    [switch]$LatestOnly,
    [switch]$RunServerBackup,
    [switch]$SkipPgRestoreListCheck,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RemoteBackupDir)) {
    $RemoteBackupDir = "/var/backups/rocketflow"
}

if ([string]::IsNullOrWhiteSpace($RemotePattern)) {
    $RemotePattern = "rocketflow_prod_*.dump"
}

if ([string]::IsNullOrWhiteSpace($LocalOutputRoot)) {
    $LocalOutputRoot = "tmp/prod-db-backups"
}

if ([string]::IsNullOrWhiteSpace($RemoteBackupCommand)) {
    $RemoteBackupCommand = "/usr/local/sbin/rocketflow-backup.sh"
}

function Write-Step([string]$Message) {
    Write-Host "[prod-backup-download] $Message"
}

function Assert-NotBlank([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required $Name. Pass it as a parameter or set the matching ROCKETFLOW_PROD_BACKUP_* environment variable."
    }
}

function Assert-MatchesSafePattern([string]$Name, [string]$Value, [string]$Pattern, [string]$Description) {
    if ($Value -notmatch $Pattern) {
        throw "Unsafe $Name. Expected $Description."
    }
}

function Assert-NoLeadingDash([string]$Name, [string]$Value) {
    if ($Value.StartsWith("-", [System.StringComparison]::Ordinal)) {
        throw "Unsafe $Name. Values must not start with '-'."
    }
}

function Assert-NoWhitespaceOrControl([string]$Name, [string]$Value) {
    if ($Value -match '[\s\p{Cc}]') {
        throw "Unsafe $Name. Values must not contain whitespace or control characters."
    }
}

function Assert-SafeSshUser([string]$Value) {
    Assert-NoLeadingDash -Name "SshUser" -Value $Value
    Assert-NoWhitespaceOrControl -Name "SshUser" -Value $Value
    Assert-MatchesSafePattern -Name "SshUser" -Value $Value -Pattern '^[A-Za-z0-9_][A-Za-z0-9._-]*$' -Description "an SSH user name using letters, digits, underscore, dot, or dash"
}

function Assert-SafeSshHost([string]$Value) {
    Assert-NoLeadingDash -Name "SshHost" -Value $Value
    Assert-NoWhitespaceOrControl -Name "SshHost" -Value $Value
    Assert-MatchesSafePattern -Name "SshHost" -Value $Value -Pattern '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$|^[A-Za-z0-9]$' -Description "a DNS name or IPv4 address using letters, digits, dot, or dash"
}

function Assert-SafeRemoteDirectory([string]$Value) {
    Assert-NoWhitespaceOrControl -Name "RemoteBackupDir" -Value $Value
    Assert-MatchesSafePattern -Name "RemoteBackupDir" -Value $Value -Pattern '^/[A-Za-z0-9._/+=%-]+$' -Description "an absolute Unix path without shell metacharacters"
}

function Assert-SafeRemotePattern([string]$Value) {
    Assert-NoLeadingDash -Name "RemotePattern" -Value $Value
    Assert-NoWhitespaceOrControl -Name "RemotePattern" -Value $Value
    Assert-MatchesSafePattern -Name "RemotePattern" -Value $Value -Pattern '^[A-Za-z0-9._+=%*-]+$' -Description "a file-name pattern without path separators or shell metacharacters other than '*'"
}

function Assert-SafeRemoteBackupCommand([string]$Value) {
    Assert-NoWhitespaceOrControl -Name "RemoteBackupCommand" -Value $Value
    Assert-MatchesSafePattern -Name "RemoteBackupCommand" -Value $Value -Pattern '^/[A-Za-z0-9._/+=%-]+$' -Description "an absolute command path without arguments or shell metacharacters"
}

function Assert-SafeRemoteFileName([string]$Value) {
    Assert-NoLeadingDash -Name "remote backup filename" -Value $Value
    Assert-NoWhitespaceOrControl -Name "remote backup filename" -Value $Value
    Assert-MatchesSafePattern -Name "remote backup filename" -Value $Value -Pattern '^[A-Za-z0-9._+=%-]+$' -Description "a file name without path separators or shell metacharacters"
}

function Assert-SafeLocalOutputRoot([string]$Value) {
    if ($Value -match '[\p{Cc}]') {
        throw "Unsafe LocalOutputRoot. Values must not contain control characters."
    }
}

function Test-ToolAvailable([string]$CommandName) {
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function ConvertTo-ShellSingleQuoted([string]$Value) {
    $quote = [string][char]39
    $doubleQuote = [string][char]34
    $escapedQuote = $quote + $doubleQuote + $quote + $doubleQuote + $quote
    return $quote + $Value.Replace($quote, $escapedQuote) + $quote
}

function ConvertTo-DisplayCommand([string]$FilePath, [string[]]$ArgumentList) {
    $displayArgs = @(
        $ArgumentList |
            ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + $_.Replace('"', '\"') + '"'
                } else {
                    $_
                }
            }
    )

    return (@($FilePath) + $displayArgs) -join " "
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

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [switch]$NoOutput
    )

    $displayCommand = ConvertTo-DisplayCommand -FilePath $FilePath -ArgumentList $ArgumentList

    if ($DryRun) {
        Write-Step "DRY RUN: would run: $displayCommand"
        return ""
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $text = Convert-OutputToText -Output @($output)

    if ($exitCode -ne 0) {
        $details = if ([string]::IsNullOrWhiteSpace($text)) {
            "$FilePath exited with code $exitCode."
        } else {
            $text
        }

        throw "Command failed: $displayCommand`n$details"
    }

    if (-not $NoOutput -and -not [string]::IsNullOrWhiteSpace($text)) {
        Write-Verbose $text
    }

    return $text
}

function Join-RemoteUnixPath([string]$Directory, [string]$FileName) {
    return $Directory.TrimEnd("/") + "/" + $FileName
}

function Assert-SafeScpRemotePath([string]$RemoteFilePath) {
    if ($RemoteFilePath -notmatch '^[A-Za-z0-9_./+=%-]+$') {
        throw "Refusing to pass remote path to scp because it contains characters outside the safe path set: $RemoteFilePath"
    }
}

function Get-SshBaseArgs {
    $args = @("-o", "BatchMode=yes")

    if (-not [string]::IsNullOrWhiteSpace($SshKeyPath)) {
        $args += @("-o", "IdentitiesOnly=yes", "-i", $SshKeyPath)
    }

    return $args
}

function Get-RemoteBackupList([string]$RemoteTarget, [string[]]$SshBaseArgs) {
    $quotedDir = ConvertTo-ShellSingleQuoted -Value $RemoteBackupDir
    $quotedPattern = ConvertTo-ShellSingleQuoted -Value $RemotePattern
    $remoteListCommand = "find $quotedDir -maxdepth 1 -type f -name $quotedPattern -printf '%T@\t%s\t%f\n' | sort -nr"
    $output = Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($SshBaseArgs + @($RemoteTarget, $remoteListCommand))

    $entries = @(
        $output -split "\r?\n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $parts = $_ -split "`t", 3
                if ($parts.Count -ne 3) {
                    throw "Could not parse remote backup listing line: $_"
                }

                [pscustomobject]@{
                    ModifiedEpoch = [double]$parts[0]
                    SizeBytes     = [int64]$parts[1]
                    FileName      = $parts[2]
                }
            }
    )

    if ($entries.Count -eq 0) {
        throw "No remote backups matched $RemotePattern in $RemoteBackupDir on $RemoteTarget."
    }

    return $entries
}

function Get-RemoteSha256([string]$RemoteTarget, [string[]]$SshBaseArgs, [string]$RemoteFilePath) {
    $quotedRemoteFile = ConvertTo-ShellSingleQuoted -Value $RemoteFilePath
    $output = Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($SshBaseArgs + @($RemoteTarget, "sha256sum -- $quotedRemoteFile"))

    if ($output -notmatch "^(?<hash>[a-fA-F0-9]{64})\s+") {
        throw "Could not parse sha256sum output for $RemoteFilePath."
    }

    return $Matches["hash"].ToLowerInvariant()
}

function Invoke-PgRestoreListCheck([string]$DumpPath) {
    if ($SkipPgRestoreListCheck) {
        Write-Step "Skipping pg_restore -l readability check for $DumpPath."
        return
    }

    if (-not (Test-ToolAvailable "pg_restore")) {
        Write-Step "pg_restore was not found on PATH; skipping archive readability check."
        return
    }

    Invoke-ExternalCommand -FilePath "pg_restore" -ArgumentList @("-l", $DumpPath) -NoOutput | Out-Null
    Write-Step "pg_restore -l readability check passed for $DumpPath."
}

Assert-NotBlank -Name "host" -Value $SshHost
Assert-NotBlank -Name "user" -Value $SshUser
Assert-NotBlank -Name "remote backup directory" -Value $RemoteBackupDir
Assert-NotBlank -Name "remote pattern" -Value $RemotePattern
Assert-NotBlank -Name "local output root" -Value $LocalOutputRoot
Assert-NotBlank -Name "remote backup command" -Value $RemoteBackupCommand

Assert-SafeSshHost -Value $SshHost
Assert-SafeSshUser -Value $SshUser
Assert-SafeRemoteDirectory -Value $RemoteBackupDir
Assert-SafeRemotePattern -Value $RemotePattern
Assert-SafeRemoteBackupCommand -Value $RemoteBackupCommand
Assert-SafeLocalOutputRoot -Value $LocalOutputRoot

if (-not $DryRun) {
    if (-not (Test-ToolAvailable "ssh")) {
        throw "ssh was not found on PATH. Install OpenSSH client or add it to PATH."
    }

    if (-not (Test-ToolAvailable "scp")) {
        throw "scp was not found on PATH. Install OpenSSH client or add it to PATH."
    }

    if (-not [string]::IsNullOrWhiteSpace($SshKeyPath) -and -not (Test-Path -LiteralPath $SshKeyPath)) {
        throw "SSH key path does not exist: $SshKeyPath"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedLocalRoot = if ([System.IO.Path]::IsPathRooted($LocalOutputRoot)) {
    $LocalOutputRoot
} else {
    Join-Path $repoRoot $LocalOutputRoot
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$downloadDir = Join-Path $resolvedLocalRoot $timestamp
$remoteTarget = "${SshUser}@${SshHost}"
$sshBaseArgs = Get-SshBaseArgs

Write-Step "Remote target: $remoteTarget"
Write-Step "Remote backup directory: $RemoteBackupDir"
Write-Step "Remote pattern: $RemotePattern"
Write-Step "Local download directory: $downloadDir"

if ($RunServerBackup) {
    Write-Warning "RunServerBackup is set. This will run a server-side production backup command through sudo --non-interactive before downloading."
    $serverBackupCommand = "sudo --non-interactive $RemoteBackupCommand"
    Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($sshBaseArgs + @($remoteTarget, $serverBackupCommand)) -NoOutput | Out-Null
}

if ($DryRun) {
    $quotedDir = ConvertTo-ShellSingleQuoted -Value $RemoteBackupDir
    $quotedPattern = ConvertTo-ShellSingleQuoted -Value $RemotePattern
    $remoteListCommand = "find $quotedDir -maxdepth 1 -type f -name $quotedPattern -printf '%T@\t%s\t%f\n' | sort -nr"
    Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($sshBaseArgs + @($remoteTarget, $remoteListCommand)) | Out-Null
    Write-Step "DRY RUN: would select $($(if ($LatestOnly) { "the newest matching backup" } else { "all matching backups, newest first" }))."
    Write-Step "DRY RUN: would create $downloadDir, download dump file(s), write .sha256 sidecar(s), verify local SHA256, and run pg_restore -l when available."
    exit 0
}

New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null

$backups = @(Get-RemoteBackupList -RemoteTarget $remoteTarget -SshBaseArgs $sshBaseArgs)
if ($LatestOnly) {
    $backups = @($backups | Select-Object -First 1)
}

foreach ($backup in $backups) {
    Assert-SafeRemoteFileName -Value $backup.FileName

    $remoteFilePath = Join-RemoteUnixPath -Directory $RemoteBackupDir -FileName $backup.FileName
    $localDumpPath = Join-Path $downloadDir $backup.FileName
    $localShaPath = "$localDumpPath.sha256"

    Write-Step "Selected remote backup: $($backup.FileName) ($($backup.SizeBytes) bytes)"
    $remoteHash = Get-RemoteSha256 -RemoteTarget $remoteTarget -SshBaseArgs $sshBaseArgs -RemoteFilePath $remoteFilePath
    Write-Step "Remote SHA256: $remoteHash"

    Assert-SafeScpRemotePath -RemoteFilePath $remoteFilePath
    Invoke-ExternalCommand -FilePath "scp" -ArgumentList ($sshBaseArgs + @("${remoteTarget}:$remoteFilePath", $localDumpPath)) -NoOutput | Out-Null

    $localHash = (Get-FileHash -LiteralPath $localDumpPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($localHash -ne $remoteHash) {
        throw "SHA256 verification failed for $localDumpPath. Remote=$remoteHash Local=$localHash"
    }

    Set-Content -LiteralPath $localShaPath -Value "$remoteHash  $($backup.FileName)" -Encoding ascii
    Write-Step "Local SHA256 verified and written to $localShaPath."

    Invoke-PgRestoreListCheck -DumpPath $localDumpPath
}

Write-Step "Backup download completed: $downloadDir"
