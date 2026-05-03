<#
.SYNOPSIS
Starts a local RocketFlow backend smoke stack and optionally logs in on Android.

.DESCRIPTION
The script uses a local PostgreSQL installation, starts or reuses a temporary
database on localhost, starts or reuses the Spring backend, creates a smoke
account, verifies API login, and can drive a connected Android emulator through
the login screen.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-AndroidLocalBackendSmoke.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-AndroidLocalBackendSmoke.ps1 -DeviceLogin -ClearAppData

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-AndroidLocalBackendSmoke.ps1 -BuildDebugApk -InstallDebugApk -DeviceLogin -ClearAppData

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-AndroidLocalBackendSmoke.ps1 -Email styleguch@gmail.com -ResetAccount -BuildDebugApk -InstallDebugApk -DeviceLogin -ClearAppData -UseSimpleTestIme
#>

param(
    [string]$Email = "rocketflow.device.smoke@example.test",
    [string]$Password = "ValidationPass123",
    [string]$DisplayName = "Device Smoke",
    [int]$BackendPort = 8080,
    [int]$PostgresPort = 55432,
    [string]$PostgresDatabase = "rocketflow",
    [string]$PostgresUsername = "rocketflow",
    [string]$PostgresPassword = "rocketflow",
    [string]$PostgresDataDir = "",
    [string]$PostgresBin = "",
    [switch]$BuildDebugApk,
    [switch]$InstallDebugApk,
    [switch]$DeviceLogin,
    [switch]$ClearAppData,
    [switch]$UseSimpleTestIme,
    [switch]$ResetAccount,
    [string]$DeviceId = "",
    [switch]$StopAfter,
    [int]$BackendHealthTimeoutSeconds = 150
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[android-local-smoke] $Message"
}

function Resolve-RepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Test-TcpPort([int]$Port) {
    $listeners = @(netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING")
    return $listeners.Count -gt 0
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Exit code: $LASTEXITCODE"
    }
}

function ConvertTo-SqlLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-PostgresBin([string]$ExplicitBin) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitBin)) {
        if (Test-Path -LiteralPath (Join-Path $ExplicitBin "pg_ctl.exe")) {
            return (Resolve-Path -LiteralPath $ExplicitBin).Path
        }
        throw "PostgresBin does not contain pg_ctl.exe: $ExplicitBin"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:POSTGRES_BIN)) {
        if (Test-Path -LiteralPath (Join-Path $env:POSTGRES_BIN "pg_ctl.exe")) {
            return (Resolve-Path -LiteralPath $env:POSTGRES_BIN).Path
        }
    }

    $fromPath = Get-Command pg_ctl.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        return Split-Path -Parent $fromPath.Source
    }

    $programFilesRoot = "C:\Program Files\PostgreSQL"
    if (Test-Path -LiteralPath $programFilesRoot) {
        $candidate = Get-ChildItem -LiteralPath $programFilesRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "bin" } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ "pg_ctl.exe") } |
            Select-Object -First 1

        if ($null -ne $candidate) {
            return $candidate
        }
    }

    throw "Could not find PostgreSQL tools. Pass -PostgresBin or set POSTGRES_BIN."
}

function Start-LocalPostgres {
    param(
        [string]$PgBin,
        [string]$DataDir,
        [int]$Port
    )

    $initDb = Join-Path $PgBin "initdb.exe"
    $pgCtl = Join-Path $PgBin "pg_ctl.exe"
    $pgIsReady = Join-Path $PgBin "pg_isready.exe"
    $logPath = Join-Path (Split-Path -Parent $DataDir) "postgres-$Port.log"
    $started = $false

    if (Test-TcpPort -Port $Port) {
        Write-Step "PostgreSQL port $Port is already listening; reusing it."
        Invoke-Checked $pgIsReady @("-h", "127.0.0.1", "-p", "$Port", "-U", "postgres") "PostgreSQL did not become ready."
        return [pscustomobject]@{
            Started = $false
            LogPath = $logPath
        }
    }

    if (-not (Test-Path -LiteralPath $DataDir)) {
        Write-Step "Initializing temporary PostgreSQL data dir: $DataDir"
        New-Item -ItemType Directory -Path (Split-Path -Parent $DataDir) -Force | Out-Null
        Invoke-Checked $initDb @("-D", $DataDir, "-U", "postgres", "--auth=trust", "--encoding=UTF8", "--locale=C") "initdb failed."
    }

    Write-Step "Starting PostgreSQL on 127.0.0.1:$Port"
    Invoke-Checked $pgCtl @("-D", $DataDir, "-l", $logPath, "-o", "-p $Port", "-w", "start") "pg_ctl start failed."
    $started = $true

    Invoke-Checked $pgIsReady @("-h", "127.0.0.1", "-p", "$Port", "-U", "postgres") "PostgreSQL did not become ready."

    return [pscustomobject]@{
        Started = $started
        LogPath = $logPath
    }
}

