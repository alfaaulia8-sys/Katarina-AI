param(
    [string]$InstallRoot = "C:\KatarinaVPSAgent",
    [string]$AgentTaskName = "KatarinaVPSAgent",
    [int]$StaleSeconds = 90,
    [int]$BusyStaleSeconds = 300,
    [int]$RestartCooldownSeconds = 60
)

$ErrorActionPreference = "Continue"

$LaneConfigPath = Join-Path $InstallRoot "watchdog_lanes.json"
$StateRoot = Join-Path $InstallRoot "watchdog"
$LogPath = Join-Path $InstallRoot "watchdog.log"
$LastCheckPath = Join-Path $InstallRoot "watchdog_last_check.json"

New-Item -ItemType Directory -Force -Path $InstallRoot,$StateRoot | Out-Null

function Log-Line([string]$Text) {
    try {
        $line = "[{0}] {1}" -f [DateTime]::UtcNow.ToString("o"), $Text
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {}
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

function Resolve-LanePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    if ([IO.Path]::IsPathRooted($Value)) { return $Value }
    return (Join-Path $InstallRoot $Value)
}

function Get-AgentProcess([string]$ConfigPath) {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { return $null }
    try {
        return @(
            Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($ConfigPath,[StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        ) | Select-Object -First 1
    } catch {
        return $null
    }
}

function Get-Heartbeat([string]$Path,[string]$FallbackPath="") {
    foreach($candidate in @($Path,$FallbackPath)) {
        if([string]::IsNullOrWhiteSpace($candidate)){ continue }
        if(Test-Path -LiteralPath $candidate -PathType Leaf) {
            try { return Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json } catch {}
        }
    }
    return $null
}

function Get-LastRestart([string]$Lane) {
    $path = Join-Path $StateRoot ($Lane + ".json")
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return Read-Utc $state.last_restart_utc
    } catch {
        return $null
    }
}

function Save-Restart([string]$Lane,[string]$Reason) {
    $path = Join-Path $StateRoot ($Lane + ".json")
    [ordered]@{
        schema_version = 2
        lane = $Lane
        reason = $Reason
        last_restart_utc = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Restart-Lane($LaneInfo,[string]$Reason) {
    $laneName = [string]$LaneInfo.lane
    $taskName = [string]$LaneInfo.task
    $configPath = Resolve-LanePath ([string]$LaneInfo.config)

    $now = [DateTime]::UtcNow
    $lastRestart = Get-LastRestart $laneName
    if ($null -ne $lastRestart -and (($now - $lastRestart).TotalSeconds -lt $RestartCooldownSeconds)) {
        Log-Line ("recovery suppressed lane={0} reason={1}" -f $laneName,$Reason)
        return $false
    }

    Log-Line ("recovery triggered lane={0} reason={1}" -f $laneName,$Reason)

    $proc = Get-AgentProcess $configPath
    if ($null -ne $proc) {
        try { [void]$proc.Terminate() } catch {}
        Start-Sleep -Milliseconds 750
    }

    try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
    Start-Sleep -Milliseconds 750

    & schtasks.exe /Run /TN $taskName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Log-Line ("recovery failed lane={0} task={1} exit={2}" -f $laneName,$taskName,$LASTEXITCODE)
        return $false
    }

    Save-Restart $laneName $Reason
    Log-Line ("recovery started lane={0} task={1}" -f $laneName,$taskName)
    return $true
}

function Get-Lanes {
    if (Test-Path -LiteralPath $LaneConfigPath -PathType Leaf) {
        try {
            $cfg = Get-Content -LiteralPath $LaneConfigPath -Raw | ConvertFrom-Json
            if ($null -ne $cfg.lanes -and @($cfg.lanes).Count -gt 0) {
                return @($cfg.lanes)
            }
        } catch {
            Log-Line ("lane config invalid: " + $_.Exception.Message)
        }
    }

    return @(
        [pscustomobject]@{
            lane = "primary"
            task = $AgentTaskName
            config = (Join-Path $InstallRoot "agent.json")
            heartbeat = (Join-Path $InstallRoot "lanes\primary\heartbeat.json")
            fallback = (Join-Path $InstallRoot "heartbeat.json")
            stale_seconds = $StaleSeconds
            busy_stale_seconds = $BusyStaleSeconds
        }
    )
}

$checks = @()
foreach($lane in @(Get-Lanes)) {
    $laneName = [string]$lane.lane
    $taskName = [string]$lane.task
    $configPath = Resolve-LanePath ([string]$lane.config)
    $heartbeatPath = Resolve-LanePath ([string]$lane.heartbeat)
    $fallbackPath = Resolve-LanePath ([string]$lane.fallback)

    $idleLimit = $StaleSeconds
    $busyLimit = $BusyStaleSeconds
    try {
        if ($null -ne $lane.stale_seconds -and [int]$lane.stale_seconds -gt 0) {
            $idleLimit = [int]$lane.stale_seconds
        }
    } catch {}
    try {
        if ($null -ne $lane.busy_stale_seconds -and [int]$lane.busy_stale_seconds -gt 0) {
            $busyLimit = [int]$lane.busy_stale_seconds
        }
    } catch {}

    $proc = Get-AgentProcess $configPath
    $heartbeat = Get-Heartbeat $heartbeatPath $fallbackPath
    $reason = $null
    $phase = ""
    $age = $null
    $limit = $idleLimit

    if ($null -eq $proc) {
        $reason = "PROCESS_MISSING"
    } elseif ($null -eq $heartbeat) {
        $reason = "HEARTBEAT_MISSING"
    } else {
        $phase = [string]$heartbeat.phase
        if ($phase -eq "TASK_RUNNING" -or
            $phase -eq "WAITING_MUTATION_LOCK" -or
            $phase -eq "REQUEST_START" -or
            $phase -like "GITHUB_RETRY_*") {
            $limit = $busyLimit
        }

        $updated = Read-Utc $heartbeat.updated_utc
        if ($null -eq $updated) {
            $reason = "HEARTBEAT_INVALID"
        } else {
            $age = [math]::Round(([DateTime]::UtcNow - $updated).TotalSeconds,1)
            if ($age -gt $limit) {
                $reason = ("HEARTBEAT_STALE_{0}s" -f [int]$age)
            }
        }
    }

    $restarted = $false
    if ($null -ne $reason) {
        $restarted = Restart-Lane $lane $reason
    }

    $checks += [ordered]@{
        lane = $laneName
        task = $taskName
        process_present = ($null -ne $proc)
        process_id = $(if($proc){[int]$proc.ProcessId}else{$null})
        phase = $phase
        heartbeat_age_seconds = $age
        stale_limit_seconds = $limit
        reason = $reason
        restart_attempted = ($null -ne $reason)
        restart_started = $restarted
    }
}

try {
    [ordered]@{
        schema_version = 2
        generated_utc = [DateTime]::UtcNow.ToString("o")
        lane_count = @($checks).Count
        checks = $checks
        result = "PASS"
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LastCheckPath -Encoding UTF8
} catch {}

exit 0
