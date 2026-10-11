$ErrorActionPreference='Stop'
$name='Katarina-AnalogMemory-Observer'
$source=Get-ScheduledTask -TaskName 'Katarina-MarketBrain-Observer'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script=Join-Path $root 'scripts\research\probe_current_market_analogs.py'
$python='C:\KatarinaDev\brain-runtime\Scripts\python.exe'
$memory='C:\KatarinaDev\artifacts\historical-brain\frozen-per-symbol-analog-memory-v1.json'
$observer='C:\KatarinaDev\artifacts\multi-market-brain\latest.json'
$output='C:\KatarinaDev\artifacts\historical-brain\current-analog-shadow.json'
foreach($x in @($root,$script,$python,$memory,$observer)){if(!(Test-Path $x)){throw "Missing input: $x"}}
$arg='"'+$script+'" --memory "'+$memory+'" --observer "'+$observer+'" --output "'+$output+'"'
$action=New-ScheduledTaskAction -Execute $python -Argument $arg -WorkingDirectory $root
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal=New-ScheduledTaskPrincipal -UserId $source.Principal.UserId -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
$task=Get-ScheduledTask -TaskName $name
$info=Get-ScheduledTaskInfo -TaskName $name
Write-Output ('REGISTERED='+$task.TaskName)
Write-Output ('STATUS='+$task.State)
Write-Output ('NEXT_RUN='+$info.NextRunTime)
Write-Output ('EXECUTE='+$task.Actions[0].Execute)
Write-Output ('ARGUMENTS='+$task.Actions[0].Arguments)
