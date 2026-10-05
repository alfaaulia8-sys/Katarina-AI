param(
    [string]$RepoRoot = "",
    [int]$ScanSeconds = 3
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$Publisher = Join-Path $PSScriptRoot "Publish-KatarinaError.ps1"
$stateRoot = Join-Path $env:LOCALAPPDATA "KatarinaAI"
$logRoot = Join-Path $stateRoot "supervisor-logs"
$pidFile = Join-Path $stateRoot "supervisor.pid"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$PID | Set-Content -LiteralPath $pidFile -Encoding ASCII

$seen = @{}
$lastQueueRetry = [DateTime]::MinValue

function Get-SourceCommit {
    $v = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    return [string]$v
}

function Find-ErrorLine {
    param([string[]]$Lines)
    foreach ($line in ($Lines | Select-Object -Last 400)) {
        if ($line -match '(?i)\b0\s+errors?\b' -or
            $line -match '(?i)\berrors?\s*[:=]\s*0\b' -or
            $line -match '(?i)\bno\s+errors?\b') {
            continue
        }
        if ($line -match '(?i)\b[1-9]\d*\s+errors?\b') { return $line.Trim() }
        if ($line -match '(?i)\b(fatal|exception|critical|failed|failure|error)\b') { return $line.Trim() }
        if ($line -match '(?i)(array out of range|zero divide|access violation|unhandled exception)') { return $line.Trim() }
    }
    return $null
}

function Test-LogFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -notin @(".log", ".txt", ".xml", ".json", ".htm", ".html")) { return }

    try {
        $lines = Get-Content -LiteralPath $Path -Tail 500 -ErrorAction Stop
    } catch {
        return
    }
    if (-not $lines) { return }

    $hit = Find-ErrorLine -Lines $lines
    if (-not $hit) { return }

    $commit = Get-SourceCommit
    $raw = "$Path|$hit|$commit"
    $bytes = [Text.Encoding]::UTF8.GetBytes($raw)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $signature = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
    } finally {
        $sha.Dispose()
    }
    if ($seen.ContainsKey($signature)) { return }
    $seen[$signature] = [DateTime]::UtcNow

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Publisher,
        "-RepoRoot", $RepoRoot,
        "-ErrorType", "LOG_ERROR",
        "-Summary", $hit,
        "-LogPaths", $Path,
        "-SourcePath", $Path
    )
    & powershell.exe @args | Out-Null
}

function Get-WatchRoots {
    $roots = @(
        (Join-Path $env:APPDATA "MetaQuotes\Terminal"),
        (Join-Path $env:APPDATA "MetaQuotes\Tester"),
        (Join-Path $RepoRoot ".katarina\logs")
    )
    return $roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique
}

Write-Host "KATARINA Error Supervisor ACTIVE"
Write-Host "Repo: $RepoRoot"
Write-Host "Target branch: katarina-errors"
Write-Host "Live trading remains disabled by KATARINA policy."

try {
    while ($true) {
        foreach ($root in (Get-WatchRoots)) {
            $cutoff = (Get-Date).AddSeconds(-[Math]::Max($ScanSeconds * 3, 15))
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -ge $cutoff -and
                    $_.Extension.ToLowerInvariant() -in @(".log", ".txt", ".xml", ".json", ".htm", ".html")
                } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 250 |
                ForEach-Object { Test-LogFile -Path $_.FullName }
        }

        if (((Get-Date) - $lastQueueRetry).TotalSeconds -ge 15) {
            try {
                $retryArgs = @(
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Publisher,
                    "-RepoRoot", $RepoRoot, "-RetryQueued"
                )
                & powershell.exe @retryArgs | Out-Null
            } catch {}
            $lastQueueRetry = Get-Date
        }

        Start-Sleep -Seconds $ScanSeconds
    }
} finally {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}
