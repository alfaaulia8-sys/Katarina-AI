param(
    [string]$RepoRoot = "",
    [string]$ErrorType = "UNKNOWN",
    [string]$Summary = "KATARINA error detected",
    [string[]]$LogPaths = @(),
    [string]$SourcePath = "",
    [Nullable[int]]$ExitCode = $null,
    [switch]$RetryQueued
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Invoke-Git {
    param([string[]]$Args, [string]$WorkingDirectory)
    $output = & git -C $WorkingDirectory @Args 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "git $($Args -join ' ') failed ($code): $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Sanitize-Text {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $v = $Text
    $v = [regex]::Replace($v, 'gh[opusr]_[A-Za-z0-9_]{20,}', '[REDACTED_GITHUB_TOKEN]')
    $v = [regex]::Replace($v, 'github_pat_[A-Za-z0-9_]{20,}', '[REDACTED_GITHUB_TOKEN]')
    $v = [regex]::Replace($v, 'sk-[A-Za-z0-9_-]{20,}', '[REDACTED_API_KEY]')
    $v = [regex]::Replace($v, '(?im)(password|passwd|pwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s;]+', '$1=[REDACTED]')
    $v = [regex]::Replace($v, '(?im)(login|account)\s*[:=]\s*(\d{0,8})(\d{4})\b', '$1=****$3')
    return $v
}

function Get-RepoRoot {
    param([string]$Explicit)
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
    $candidate = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
    return $candidate.Path
}

function Write-ErrorBundle {
    param(
        [string]$Root,
        [string]$Type,
        [string]$Message,
        [string[]]$Paths,
        [string]$Source,
        [Nullable[int]]$Code
    )

    $outbox = Join-Path $env:LOCALAPPDATA "KatarinaAI\error-outbox"
    New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    $runId = ([DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssfff")) + "-" + $env:COMPUTERNAME
    $bundle = Join-Path $outbox $runId
    New-Item -ItemType Directory -Force -Path $bundle | Out-Null

    $head = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
    $branch = (& git -C $Root rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)

    $environment = [ordered]@{
        schema_version = 1
        generated_utc = [DateTime]::UtcNow.ToString("o")
        computer_name = $env:COMPUTERNAME
        os = [Environment]::OSVersion.VersionString
        powershell = $PSVersionTable.PSVersion.ToString()
        source_commit = $head
        source_branch = $branch
        error_type = $Type
        summary = (Sanitize-Text $Message)
        source_path = $Source
        exit_code = $Code
        live_risk_ready = $false
        live_execution_enabled = $false
    }
    $environment | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bundle "error.json") -Encoding UTF8

    $copied = @()
    $index = 0
    foreach ($p in $Paths) {
        if (-not $p) { continue }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $index++
        $leaf = [IO.Path]::GetFileName($p)
        $dest = Join-Path $bundle ("{0:D2}-{1}" -f $index, $leaf)
        try {
            $lines = Get-Content -LiteralPath $p -Tail 2000 -ErrorAction Stop
            $text = Sanitize-Text ($lines -join [Environment]::NewLine)
            $text | Set-Content -LiteralPath $dest -Encoding UTF8
            $copied += $dest
        } catch {
            ("Unable to read log: " + $_.Exception.Message) | Set-Content -LiteralPath ($dest + ".unreadable.txt") -Encoding UTF8
        }
    }

    $summaryText = @(
        "KATARINA ERROR BUNDLE",
        "run_id=$runId",
        "error_type=$Type",
        "summary=$(Sanitize-Text $Message)",
        "source_commit=$head",
        "source_path=$Source",
        "log_count=$($copied.Count)",
        "live_risk_ready=false",
        "live_execution_enabled=false"
    ) -join [Environment]::NewLine
    $summaryText | Set-Content -LiteralPath (Join-Path $bundle "summary.txt") -Encoding UTF8
    return $bundle
}

function Publish-Bundle {
    param([string]$Root, [string]$Bundle)

    $runId = Split-Path -Leaf $Bundle
    $tempRoot = Join-Path $env:TEMP ("KatarinaErrorGit-" + [Guid]::NewGuid().ToString("N"))
    try {
        & git -C $Root fetch origin 2>$null | Out-Null
        & git -C $Root fetch origin katarina-errors 2>$null | Out-Null
        $hasErrorsBranch = ($LASTEXITCODE -eq 0)

        $baseRef = if ($hasErrorsBranch) { "FETCH_HEAD" } else { "origin/main" }
        Invoke-Git -Args @("worktree","add","--detach",$tempRoot,$baseRef) -WorkingDirectory $Root | Out-Null

        $destRoot = Join-Path $tempRoot ("errors\" + $runId)
        New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
        Copy-Item -Path (Join-Path $Bundle "*") -Destination $destRoot -Recurse -Force

        Invoke-Git -Args @("add","errors/$runId") -WorkingDirectory $tempRoot | Out-Null
        & git -C $tempRoot -c user.name="KATARINA Error Supervisor" -c user.email="katarina-errors@local.invalid" commit -m "error: $runId" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "unable to commit error bundle" }

        & git -C $tempRoot push origin HEAD:refs/heads/katarina-errors 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "unable to push katarina-errors" }

        Remove-Item -LiteralPath $Bundle -Recurse -Force
        return $true
    } catch {
        Write-Warning ("KATARINA error queued locally: " + $_.Exception.Message)
        return $false
    } finally {
        try { & git -C $Root worktree remove --force $tempRoot 2>$null | Out-Null } catch {}
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$RepoRoot = Get-RepoRoot $RepoRoot
$outboxRoot = Join-Path $env:LOCALAPPDATA "KatarinaAI\error-outbox"
New-Item -ItemType Directory -Force -Path $outboxRoot | Out-Null

if (-not $RetryQueued) {
    $bundle = Write-ErrorBundle -Root $RepoRoot -Type $ErrorType -Message $Summary -Paths $LogPaths -Source $SourcePath -Code $ExitCode
    [void](Publish-Bundle -Root $RepoRoot -Bundle $bundle)
}

Get-ChildItem -LiteralPath $outboxRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object CreationTime |
    ForEach-Object {
        [void](Publish-Bundle -Root $RepoRoot -Bundle $_.FullName)
    }
