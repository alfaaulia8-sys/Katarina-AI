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

function Resolve-GitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "GitHubDesktop\bin\git.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $desktopRoot = Join-Path $env:LOCALAPPDATA "GitHubDesktop"
    if (Test-Path -LiteralPath $desktopRoot -PathType Container) {
        $desktopGit = Get-ChildItem -Path (Join-Path $desktopRoot "app-*") -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                @(
                    (Join-Path $_.FullName "resources\app\git\cmd\git.exe"),
                    (Join-Path $_.FullName "resources\app\git\mingw64\bin\git.exe")
                )
            } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($desktopGit) { return [string]$desktopGit }
    }

    return $null
}

function Enable-Git {
    $gitExe = Resolve-GitExecutable
    if (-not $gitExe) { return $null }

    $gitDir = Split-Path -Parent $gitExe
    if (($env:PATH -split ';') -notcontains $gitDir) {
        $env:PATH = $gitDir + ";" + $env:PATH
    }
    return $gitExe
}

function Try-InstallGit {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }

    Write-Host "[KATARINA] Git belum ditemukan. Mencoba install Git for Windows otomatis..."
    & $winget.Source install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { return $false }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machinePath;$userPath"
    return [bool](Enable-Git)
}

function Resolve-PythonCommand {
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python) {
        return [pscustomobject]@{ File = $python.Source; Prefix = @() }
    }

    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        return [pscustomobject]@{ File = $py.Source; Prefix = @("-3") }
    }

    $candidateRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        (Join-Path $env:ProgramFiles "Python312"),
        (Join-Path $env:ProgramFiles "Python313")
    )
    foreach ($root in $candidateRoots) {
        if (-not $root) { continue }
        if (Test-Path -LiteralPath $root -PathType Leaf) {
            return [pscustomobject]@{ File = $root; Prefix = @() }
        }
        if (Test-Path -LiteralPath $root -PathType Container) {
            $found = Get-ChildItem -LiteralPath $root -Filter python.exe -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($found) {
                return [pscustomobject]@{ File = $found.FullName; Prefix = @() }
            }
        }
    }
    return $null
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

$gitExe = Enable-Git
if (-not $gitExe) {
    [void](Try-InstallGit)
    $gitExe = Enable-Git
}
if (-not $gitExe) {
    Write-Host ""
    Write-Host "[KATARINA] Git belum ditemukan." -ForegroundColor Red
    Write-Host "Install Git for Windows atau buka ulang GitHub Desktop, lalu jalankan START_KATARINA.bat lagi."
    Write-Host "Download resmi: https://git-scm.com/download/win"
    exit 10
}
Write-Host "Git: $gitExe"

$pythonCommand = Resolve-PythonCommand
if (-not $pythonCommand) {
    Write-Host ""
    Write-Host "[KATARINA] Python 3 belum ditemukan." -ForegroundColor Red
    Write-Host "Install Python 3.12+ lalu jalankan START_KATARINA.bat lagi."
    exit 11
}
Write-Host "Python: $($pythonCommand.File)"

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
    $pythonArgs = @($pythonCommand.Prefix) + $cmd
    ("RUN " + $pythonCommand.File + " " + ($pythonArgs -join " ")) | Add-Content -LiteralPath $verifyLog -Encoding UTF8
    $stdoutPath = [IO.Path]::GetTempFileName()
    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $pythonCommand.File `
            -ArgumentList $pythonArgs `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        $rc = $proc.ExitCode

        $output = @()
        if (Test-Path -LiteralPath $stdoutPath) {
            $output += Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $output += Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
        }
        foreach ($line in $output) {
            Write-Host $line
            $line | Add-Content -LiteralPath $verifyLog -Encoding UTF8
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
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
