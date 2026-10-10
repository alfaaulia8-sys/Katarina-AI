# KATARINA VPS self-healing health monitor (Windows PowerShell 5.x).
# Only retries our own stalled scheduled jobs; never alters sessions, cookies, credentials, or Termux remotely.
param([switch]$Repair)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$stateDir = 'C:\KatarinaVPSControl\state'
if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory -Force | Out-Null }
$checks = @()
$repairs = @()
$now = Get-Date

foreach ($n in @('KatarinaVPSControlAgent','ProjectPushZeroCostRadar','ProjectPushFulfillmentHourly','KATARINA-MQL5-OfflineQueue','KATARINA-DriveBridge-15min','ProjectPushVpsDebianBrowserHourly')) {
    $task = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    $info = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
    if (-not $task) { $checks += [pscustomobject]@{name=$n; status='MISSING'; lastResult=$null; minutesSinceRun=$null}; continue }
    $mins = $null
    if ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2020) {
        $mins = [math]::Round(($now - $info.LastRunTime).TotalMinutes, 1)
    }
    $state = "$($task.State)"
    $status = if ($state -eq 'Disabled') {'DISABLED'} elseif ($state -eq 'Running') {'RUNNING'} elseif ($info -and $info.LastTaskResult -eq 0) {'SCHEDULE_OK'} else {'NEEDS_REVIEW'}
    $checks += [pscustomobject]@{name=$n; status=$status; state=$state; lastResult=if($info){$info.LastTaskResult}else{$null}; minutesSinceRun=$mins}
    $retryable = @('ProjectPushZeroCostRadar','ProjectPushFulfillmentHourly','KATARINA-MQL5-OfflineQueue')
    if ($Repair -and $retryable -contains $n -and $state -eq 'Ready' -and $mins -ne $null -and $mins -gt 130) {
        try { Start-ScheduledTask -TaskName $n -ErrorAction Stop; $repairs += "START_REQUESTED: $n" }
        catch { $repairs += ("START_FAILED: "+$n+" "+$_.Exception.Message) }
    }
}

# Agent is a long-running task; Task Scheduler reports an 'active' task nonzero code while running.
$agent = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*KatarinaVPSAgent.ps1*' -and $_.CommandLine -notlike '*healthwatch*' }
$checks += [pscustomobject]@{name='VPS_CONTROL_AGENT_PROCESS'; status=if($agent){'RUNNING'}else{'MISSING'}; instances=@($agent).Count}
if ($Repair -and -not $agent) {
    $t = Get-ScheduledTask -TaskName 'KatarinaVPSControlAgent' -ErrorAction SilentlyContinue
    if ($t -and $t.State -eq 'Ready') {
        try { Start-ScheduledTask -TaskName 'KatarinaVPSControlAgent' -ErrorAction Stop; $repairs += 'START_REQUESTED: VPS control agent' }
        catch { $repairs += ('START_FAILED: VPS control agent '+$_.Exception.Message) }
    }
}

foreach ($hostAndUrl in @(
    @{name='GitHub';url='https://api.github.com/rate_limit'},
    @{name='MQL5';url='https://www.mql5.com/en/job'},
    @{name='Google';url='https://www.google.com/generate_204'})) {
    try {
        $r = Invoke-WebRequest -Uri $hostAndUrl.url -UseBasicParsing -TimeoutSec 9 -ErrorAction Stop
        $checks += [pscustomobject]@{name=('HTTPS_'+$hostAndUrl.name);status=if($r.StatusCode -lt 400){'OK'}else{'ERROR'};http=$r.StatusCode}
    } catch {
        $checks += [pscustomobject]@{name=('HTTPS_'+$hostAndUrl.name);status='ERROR';message=$_.Exception.Message}
    }
}

# A successful Windows Task Scheduler exit code does not prove Google Drive OAuth is authorized.
$bridgeScript = 'C:\ProjectPush\drive-bridge\drive-worker.js'
$node = 'C:\Program Files\nodejs\node.exe'
if ((Test-Path $bridgeScript) -and (Test-Path $node)) {
    try {
        $raw = & $node $bridgeScript check 2>&1
        $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        $checks += [pscustomobject]@{name='GOOGLE_DRIVE_BRIDGE';status=if($result.ok){'READY'}else{'OAUTH_PENDING'};reason=$result.reason;verified=$result.remote_root_verified}
    } catch {
        $checks += [pscustomobject]@{name='GOOGLE_DRIVE_BRIDGE';status='CHECK_FAILED';message=$_.Exception.Message}
    }
}
# Android/Termux requires its own authenticated relay; VPS cannot power-on that device.
$checks += [pscustomobject]@{name='TERMUX_RELAY';status='CHECK_VIA_REMOTE_DESKTOP_COMMANDER';note='Cannot reboot Android remotely when agent is offline.'}

$report = [ordered]@{ checked_at=$now.ToString('o'); mode=if($Repair){'repair'}else{'check'}; checks=$checks; repairs=$repairs }
$json = $report | ConvertTo-Json -Depth 7
$tmp = Join-Path $stateDir 'katarina-healthwatch.tmp'
$dest = Join-Path $stateDir 'katarina-healthwatch.json'
[System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
Move-Item -Path $tmp -Destination $dest -Force
Write-Output ("KATARINA_HEALTHWATCH checked="+$checks.Count+" actions="+$repairs.Count+" report="+$dest)
$checks | Format-Table -Property name,status -AutoSize
if ($repairs.Count) { $repairs | ForEach-Object {Write-Output ("ACTION: "+$_)} }

