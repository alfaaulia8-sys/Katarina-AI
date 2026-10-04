param(
    [string]$InstallRoot = "C:\KatarinaVPSAgent",
    [int]$CheckSeconds = 5,
    [int]$StaleSeconds = 35,
    [int]$RestartCooldownSeconds = 45
)

$ErrorActionPreference = "Continue"

$SupervisorMutex = New-Object Threading.Mutex($false,"Global\KatarinaControlSupervisor")
$SupervisorAcquired = $false
try { $SupervisorAcquired = $SupervisorMutex.WaitOne(0,$false) } catch { $SupervisorAcquired = $false }
if(-not $SupervisorAcquired) { exit 0 }

$LogPath = Join-Path $InstallRoot "control_supervisor.log"
$StateRoot = Join-Path $InstallRoot "supervisor"
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

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
    } catch { return $null }
}

function Get-AgentProcess([string]$ConfigPath) {
    try {
        return @(
            Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($ConfigPath,[StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        ) | Select-Object -First 1
    } catch { return $null }
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
    $path=Join-Path $StateRoot ($Lane+".json")
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){ return $null }
    try {
        $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return Read-Utc $state.last_restart_utc
    } catch { return $null }
}

function Save-Restart([string]$Lane,[string]$Reason) {
    $path=Join-Path $StateRoot ($Lane+".json")
    [ordered]@{
        schema_version=1
        lane=$Lane
        reason=$Reason
        last_restart_utc=[DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Restart-Lane($LaneInfo,[string]$Reason) {
    $now=[DateTime]::UtcNow
    $last=Get-LastRestart $LaneInfo.lane
    if($null -ne $last -and (($now-$last).TotalSeconds -lt $RestartCooldownSeconds)) {
        Log-Line ("restart suppressed lane={0} reason={1}" -f $LaneInfo.lane,$Reason)
        return
    }

    Log-Line ("restart lane={0} reason={1}" -f $LaneInfo.lane,$Reason)
    $proc=Get-AgentProcess $LaneInfo.config
    if($null -ne $proc) {
        try { [void]$proc.Terminate() } catch {}
        Start-Sleep -Seconds 1
    }
    try { & schtasks.exe /End /TN $LaneInfo.task | Out-Null } catch {}
    Start-Sleep -Seconds 1
    & schtasks.exe /Run /TN $LaneInfo.task | Out-Null
    if($LASTEXITCODE -eq 0) {
        Save-Restart $LaneInfo.lane $Reason
        Log-Line ("restart success lane={0}" -f $LaneInfo.lane)
    } else {
        Log-Line ("restart failed lane={0} exit={1}" -f $LaneInfo.lane,$LASTEXITCODE)
    }
}

$lanes=@(
    [pscustomobject]@{
        lane="primary"; task="KatarinaVPSAgent";
        config=(Join-Path $InstallRoot "agent.json");
        heartbeat=(Join-Path $InstallRoot "lanes\primary\heartbeat.json");
        fallback=(Join-Path $InstallRoot "heartbeat.json")
    },
    [pscustomobject]@{
        lane="recovery"; task="KatarinaControlRecovery";
        config=(Join-Path $InstallRoot "agent-recovery.json");
        heartbeat=(Join-Path $InstallRoot "lanes\recovery\heartbeat.json");
        fallback=""
    },
    [pscustomobject]@{
        lane="worker01"; task="KatarinaControlWorker01";
        config=(Join-Path $InstallRoot "agent-worker01.json");
        heartbeat=(Join-Path $InstallRoot "lanes\worker01\heartbeat.json");
        fallback=""
    },
    [pscustomobject]@{
        lane="worker02"; task="KatarinaControlWorker02";
        config=(Join-Path $InstallRoot "agent-worker02.json");
        heartbeat=(Join-Path $InstallRoot "lanes\worker02\heartbeat.json");
        fallback=""
    }
)

Log-Line "supervisor started"

while($true) {
    foreach($lane in $lanes) {
        if(!(Test-Path -LiteralPath $lane.config -PathType Leaf)){ continue }

        $heartbeat=Get-Heartbeat $lane.heartbeat $lane.fallback
        $proc=Get-AgentProcess $lane.config
        $reason=$null

        if($null -eq $proc) {
            $reason="PROCESS_MISSING"
        } elseif($null -eq $heartbeat) {
            $reason="HEARTBEAT_MISSING"
        } else {
            $updated=Read-Utc $heartbeat.updated_utc
            if($null -eq $updated) {
                $reason="HEARTBEAT_INVALID"
            } else {
                $age=([DateTime]::UtcNow-$updated).TotalSeconds
                if($age -gt $StaleSeconds) {
                    $reason=("HEARTBEAT_STALE_{0}s" -f [int]$age)
                }
            }
        }

        if($null -ne $reason) {
            Restart-Lane $lane $reason
        }
    }
    Start-Sleep -Seconds $CheckSeconds
}