function Invoke-PsqlScalar {
    param(
        [string]$PgBin,
        [int]$Port,
        [string]$Database,
        [string]$Query
    )

    $psql = Join-Path $PgBin "psql.exe"
    $output = & $psql -h "127.0.0.1" -p $Port -U "postgres" -d $Database -At -c $Query
    if ($LASTEXITCODE -ne 0) {
        throw "psql query failed. Exit code: $LASTEXITCODE"
    }

    return ($output | Out-String).Trim()
}

function Invoke-PsqlCommand {
    param(
        [string]$PgBin,
        [int]$Port,
        [string]$Database,
        [string]$Command
    )

    $psql = Join-Path $PgBin "psql.exe"
    & $psql -h "127.0.0.1" -p $Port -U "postgres" -d $Database -c $Command | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed. Exit code: $LASTEXITCODE"
    }
}

function Ensure-PostgresDatabase {
    param(
        [string]$PgBin,
        [int]$Port,
        [string]$Database,
        [string]$Username,
        [string]$Password
    )

    $roleExists = Invoke-PsqlScalar -PgBin $PgBin -Port $Port -Database "postgres" -Query "select 1 from pg_roles where rolname = $(ConvertTo-SqlLiteral $Username);"
    if ($roleExists -ne "1") {
        Write-Step "Creating PostgreSQL role: $Username"
        Invoke-PsqlCommand -PgBin $PgBin -Port $Port -Database "postgres" -Command "create role $Username login password $(ConvertTo-SqlLiteral $Password);"
    } else {
        Invoke-PsqlCommand -PgBin $PgBin -Port $Port -Database "postgres" -Command "alter role $Username with login password $(ConvertTo-SqlLiteral $Password);"
    }

    $dbExists = Invoke-PsqlScalar -PgBin $PgBin -Port $Port -Database "postgres" -Query "select 1 from pg_database where datname = $(ConvertTo-SqlLiteral $Database);"
    if ($dbExists -ne "1") {
        Write-Step "Creating PostgreSQL database: $Database"
        Invoke-PsqlCommand -PgBin $PgBin -Port $Port -Database "postgres" -Command "create database $Database owner $Username;"
    }
}

