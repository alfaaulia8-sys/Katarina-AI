param(
    [string]$Python = 'C:\KatarinaDev\brain-runtime\Scripts\python.exe',
    [string]$Terminal = 'C:\Program Files\MetaTrader 5 ALFA\terminal64.exe',
    [string]$StateDir = 'C:\KatarinaDev\artifacts\multi-market-brain'
)
$ErrorActionPreference = 'Stop'
$taskName = 'Katarina-MarketBrain-Observer'
$script = Join-Path $PSScriptRoot 'run_market_brain.py'
foreach ($file in @($Python,$Terminal,$script)) {
    if (-not (Test-Path $file)) { throw "Missing dependency: $file" }
}
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    throw 'Observer task already exists; inspect it instead of overwriting.'
}
$arguments = '"' + $script + '" --terminal "' + $Terminal + '" --state-dir "' + $StateDir + '" --cycles 1'
$action = New-ScheduledTaskAction -Execute $Python -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Read-only broker/news observer; no order API; research state only.' | Out-Null
Start-ScheduledTask -TaskName $taskName
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State
