param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$stateRoot = Join-Path $env:LOCALAPPDATA "KatarinaAI"
$logRoot = Join-Path $stateRoot "supervisor-logs"
$pidFile = Join-Path $stateRoot "supervisor.pid"
$watcher = Join-Path $PSScriptRoot "Watch-KatarinaErrors.ps1"
$publisher = Join-Path $PSScriptRoot "Publish-KatarinaError.ps1"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Start-ErrorSupervisor {
    $alreadyRunning = $false
    if (Test-Path -LiteralPath $pidFile) {
        try {
            $existingPid = [int](Get-Content -LiteralPath $pidFile -ErrorAction Stop | Select-Object -First 1)
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) { $alreadyRunning = $true }
        } catch {}
    }

    if ($alreadyRunning) {
        Write-Host "[KATARINA] Error Supervisor already running."
        return
    }

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $watcher),
        "-RepoRoot", ('"{0}"' -f $RepoRoot)
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Minimized | Out-Null
    Start-Sleep -Milliseconds 700
    Write-Host "[KATARINA] Error Supervisor started."
}

function Publish-StartupFailure {
    param([string]$Summary, [string]$LogPath, [int]$ExitCode)
    try {
        $args = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $publisher,
            "-RepoRoot", $RepoRoot,
            "-ErrorType", "STARTUP_VERIFY_ERROR",
            "-Summary", $Summary,
            "-LogPaths", $LogPath,
            "-SourcePath", "START_KATARINA.bat",
            "-ExitCode", $ExitCode
        )
        & powershell.exe @args | Out-Null
    } catch {
        Write-Warning ("Unable to publish startup error immediately: " + $_.Exception.Message)
    }
}

Write-Host ""
Write-Host "=================================================="
Write-Host " KATARINA AI - ONE CLICK START"
Write-Host "=================================================="
Write-Host "Repo: $RepoRoot"

if (-not (Test-Command "git")) {
    throw "Git is required. Install Git for Windows first."
}
if (-not (Test-Command "python")) {
    throw "Python is required and must be available in PATH."
}

$remote = (& git -C $RepoRoot remote get-url origin 2>$null | Select-Object -First 1)
if (-not $remote) {
    throw "Git remote 'origin' is missing."
}
Write-Host "Git remote: $remote"

Start-ErrorSupervisor

$verifyLog = Join-Path $logRoot ("startup-verify-" + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss") + ".log")
$commands = @(
    @("-m","compileall","-q","src"),
    @("-m","unittest","discover","-s","tests/unit","-p","test_*.py"),
    @("-m","unittest","discover","-s","tests/static","-p","test_*.py")
)

$failed = $false
$failedCode = 0
foreach ($cmd in $commands) {
    ("RUN python " + ($cmd -join " ")) | Add-Content -LiteralPath $verifyLog -Encoding UTF8
    $output = & python @cmd 2>&1
    $rc = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line
        $line | Add-Content -LiteralPath $verifyLog -Encoding UTF8
    }
    ("EXIT_CODE=" + $rc) | Add-Content -LiteralPath $verifyLog -Encoding UTF8
    if ($rc -ne 0) {
        $failed = $true
        $failedCode = $rc
        break
    }
}

if ($failed) {
    Write-Host "[KATARINA] Startup verification FAILED."
    Publish-StartupFailure -Summary "KATARINA startup verification failed" -LogPath $verifyLog -ExitCode $failedCode
    Write-Host "[KATARINA] Error bundle queued/pushed to branch: katarina-errors"
    exit $failedCode
}

Write-Host ""
Write-Host "[KATARINA] Startup verification PASS."
Write-Host "[KATARINA] Error Supervisor ACTIVE."
Write-Host "[KATARINA] MT5/MetaEditor/Python errors will be pushed to branch katarina-errors."
Write-Host "[KATARINA] Live trading remains disabled."
exit 0