function Test-BackendHealth([int]$Port) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/health" -TimeoutSec 2
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Start-LocalBackend {
    param(
        [string]$RepoRoot,
        [int]$BackendPort,
        [int]$PostgresPort,
        [string]$Database,
        [string]$Username,
        [string]$Password,
        [int]$HealthTimeoutSeconds
    )

    if (Test-BackendHealth -Port $BackendPort) {
        Write-Step "Backend is already healthy on localhost:$BackendPort; reusing it."
        return [pscustomobject]@{
            Started = $false
            Process = $null
            OutLog  = $null
            ErrLog  = $null
        }
    }

    if (Test-TcpPort -Port $BackendPort) {
        throw "Port $BackendPort is already listening, but /api/health is not healthy."
    }

    $backendDir = Join-Path $RepoRoot "backend"
    $runDir = Join-Path $RepoRoot "tmp\android-local-backend-smoke"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $outLog = Join-Path $runDir "backend-$BackendPort.out.log"
    $errLog = Join-Path $runDir "backend-$BackendPort.err.log"
    Remove-Item -LiteralPath $outLog, $errLog -ErrorAction SilentlyContinue

    $databaseUrl = "jdbc:postgresql://localhost:$PostgresPort/$Database"
    $commandLine = @(
        "set ROCKETFLOW_DB_URL=$databaseUrl",
        "set ROCKETFLOW_DB_USERNAME=$Username",
        "set ROCKETFLOW_DB_PASSWORD=$Password",
        "set SERVER_PORT=$BackendPort",
        "cd /d `"$backendDir`"",
        "mvn.cmd -Dspring-boot.run.profiles=local spring-boot:run"
    ) -join "&& "

    Write-Step "Starting backend on localhost:$BackendPort"
    $process = Start-Process -FilePath "cmd.exe" `
        -ArgumentList @("/c", $commandLine) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -PassThru

    $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if ($process.HasExited) {
            $stdout = Get-Content -LiteralPath $outLog -Tail 120 -ErrorAction SilentlyContinue | Out-String
            $stderr = Get-Content -LiteralPath $errLog -Tail 120 -ErrorAction SilentlyContinue | Out-String
            throw "Backend exited before health was ready. Exit code: $($process.ExitCode)`n$outLog`n$stdout`n$errLog`n$stderr"
        }
        if (Test-BackendHealth -Port $BackendPort) {
            Write-Step "Backend health is UP."
            return [pscustomobject]@{
                Started = $true
                Process = $process
                OutLog  = $outLog
                ErrLog  = $errLog
            }
        }
    }

    throw "Timed out waiting for backend health on localhost:$BackendPort. Logs: $outLog, $errLog"
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body,
        [switch]$AllowConflict
    )

    $json = if ($null -eq $Body) { $null } else { $Body | ConvertTo-Json -Depth 10 }

    try {
        if ($null -eq $json) {
            return Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method $Method -TimeoutSec 15
        }

        return Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method $Method -ContentType "application/json" -Body $json -TimeoutSec 15
    } catch {
        if ($AllowConflict -and $null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 409) {
            return $null
        }
        throw
    }
}

function Ensure-SmokeAccount {
    param(
        [int]$BackendPort,
        [string]$Email,
        [string]$Password,
        [string]$DisplayName
    )

    $baseUrl = "http://localhost:$BackendPort/api"
    Write-Step "Ensuring API smoke account: $Email"
    Invoke-ApiJson -Method "Post" -Uri "$baseUrl/auth/register" -AllowConflict -Body @{
        email       = $Email
        password    = $Password
        displayName = $DisplayName
        timezone    = "Europe/Moscow"
        language    = "ru"
    } | Out-Null

    $login = Invoke-ApiJson -Method "Post" -Uri "$baseUrl/auth/login" -Body @{
        email    = $Email
        password = $Password
    }

    if ($login.StatusCode -ne 200) {
        throw "API login failed for $Email with status $($login.StatusCode)."
    }
    Write-Step "API login passed."
}

function Reset-SmokeAccount {
    param(
        [string]$PgBin,
        [int]$Port,
        [string]$Database,
        [string]$Email
    )

    Write-Step "Deleting existing smoke account if present: $Email"
    Invoke-PsqlCommand `
        -PgBin $PgBin `
        -Port $Port `
        -Database $Database `
        -Command "delete from users where lower(email) = lower($(ConvertTo-SqlLiteral $Email));"
}

function Resolve-Adb {
    $fromPath = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        return $fromPath.Source
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        $candidates += Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
        $candidates += Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    }

    $candidate = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($null -ne $candidate) {
        return $candidate
    }

    throw "Could not find adb.exe. Install Android SDK platform-tools or pass it through PATH."
}

function Resolve-DeviceId {
    param(
        [string]$Adb,
        [string]$ExplicitDeviceId
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitDeviceId)) {
        return $ExplicitDeviceId
    }

    $devices = & $Adb devices |
        Select-String -Pattern "^\S+\s+device$" |
        ForEach-Object { ($_.Line -split "\s+")[0] }

    if (@($devices).Count -eq 0) {
        throw "No connected Android device found."
    }

    return @($devices)[0]
}

function Invoke-Adb {
    param(
        [string]$Adb,
        [string]$Device,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Adb -s $Device @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "adb $($Arguments -join ' ') failed. Exit code: $exitCode`n$($output | Out-String)"
    }
}

