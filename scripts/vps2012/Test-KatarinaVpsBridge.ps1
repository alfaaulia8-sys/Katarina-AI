param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
trap {
    Write-Host ""
    Write-Host ("FAIL_VPS_GITHUB_HANDSHAKE: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Resolve-Git {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf86) { $candidates += (Join-Path $pf86 "Git\cmd\git.exe") }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Quote-Arg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"','\"') + '"'
}

function Run-Git {
    param([string]$Git,[string[]]$Args,[string]$WorkingDirectory)
    $stdout = [IO.Path]::GetTempFileName()
    $stderr = [IO.Path]::GetTempFileName()
    try {
        $allArgs = @("-C",$WorkingDirectory) + $Args
        $argLine = (($allArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join " ")
        $p = Start-Process -FilePath $Git -ArgumentList $argLine -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $outText = ""
        $errText = ""
        if (Test-Path -LiteralPath $stdout) { $outText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderr) { $errText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue }
        return [pscustomobject]@{
            Code = [int]$p.ExitCode
            Text = ([string]$outText + [Environment]::NewLine + [string]$errText).Trim()
        }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

$gitMarker = Join-Path $RepoRoot ".git"
if (-not (Test-Path -LiteralPath $gitMarker)) {
    throw "Folder ini bukan Git clone. Folder .git tidak ditemukan. Jangan gunakan ZIP/copy."
}

$git = Resolve-Git
if (-not $git) { throw "git.exe tidak ditemukan. Install Git for Windows terlebih dahulu." }

$origin = Run-Git $git @("remote","get-url","origin") $RepoRoot
if ($origin.Code -ne 0) { throw "origin remote tidak tersedia: $($origin.Text)" }

$fetch = Run-Git $git @("fetch","origin","vps-reports:refs/remotes/origin/vps-reports") $RepoRoot
if ($fetch.Code -ne 0) { throw "Tidak bisa fetch vps-reports: $($fetch.Text)" }

$headResult = Run-Git $git @("rev-parse","HEAD") $RepoRoot
if ($headResult.Code -ne 0) { throw "Tidak bisa membaca HEAD." }
$sourceHead = $headResult.Text.Trim()

$branchResult = Run-Git $git @("rev-parse","--abbrev-ref","HEAD") $RepoRoot
if ($branchResult.Code -ne 0) { throw "Tidak bisa membaca branch." }
$sourceBranch = $branchResult.Text.Trim()

$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$temp = Join-Path $env:TEMP ("KatarinaVpsProbe-" + [Guid]::NewGuid().ToString("N"))

try {
    $wt = Run-Git $git @("worktree","add","--detach",$temp,"origin/vps-reports") $RepoRoot
    if ($wt.Code -ne 0) { throw "Tidak bisa membuat report worktree: $($wt.Text)" }

    $dest = Join-Path $temp "vps_bridge\reports"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $report = [ordered]@{
        schema_version = 1
        proof_type = "KATARINA_VPS_CONNECTION"
        run_id = $runId
        generated_utc = [DateTime]::UtcNow.ToString("o")
        computer_name = $env:COMPUTERNAME
        os = [Environment]::OSVersion.VersionString
        powershell_version = $PSVersionTable.PSVersion.ToString()
        source_head = $sourceHead
        source_branch = $sourceBranch
        control_branch = "vps-control"
        report_branch = "vps-reports"
        live_risk_ready = $false
        live_execution_enabled = $false
        result = "PASS_VPS_GITHUB_HANDSHAKE"
    }

    ($report | ConvertTo-Json -Depth 6) | Out-File -LiteralPath (Join-Path $dest "connection.json") -Encoding utf8

    $add = Run-Git $git @("add","vps_bridge/reports/connection.json") $temp
    if ($add.Code -ne 0) { throw "git add gagal: $($add.Text)" }

    $commit = Run-Git $git @("-c","user.name=KATARINA VPS","-c","user.email=katarina-vps@local.invalid","commit","-m",("vps-handshake: " + $runId)) $temp
    if ($commit.Code -ne 0) { throw "git commit gagal: $($commit.Text)" }

    $push = Run-Git $git @("push","origin","HEAD:refs/heads/vps-reports") $temp
    if ($push.Code -ne 0) { throw "git push gagal: $($push.Text)" }

    Write-Host ""
    Write-Host "PASS_VPS_GITHUB_HANDSHAKE" -ForegroundColor Green
    Write-Host "VPS -> GitHub vps-reports berhasil."
    Write-Host "Kembali ke ChatGPT dan bilang: cek koneksi VPS."
    exit 0
} finally {
    try { [void](Run-Git $git @("worktree","remove","--force",$temp) $RepoRoot) } catch {}
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
