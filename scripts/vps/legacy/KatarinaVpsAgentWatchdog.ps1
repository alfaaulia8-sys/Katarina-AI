param(
    [string]$InstallRoot = "C:\KatarinaVPSAgent",
    [string]$AgentTaskName = "KatarinaVPSAgent",
    [int]$StaleSeconds = 75,
    [int]$RestartCooldownSeconds = 120
)

$ErrorActionPreference = "Stop"

$LaneHeartbeatPath = Join-Path $InstallRoot "lanes\primary\heartbeat.json"
$LegacyHeartbeatPath = Join-Path $InstallRoot "heartbeat.json"
$StatePath = Join-Path $InstallRoot "watchdog_state.json"
$LogPath = Join-Path $InstallRoot "watchdog.log"

function Log-Line([string]$Text) {
    $line = "[{0}] {1}" -f [DateTime]::UtcNow.ToString("o"), $Text
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Read-Utc([object]$Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        return [DateTime]::Parse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
    } catch {
        return $null
    }
}

function Get-LastRestartUtc {
    if (!(Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        return Read-Utc $state.last_restart_utc
    } catch {
        return $null
    }
}

function Save-State([string]$Reason) {
    [ordered]@{
        schema_version = 1
        last_restart_utc = [DateTime]::UtcNow.ToString("o")
        reason = $Reason
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$now = [DateTime]::UtcNow
$reason = $null
$heartbeat = $null

$heartbeatCandidate = $null
if (Test-Path -LiteralPath $LaneHeartbeatPath -PathType Leaf) {
    $heartbeatCandidate = $LaneHeartbeatPath
} elseif (Test-Path -LiteralPath $LegacyHeartbeatPath -PathType Leaf) {
    $heartbeatCandidate = $LegacyHeartbeatPath
}
if ($heartbeatCandidate) {
    try { $heartbeat = Get-Content -LiteralPath $heartbeatCandidate -Raw | ConvertFrom-Json } catch {}
}

if ($null -eq $heartbeat) {
    $reason = "HEARTBEAT_MISSING"
} else {
    $updated = Read-Utc $heartbeat.updated_utc
    if ($null -eq $updated) {
        $reason = "HEARTBEAT_INVALID"
    } else {
        $age = ($now - $updated).TotalSeconds
        if ($age -gt $StaleSeconds) {
            $reason = ("HEARTBEAT_STALE_{0}s" -f [int]$age)
        }
    }
}

# A persistent ONSTART task should have a live PowerShell host. If the host is
# gone even with a fresh file, recover immediately.
$agentProcess = $null
try {
    $agentProcess = @(
        Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    ) | Select-Object -First 1
} catch {}

if ($null -eq $agentProcess -and $null -eq $reason) {
    $reason = "AGENT_PROCESS_MISSING"
}

if ($null -eq $reason) {
    exit 0
}

$lastRestart = Get-LastRestartUtc
if ($null -ne $lastRestart -and (($now - $lastRestart).TotalSeconds -lt $RestartCooldownSeconds)) {
    Log-Line ("Recovery suppressed by cooldown. reason=" + $reason)
    exit 0
}

Log-Line ("Recovery triggered. reason=" + $reason)
try { & schtasks.exe /End /TN $AgentTaskName | Out-Null } catch {}
Start-Sleep -Seconds 2

& schtasks.exe /Run /TN $AgentTaskName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Log-Line ("Recovery failed to start scheduled task. exit=" + $LASTEXITCODE)
    exit 1
}

Save-State -Reason $reason
Log-Line ("Recovery started scheduled task successfully. reason=" + $reason)
exit 0