function Save-UiDump {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$DestinationPath
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "uiautomator", "dump", "/sdcard/rf-smoke-window.xml") | Out-Null
            Start-Sleep -Milliseconds 250
            Invoke-Adb -Adb $Adb -Device $Device -Arguments @("pull", "/sdcard/rf-smoke-window.xml", $DestinationPath) | Out-Null
            Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "rm", "/sdcard/rf-smoke-window.xml") | Out-Null
            return [xml](Get-Content -LiteralPath $DestinationPath -Raw)
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (300 * $attempt)
        }
    }

    throw $lastError
}

function Get-NodeCenter {
    param([System.Xml.XmlElement]$Node)

    $bounds = $Node.bounds
    if ($bounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") {
        throw "Could not parse UI bounds: $bounds"
    }

    $left = [int]$Matches[1]
    $top = [int]$Matches[2]
    $right = [int]$Matches[3]
    $bottom = [int]$Matches[4]

    return [pscustomobject]@{
        X      = [int](($left + $right) / 2)
        Y      = [int](($top + $bottom) / 2)
        Width  = $right - $left
        Height = $bottom - $top
        Top    = $top
        Bottom = $bottom
    }
}

function Send-AdbText {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Text
    )

    $adbText = $Text.Replace("\", "\\").Replace(" ", "%s").Replace("@", "\@")
    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "input", "text", $adbText)
}

function Clear-AdbFocusedText {
    param(
        [string]$Adb,
        [string]$Device,
        [int]$MaxDeletes = 120
    )

    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "input", "keyevent", "KEYCODE_MOVE_END")
    for ($i = 0; $i -lt $MaxDeletes; $i++) {
        Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "input", "keyevent", "KEYCODE_DEL")
    }
}

function Install-DebugApkIfRequested {
    param(
        [string]$RepoRoot,
        [string]$Adb,
        [string]$Device,
        [int]$BackendPort,
        [bool]$Build,
        [bool]$Install
    )

    if ($Build) {
        Write-Step "Building debug APK for http://10.0.2.2:$BackendPort/api"
        $androidRoot = Join-Path $RepoRoot "android"
        $gradle = Join-Path $androidRoot "gradlew.bat"
        Push-Location $androidRoot
        try {
            Invoke-Checked $gradle @(":app:assembleDebug", "-ProcketflowApiBaseUrl=http://10.0.2.2:$BackendPort/api") "Gradle assembleDebug failed."
        } finally {
            Pop-Location
        }
    }

    if ($Install) {
        $apk = Join-Path $RepoRoot "android\app\build\outputs\apk\debug\app-debug.apk"
        if (-not (Test-Path -LiteralPath $apk)) {
            throw "Debug APK does not exist: $apk. Run with -BuildDebugApk."
        }
        Write-Step "Installing debug APK on $Device"
        Invoke-Adb -Adb $Adb -Device $Device -Arguments @("install", "-r", $apk)
    }
}

function Ensure-SimpleTestIme {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$RunDir
    )

    $component = "rkr.simplekeyboard.inputmethod/.latin.LatinIME"
    $apkUrl = "https://github.com/rkkr/simple-keyboard/releases/download/144/app-release.apk"
    $apkSha256 = "A1CA4D6D4685BBF7A0F57A0668C0BA9FEFFE7FB2519F97B8E561238E6BF67BA0"
    $apkPath = Join-Path $RunDir "simple-keyboard.apk"

    $needDownload = $true
    if (Test-Path -LiteralPath $apkPath) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
        $needDownload = $hash -ne $apkSha256
    }

    if ($needDownload) {
        Write-Step "Downloading deterministic test keyboard APK."
        Invoke-WebRequest -UseBasicParsing -Uri $apkUrl -OutFile $apkPath
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
        if ($hash -ne $apkSha256) {
            throw "Simple Keyboard APK hash mismatch. Expected $apkSha256, got $hash."
        }
    }

    Write-Step "Installing and selecting deterministic test keyboard on $Device"
    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("install", "-r", $apkPath)
    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "ime", "enable", $component)
    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "ime", "set", $component)
    Invoke-Adb -Adb $Adb -Device $Device -Arguments @("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1")

    $current = (& $Adb -s $Device shell settings get secure default_input_method 2>&1 | Out-String).Trim()
    if ($current -ne $component) {
        throw "Could not select test keyboard. Expected $component, got $current."
    }
}

