# Restore the ORIGINAL Katarina-VPS-Control GitHub bridge only.
# Designed for Windows Server 2012 R2 / PowerShell 4+, no trading operations.
# Safe: no resets, deletes, credentials, MetaTrader or unrelated tasks.
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = 'C:\KatarinaVPSControl'
$repo = Join-Path $root 'repo'
$agent = Join-Path $repo 'agent\KatarinaVPSAgent.ps1'
$taskName = 'KatarinaVPSControlAgent'
$remote = 'https://github.com/alfaauliau-katarinaAI/Katarina-VPS-Control.git'

function Emit([string]$status,[string]$detail) {
    Write-Output ('KATARINA_CONTROL_RECOVERY ' + $status + ' ' + $detail)
}

$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($ident)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Emit 'BLOCKED' 'Run PowerShell as Administrator.'
    exit 2
}
if ($env:COMPUTERNAME -ne 'WIN-4TTT19K3CL8') {
    Emit 'BLOCKED' 'Unexpected machine. No changes made.'
    exit 3
}

Emit 'CHECK' ('script_exists=' + (Test-Path -LiteralPath $agent -PathType Leaf))
Emit 'CHECK' ('repo_exists=' + (Test-Path -LiteralPath $repo -PathType Container))
Emit 'CHECK' ('auth_profile_pointer_exists=' + (Test-Path -LiteralPath (Join-Path $root 'state\git-profile.path') -PathType Leaf))

if (-not (Test-Path -LiteralPath $agent -PathType Leaf)) {
    if (Test-Path -LiteralPath $repo) {
        Emit 'BLOCKED' 'Existing control repository has no agent script. Nothing overwritten.'
        exit 4
    }
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Emit 'BLOCKED' 'git.exe missing. Nothing downloaded.'
        exit 5
    }
    if ($DryRun) {
        Emit 'PLAN' 'Clone private control repository with existing Windows Git authorization.'
        return
    }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $stage = Join-Path $root ('repo.recovery.' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
    if (Test-Path -LiteralPath $stage) {
        Emit 'BLOCKED' 'Recovery stage already exists; refusing overwrite.'
        exit 6
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'
    $save = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & git.exe clone --no-tags --single-branch --branch main $remote $stage 2>&1 | Out-Null
        $cloneExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $save
    }
    if ($cloneExit -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $stage 'agent\KatarinaVPSAgent.ps1'))) {
        Emit 'BLOCKED' 'Private clone unavailable with existing Git authorization. Do not share credentials.'
        exit 7
    }
    Move-Item -LiteralPath $stage -Destination $repo -ErrorAction Stop
    Emit 'RESTORED' 'Private control checkout created; no other repository changed.'
}

# Verify that an existing checkout is from the intended GitHub repository.
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
    Emit 'BLOCKED' 'Control checkout has no Git metadata. Refusing to trust it.'
    exit 8
}
$origin = ''
try {
    $origin = (& git.exe -C $repo remote get-url origin 2>$null | Select-Object -First 1)
} catch {
    Emit 'BLOCKED' 'Cannot verify control repository origin.'
    exit 9
}
if ($origin -notmatch '^(https://github\.com/|git@github\.com:)(?:alfaaulia8-sys|alfaauliau-katarinaAI)/Katarina-VPS-Control(?:\.git)?$') {
    Emit 'BLOCKED' 'Unexpected control repository origin; no scheduled task changed.'
    exit 10
}

$found = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Emit 'CHECK' ('existing_task=' + [bool]$existing + ' agent_processes=' + $found.Count)

if ($DryRun) {
    Emit 'PLAN' 'Register or correct only KatarinaVPSControlAgent, start if not running.'
    return
}

$action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $agent + '" -Root "' + $root + '"')
if (-not $existing) {
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Emit 'REPAIRED' 'Missing existing control task re-registered.'
} else {
    $validAction = @($existing.Actions | Where-Object {
        $_.Arguments -and $_.Arguments.IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -ge 0
    }).Count -gt 0
    if (-not $validAction) {
        Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null
        Emit 'REPAIRED' 'Existing control task action corrected.'
    }
    if ($existing.State -eq 'Disabled') {
        Enable-ScheduledTask -TaskName $taskName | Out-Null
        Emit 'REPAIRED' 'Existing control task enabled.'
    }
}
if ($found.Count -eq 0) {
    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Emit 'STARTED' 'Requested original GitHub VPS control agent.'
} else {
    Emit 'SKIPPED' 'Agent already running; no duplicate started.'
}
Start-Sleep -Seconds 8
$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
$current = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Emit 'RESULT' ('task_state=' + $current.State + ' agent_processes=' + $running.Count)
if ($running.Count -eq 0) {
    Emit 'BLOCKED' 'Agent exited. Check C:\KatarinaVPSControl\agent.log without sharing secrets.'
    exit 11
}
Emit 'PASS' 'Original control agent running. Wait 60-90 seconds for GitHub job receipt.'
