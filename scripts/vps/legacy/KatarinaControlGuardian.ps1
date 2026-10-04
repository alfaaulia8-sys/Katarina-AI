param(
    [string]$InstallRoot = "C:\KatarinaVPSAgent",
    [string]$PrimaryTaskName = "KatarinaVPSAgent",
    [int]$CheckSeconds = 10,
    [int]$StaleSeconds = 45,
    [int]$RestartCooldownSeconds = 45
)

$ErrorActionPreference = "Continue"

$GuardianVersion = "1.0.0"
$PrimaryConfig = Join-Path $InstallRoot "agent.json"
$PrimaryHeartbeat = Join-Path $InstallRoot "lanes\primary\heartbeat.json"
$LegacyHeartbeat = Join-Path $InstallRoot "heartbeat.json"
$StateRoot = Join-Path $InstallRoot "guardian"
$GuardianHeartbeat = Join-Path $StateRoot "heartbeat.json"
$GuardianState = Join-Path $StateRoot "state.json"
$GuardianLog = Join-Path $StateRoot "guardian.log"

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

$mutex = New-Object System.Threading.Mutex($false,"Global\KatarinaControlGuardian")
$acquired = $false
try { $acquired = $mutex.WaitOne(0,$false) } catch { $acquired = $false }
if(-not $acquired) { exit 0 }

function Write-GuardianJson([string]$Path,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Log-Line([string]$Text) {
    try {
        Add-Content -LiteralPath $GuardianLog -Value ("[{0}] {1}" -f [DateTime]::UtcNow.ToString("o"),$Text) -Encoding UTF8
    } catch {}
}

function Read-Utc([object]$Value) {
    if($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        return [DateTime]::Parse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
    } catch { return $null }
}

function Get-PrimaryProcess {
    try {
        return @(
            Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($PrimaryConfig,[StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        ) | Select-Object -First 1
    } catch { return $null }
}

function Get-PrimaryHeartbeat {
    foreach($candidate in @($PrimaryHeartbeat,$LegacyHeartbeat)) {
        if(Test-Path -LiteralPath $candidate -PathType Leaf) {
            try { return Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json } catch {}
        }
    }
    return $null
}

function Get-LastRestartUtc {
    if(!(Test-Path -LiteralPath $GuardianState -PathType Leaf)) { return $null }
    try {
        $state=Get-Content -LiteralPath $GuardianState -Raw | ConvertFrom-Json
        return Read-Utc $state.last_restart_utc
    } catch { return $null }
}

function Save-Restart([string]$Reason,[bool]$Started) {
    Write-GuardianJson $GuardianState ([ordered]@{
        schema_version=1
        guardian_version=$GuardianVersion
        last_restart_utc=[DateTime]::UtcNow.ToString("o")
        reason=$Reason
        started=$Started
    })
}

function Write-GuardianHeartbeat([string]$Phase,[string]$Reason,[object]$Primary,[object]$Heartbeat,[object]$Age) {
    $primaryPid=$null
    if($null -ne $Primary) {
        try { $primaryPid=[int]$Primary.ProcessId } catch {}
    }
    $primaryPhase=""
    $primaryVersion=""
    if($null -ne $Heartbeat) {
        try { $primaryPhase=[string]$Heartbeat.phase } catch {}
        try { $primaryVersion=[string]$Heartbeat.agent_version } catch {}
    }
    Write-GuardianJson $GuardianHeartbeat ([ordered]@{
        schema_version=1
        guardian_version=$GuardianVersion
        process_id=$PID
        phase=$Phase
        reason=$Reason
        primary_process_id=$primaryPid
        primary_agent_version=$primaryVersion
        primary_phase=$primaryPhase
        primary_heartbeat_age_seconds=$Age
        updated_utc=[DateTime]::UtcNow.ToString("o")
    })
}

Log-Line "guardian started"

while($true) {
    $now=[DateTime]::UtcNow
    $primary=Get-PrimaryProcess
    $hb=Get-PrimaryHeartbeat
    $age=$null
    $reason=$null

    if($null -eq $primary) {
        $reason="PRIMARY_PROCESS_MISSING"
    } elseif($null -eq $hb) {
        $reason="PRIMARY_HEARTBEAT_MISSING"
    } else {
        $updated=Read-Utc $hb.updated_utc
        if($null -eq $updated) {
            $reason="PRIMARY_HEARTBEAT_INVALID"
        } else {
            $age=[math]::Round(($now-$updated).TotalSeconds,1)
            if($age -gt $StaleSeconds) {
                $reason=("PRIMARY_HEARTBEAT_STALE_{0}s" -f [int]$age)
            }
        }
    }

    if($null -eq $reason) {
        Write-GuardianHeartbeat "HEALTHY" "" $primary $hb $age
        Start-Sleep -Seconds $CheckSeconds
        continue
    }

    $lastRestart=Get-LastRestartUtc
    if($null -ne $lastRestart -and (($now-$lastRestart).TotalSeconds -lt $RestartCooldownSeconds)) {
        Write-GuardianHeartbeat "COOLDOWN" $reason $primary $hb $age
        Start-Sleep -Seconds $CheckSeconds
        continue
    }

    Log-Line ("recovery triggered reason=" + $reason)
    Write-GuardianHeartbeat "RECOVERING" $reason $primary $hb $age

    if($null -ne $primary) {
        try { [void]$primary.Terminate() } catch {}
        Start-Sleep -Seconds 1
    }
    try { & schtasks.exe /End /TN $PrimaryTaskName | Out-Null } catch {}
    Start-Sleep -Seconds 1
    & schtasks.exe /Run /TN $PrimaryTaskName | Out-Null
    $started=($LASTEXITCODE -eq 0)
    Save-Restart $reason $started

    if($started) {
        Log-Line ("primary restart started reason=" + $reason)
    } else {
        Log-Line ("primary restart failed reason=" + $reason + " exit=" + [string]$LASTEXITCODE)
    }

    Start-Sleep -Seconds $CheckSeconds
}