function Invoke-DeviceLoginSmoke {
    param(
        [string]$RepoRoot,
        [string]$Email,
        [string]$Password,
        [int]$BackendPort,
        [bool]$BuildApk,
        [bool]$InstallApk,
        [bool]$ClearData,
        [bool]$UseSimpleIme,
        [string]$DeviceId
    )

    $adb = Resolve-Adb
    $device = Resolve-DeviceId -Adb $adb -ExplicitDeviceId $DeviceId
    $runDir = Join-Path $RepoRoot "tmp\android-local-backend-smoke"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    Install-DebugApkIfRequested -RepoRoot $RepoRoot -Adb $adb -Device $device -BackendPort $BackendPort -Build $BuildApk -Install $InstallApk
    if ($UseSimpleIme) {
        Ensure-SimpleTestIme -Adb $adb -Device $device -RunDir $runDir
    }
    Write-Step "Enabling on-screen keyboard on $device"
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1")

    if ($ClearData) {
        Write-Step "Clearing app data on $device"
        Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "pm", "clear", "com.rocketflow.companion")
    }

    Write-Step "Launching Android app on $device"
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "am", "force-stop", "com.rocketflow.companion")
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "monkey", "-p", "com.rocketflow.companion", "-c", "android.intent.category.LAUNCHER", "1")
    Start-Sleep -Seconds 2

    $xmlPath = Join-Path $runDir "window-before-login.xml"
    $ui = Save-UiDump -Adb $adb -Device $device -DestinationPath $xmlPath
    $emailNode = $ui.SelectSingleNode("//*[@class='android.widget.EditText' and @hint='Email']")
    if ($null -eq $emailNode) {
        throw "Login screen not found on device. Use -ClearAppData, or sign out manually before running the device login smoke."
    }

    $editTexts = @($ui.SelectNodes("//*[@class='android.widget.EditText']"))
    if ($editTexts.Count -lt 2) {
        throw "Could not find both login fields in UI dump: $xmlPath"
    }

    $emailCenter = Get-NodeCenter -Node $emailNode
    $passwordCenter = Get-NodeCenter -Node $editTexts[1]
    $buttons = @($ui.SelectNodes("//*[@class='android.widget.Button']"))
    $signInButton = $buttons |
        ForEach-Object {
            $center = Get-NodeCenter -Node $_
            [pscustomobject]@{
                Node   = $_
                Center = $center
            }
        } |
        Where-Object { $_.Center.Width -gt 400 -and $_.Center.Top -gt $passwordCenter.Bottom } |
        Sort-Object { $_.Center.Top } |
        Select-Object -First 1

    if ($null -eq $signInButton) {
        throw "Could not find sign-in button in UI dump: $xmlPath"
    }

    Write-Step "Entering credentials on device"
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "input", "tap", "$($emailCenter.X)", "$($emailCenter.Y)")
    Start-Sleep -Milliseconds 250
    Clear-AdbFocusedText -Adb $adb -Device $device
    Send-AdbText -Adb $adb -Device $device -Text $Email

    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "input", "tap", "$($passwordCenter.X)", "$($passwordCenter.Y)")
    Start-Sleep -Milliseconds 250
    Clear-AdbFocusedText -Adb $adb -Device $device
    Send-AdbText -Adb $adb -Device $device -Text $Password

    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "input", "tap", "$($signInButton.Center.X)", "$($signInButton.Center.Y)")

    $loggedIn = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $ui = Save-UiDump -Adb $adb -Device $device -DestinationPath (Join-Path $runDir "window-after-login.xml")
        $stillOnLogin = $null -ne $ui.SelectSingleNode("//*[@class='android.widget.EditText' and @hint='Email']")
        $hasPlannerBrand = $null -ne $ui.SelectSingleNode("//*[@class='android.widget.TextView' and @text='RF']")
        if (-not $stillOnLogin -and $hasPlannerBrand) {
            $loggedIn = $true
            break
        }
    }

    $screenshotPath = Join-Path $runDir "device-login-result.png"
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "screencap", "-p", "/sdcard/rf-smoke-result.png")
    Invoke-Adb -Adb $adb -Device $device -Arguments @("pull", "/sdcard/rf-smoke-result.png", $screenshotPath)
    Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "rm", "/sdcard/rf-smoke-result.png")

    if (-not $loggedIn) {
        throw "Device login did not reach the planner screen. Screenshot: $screenshotPath"
    }

    Write-Step "Device login reached the planner screen."
    return [pscustomobject]@{
        DeviceId   = $device
        Screenshot = $screenshotPath
    }
}

