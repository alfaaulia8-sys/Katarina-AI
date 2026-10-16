# Foreground, bounded source sync/pretrial. No scheduler, model download or order API.
param(
  [ValidateSet('Audit','Sync','Pretrial')][string]$Mode='Audit',
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedCommit,
  [string]$SourceRoot='C:\KatarinaGitBridge',
  [string]$PythonExe='',
  [string]$StateRoot='C:\KatarinaDev\state\owner-pretrial'
)
$ErrorActionPreference='Stop'
$env:GIT_TERMINAL_PROMPT='0'
$env:GCM_INTERACTIVE='Never'
$report=@{schema_version=1;mode=$Mode;observed_utc=[DateTime]::UtcNow.ToString('o');
  expected_commit=$ExpectedCommit;ok=$false;status='BLOCKED';orders_submitted=0;live_execution_authorized=$false}
function Git-Value([string[]]$Arguments) {
  $previous=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    $out=@(& git.exe -c credential.interactive=never -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 -C $SourceRoot @Arguments 2>&1)
    $code=$LASTEXITCODE
  } finally {$ErrorActionPreference=$previous}
  if($code -ne 0){throw 'GIT_OPERATION_FAILED'}
  return (($out | ForEach-Object {[string]$_}) -join "`n").Trim()
}
function Run-Bounded([string]$Exe,[string]$Arguments,[int]$Timeout=30) {
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$Exe;$psi.Arguments=$Arguments;$psi.WorkingDirectory=$SourceRoot
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $p=New-Object System.Diagnostics.Process
  $p.StartInfo=$psi
  try {
    $null=$p.Start()
    # Drain both streams concurrently so a full stderr pipe cannot deadlock.
    # Use the owned .NET Process directly: legacy Start-Process can lose ExitCode.
    $stdout=$p.StandardOutput.ReadToEndAsync()
    $stderr=$p.StandardError.ReadToEndAsync()
    if(!$p.WaitForExit($Timeout*1000)) {
      $p.Kill();$p.WaitForExit();throw 'OWN_CHILD_TIMEOUT'
    }
    $p.WaitForExit()
    if($p.ExitCode -ne 0){throw 'PYTHON_COMMAND_FAILED'}
    $text=$stdout.Result
    if($text.Length -gt 1048576){throw 'CHILD_OUTPUT_TOO_LARGE'}
    return $text
  } finally {$p.Dispose()}
}
try {
  if(!(Test-Path -LiteralPath (Join-Path $SourceRoot '.git'))){throw 'SOURCE_REPOSITORY_REQUIRED'}
  $origin=Git-Value -Arguments @('remote','get-url','origin')
  if($origin -notmatch '^(https://github\.com/|git@github\.com:)alfaauliau-katarinaAI/Katarina-AI(?:\.git)?$'){throw 'SOURCE_ORIGIN_REJECTED'}
  $report.source_commit=Git-Value -Arguments @('rev-parse','HEAD')
  $report.source_matches=($report.source_commit -ceq $ExpectedCommit)
  $report.working_tree_clean=([string]::IsNullOrEmpty((Git-Value -Arguments @('status','--porcelain'))))
  $report.terminal_process_count=@(Get-Process terminal64 -ErrorAction SilentlyContinue).Count
  $report.brain_process_count=@(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'run_contextual_market_observer|run_assistant\.py|katarina_pc\.py|brain_observer')
  }).Count
  if($Mode -eq 'Sync') {
    if(!$report.working_tree_clean){throw 'SOURCE_DIRTY_NO_AUTOSTASH_OR_RESET'}
    if($report.brain_process_count -gt 0){throw 'BRAIN_RUNNING_SYNC_REFUSED'}
    if((Git-Value -Arguments @('branch','--show-current')) -cne 'main'){throw 'MAIN_BRANCH_REQUIRED'}
    # A fetch/moving main never silently changes the pinned approved destination.
    $null=Git-Value -Arguments @('fetch','--no-tags','origin','main')
    if((Git-Value -Arguments @('rev-parse','FETCH_HEAD')) -cne $ExpectedCommit){throw 'MAIN_MOVED_REVALIDATE_COMMIT'}
    $null=Git-Value -Arguments @('merge-base','--is-ancestor','HEAD',$ExpectedCommit)
    $null=Git-Value -Arguments @('merge','--ff-only',$ExpectedCommit)
    $report.source_commit=Git-Value -Arguments @('rev-parse','HEAD')
    $report.source_matches=($report.source_commit -ceq $ExpectedCommit)
    if(!$report.source_matches){throw 'SOURCE_COMMIT_MISMATCH'}
  }
  if(!$PythonExe) {
    foreach($candidate in @('C:\KatarinaDev\runtime\python\python.exe','C:\KatarinaDev\runtime\python312\python.exe','C:\Python312\python.exe')) {
      if(Test-Path -LiteralPath $candidate -PathType Leaf){$PythonExe=$candidate;break}
    }
    if(!$PythonExe){$cmd=Get-Command python.exe -ErrorAction SilentlyContinue;if($cmd){$PythonExe=$cmd.Source}}
  }
  $report.python_found=([bool]$PythonExe -and (Test-Path -LiteralPath $PythonExe -PathType Leaf))
  if($report.python_found) {
    # Fixed probe, no caller-provided Python or shell text.
    $code="import sys,json,importlib.util;print(json.dumps(dict(version=list(sys.version_info[:3]),numpy=importlib.util.find_spec('numpy') is not None,mt5=importlib.util.find_spec('MetaTrader5') is not None)))"
    $probeArguments='-c "'+$code+'"'
    $report.python=(Run-Bounded $PythonExe $probeArguments 15)|ConvertFrom-Json
  }
  $report.mt5_installations=@()
  foreach($terminal in @('C:\Program Files\MetaTrader 5 ALFA\terminal64.exe','C:\KatarinaDev\runtime\mt5-research\terminal64.exe','C:\Program Files\MetaTrader 5\terminal64.exe')) {
    if(Test-Path -LiteralPath $terminal -PathType Leaf){$report.mt5_installations+=@{path=$terminal;file_version=(Get-Item -LiteralPath $terminal).VersionInfo.FileVersion}}
  }
  if($Mode -eq 'Pretrial') {
    if(!$report.source_matches){throw 'SOURCE_COMMIT_MISMATCH'}
    if($report.brain_process_count -gt 0){throw 'BRAIN_RUNNING_PRETRIAL_REFUSED'}
    if(!$report.python_found -or $report.python.version[0] -ne 3 -or $report.python.version[1] -ne 12){throw 'PYTHON312_REQUIRED'}
    if(!$report.python.numpy){throw 'NUMPY_DEPENDENCY_REQUIRED'}
    $state=Join-Path $StateRoot $ExpectedCommit
    $script=Join-Path $SourceRoot 'scripts\pc\run_pretrial_acceptance.py'
    $null=Run-Bounded $PythonExe ('"'+$script+'" --state-dir "'+$state+'"') 120
    $result=Get-Content -LiteralPath (Join-Path $state 'pretrial-report\latest-pc-test.json') -Raw | ConvertFrom-Json
    if($result.status -ne 'PASS_SYNTHETIC_PRETRIAL_ONLY' -or $result.orders_sent -ne 0 -or $result.live_authorized){throw 'PRETRIAL_NOT_SAFE_PASS'}
    $report.pretrial_status=$result.status;$report.pretrial_checks=@($result.checks)
  }
  $report.ok=$true;$report.status=($Mode.ToUpperInvariant()+'_COMPLETE_LIVE_OFF')
} catch {
  # Exceptions can contain paths, account IDs, endpoints or tokens. Return codes only.
  $safe=@('CHILD_OUTPUT_TOO_LARGE','GIT_OPERATION_FAILED','OWN_CHILD_TIMEOUT','PYTHON_COMMAND_FAILED','SOURCE_REPOSITORY_REQUIRED','SOURCE_ORIGIN_REJECTED','SOURCE_DIRTY_NO_AUTOSTASH_OR_RESET','BRAIN_RUNNING_SYNC_REFUSED','MAIN_BRANCH_REQUIRED','MAIN_MOVED_REVALIDATE_COMMIT','SOURCE_COMMIT_MISMATCH','BRAIN_RUNNING_PRETRIAL_REFUSED','PYTHON312_REQUIRED','NUMPY_DEPENDENCY_REQUIRED','PRETRIAL_NOT_SAFE_PASS')
  $message=$_.Exception.Message
  $report.reason=$(if($message -in $safe){$message}else{'PREFLIGHT_OPERATION_FAILED'})
  $report.error_type=$_.Exception.GetType().Name
}
$report | ConvertTo-Json -Depth 8