$repoRoot = Resolve-RepoRoot
$runRoot = Join-Path $repoRoot "tmp\android-local-backend-smoke"
if ([string]::IsNullOrWhiteSpace($PostgresDataDir)) {
    $PostgresDataDir = Join-Path $runRoot "postgres-data-$PostgresPort"
}

$pgBin = Resolve-PostgresBin -ExplicitBin $PostgresBin
$postgresInfo = $null
$backendInfo = $null
$deviceInfo = $null

try {
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

    $postgresInfo = Start-LocalPostgres -PgBin $pgBin -DataDir $PostgresDataDir -Port $PostgresPort
    Ensure-PostgresDatabase -PgBin $pgBin -Port $PostgresPort -Database $PostgresDatabase -Username $PostgresUsername -Password $PostgresPassword

    $backendInfo = Start-LocalBackend `
        -RepoRoot $repoRoot `
        -BackendPort $BackendPort `
        -PostgresPort $PostgresPort `
        -Database $PostgresDatabase `
        -Username $PostgresUsername `
        -Password $PostgresPassword `
        -HealthTimeoutSeconds $BackendHealthTimeoutSeconds

    if ($ResetAccount) {
        Reset-SmokeAccount -PgBin $pgBin -Port $PostgresPort -Database $PostgresDatabase -Email $Email
    }

    Ensure-SmokeAccount -BackendPort $BackendPort -Email $Email -Password $Password -DisplayName $DisplayName

    if ($DeviceLogin) {
        $deviceInfo = Invoke-DeviceLoginSmoke `
            -RepoRoot $repoRoot `
            -Email $Email `
            -Password $Password `
            -BackendPort $BackendPort `
            -BuildApk ([bool]$BuildDebugApk) `
            -InstallApk ([bool]$InstallDebugApk) `
            -ClearData ([bool]$ClearAppData) `
            -UseSimpleIme ([bool]$UseSimpleTestIme) `
            -DeviceId $DeviceId
    }

    $result = [pscustomobject]@{
        Status          = "OK"
        ApiBaseUrl      = "http://localhost:$BackendPort/api"
        AndroidBaseUrl  = "http://10.0.2.2:$BackendPort/api"
        Email           = $Email
        PostgresPort    = $PostgresPort
        PostgresDataDir = $PostgresDataDir
        BackendPort     = $BackendPort
        BackendStarted  = if ($null -ne $backendInfo) { $backendInfo.Started } else { $false }
        BackendPid      = if ($null -ne $backendInfo -and $null -ne $backendInfo.Process) { $backendInfo.Process.Id } else { $null }
        BackendOutLog   = if ($null -ne $backendInfo) { $backendInfo.OutLog } else { $null }
        BackendErrLog   = if ($null -ne $backendInfo) { $backendInfo.ErrLog } else { $null }
        DeviceId        = if ($null -ne $deviceInfo) { $deviceInfo.DeviceId } else { $null }
        Screenshot      = if ($null -ne $deviceInfo) { $deviceInfo.Screenshot } else { $null }
    }

    $result | Format-List | Out-String | Write-Host
} finally {
    if ($StopAfter) {
        if ($null -ne $backendInfo -and $backendInfo.Started -and $null -ne $backendInfo.Process -and -not $backendInfo.Process.HasExited) {
            Write-Step "Stopping backend pid $($backendInfo.Process.Id)"
            Stop-Process -Id $backendInfo.Process.Id -Force -ErrorAction SilentlyContinue
        }

        if ($null -ne $postgresInfo -and $postgresInfo.Started) {
            Write-Step "Stopping temporary PostgreSQL on port $PostgresPort"
            $pgCtl = Join-Path $pgBin "pg_ctl.exe"
            & $pgCtl -D $PostgresDataDir -w stop | Out-Null
        }
    } elseif ($null -ne $backendInfo -and $backendInfo.Started) {
        Write-Step "Leaving backend running. Use -StopAfter for cleanup runs, or stop pid $($backendInfo.Process.Id)."
    }
}
