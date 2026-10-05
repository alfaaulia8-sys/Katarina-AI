param(
    [ValidateSet("Setup","Build","Bridge","Publish","Stop","Status")]
    [string]$Mode = "Setup",
    [string]$RepoRoot = "",
    [switch]$Publish
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptRoot "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$RuntimeRoot = "C:\KatarinaRuntime"
$ConfigPath = Join-Path $RuntimeRoot "vps-local.json"
$StatePath = Join-Path $RuntimeRoot "bridge-state.json"
$BridgePidPath = Join-Path $RuntimeRoot "bridge.pid"
$StopPath = Join-Path $RuntimeRoot "STOP"
$ReportsRoot = Join-Path $RuntimeRoot "reports"
$InboxRoot = Join-Path $RuntimeRoot "inbox"
$OutboxRoot = Join-Path $RuntimeRoot "outbox"
$ControlBranch = "vps-control"
$ReportsBranch = "vps-reports"
$PublishMode = "FAIL_OR_FINAL"

function Ensure-Directories {
    foreach ($p in @($RuntimeRoot,$ReportsRoot,$InboxRoot,$OutboxRoot)) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Force -Path $p | Out-Null
        }
    }
}

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}
}

function Get-PropertyValue {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Write-JsonFile {
    param($Object,[string]$Path)
    ($Object | ConvertTo-Json -Depth 12) | Out-File -LiteralPath $Path -Encoding utf8
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Resolve-Git {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.PSObject.Properties["Path"] -and $cmd.Path) { return [string]$cmd.Path }
        if ($cmd.PSObject.Properties["Definition"] -and $cmd.Definition) { return [string]$cmd.Definition }
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $env:PATH = (Split-Path -Parent $candidate) + ";" + $env:PATH
            return $candidate
        }
    }
    return $null
}

function Resolve-Python {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $pythonPath = $null
        if ($cmd.PSObject.Properties["Path"] -and $cmd.Path) { $pythonPath = [string]$cmd.Path }
        elseif ($cmd.PSObject.Properties["Definition"] -and $cmd.Definition) { $pythonPath = [string]$cmd.Definition }
        if ($pythonPath) { return [pscustomobject]@{ File=$pythonPath; Prefix=@() } }
    }
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        $pyPath = $null
        if ($py.PSObject.Properties["Path"] -and $py.Path) { $pyPath = [string]$py.Path }
        elseif ($py.PSObject.Properties["Definition"] -and $py.Definition) { $pyPath = [string]$py.Definition }
        if ($pyPath) { return [pscustomobject]@{ File=$pyPath; Prefix=@("-3") } }
    }
    foreach ($root in @((Join-Path $env:LOCALAPPDATA "Programs\Python"),"C:\Python312","C:\Python311","C:\Python310")) {
        if ($root -and (Test-Path -LiteralPath $root -PathType Container)) {
            $found = Get-ChildItem -LiteralPath $root -Filter python.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return [pscustomobject]@{ File=$found.FullName; Prefix=@() } }
        }
    }
    return $null
}

function Quote-Argument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"','\"') + '"'
}

function Invoke-Captured {
    param(
        [string]$File,
        [string[]]$Arguments=@(),
        [string]$WorkingDirectory=$RepoRoot,
        [int]$TimeoutSeconds=0
    )
    $stdout=[IO.Path]::GetTempFileName()
    $stderr=[IO.Path]::GetTempFileName()
    try {
        $argLine=(($Arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join " ")
        $p=Start-Process -FilePath $File -ArgumentList $argLine -WorkingDirectory $WorkingDirectory -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden
        if ($TimeoutSeconds -gt 0) {
            $done=$p.WaitForExit($TimeoutSeconds*1000)
            if (-not $done) {
                try { $p.Kill() } catch {}
                return [pscustomobject]@{ExitCode=124;Stdout="";Stderr="TIMEOUT";Combined="TIMEOUT";TimedOut=$true}
            }
        } else {
            $p.WaitForExit()
        }
        $outText=""
        $errText=""
        if (Test-Path -LiteralPath $stdout) { $outText=Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderr) { $errText=Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue }
        return [pscustomobject]@{
            ExitCode=$p.ExitCode
            Stdout=[string]$outText
            Stderr=[string]$errText
            Combined=([string]$outText+[Environment]::NewLine+[string]$errText)
            TimedOut=$false
        }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GitCaptured {
    param([string[]]$Arguments,[int]$TimeoutSeconds=120)
    $git=Resolve-Git
    if (-not $git) {
        return [pscustomobject]@{ExitCode=127;Stdout="";Stderr="git.exe not found";Combined="git.exe not found";TimedOut=$false}
    }
    return Invoke-Captured -File $git -Arguments $Arguments -WorkingDirectory $RepoRoot -TimeoutSeconds $TimeoutSeconds
}

function Sanitize-Text {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $v=$Text
    $v=[regex]::Replace($v,'gh[opusr]_[A-Za-z0-9_]{20,}','[REDACTED_GITHUB_TOKEN]')
    $v=[regex]::Replace($v,'github_pat_[A-Za-z0-9_]{20,}','[REDACTED_GITHUB_TOKEN]')
    $v=[regex]::Replace($v,'sk-[A-Za-z0-9_-]{20,}','[REDACTED_API_KEY]')
    $v=[regex]::Replace($v,'(?im)(password|passwd|pwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s;]+','$1=[REDACTED]')
    return $v
}

function Ensure-LocalConfig {
    if (Test-Path -LiteralPath $ConfigPath) { return }
    $config=[ordered]@{
        schema_version=1
        repo_root=$RepoRoot
        control_branch=$ControlBranch
        reports_branch=$ReportsBranch
        poll_seconds=120
        publish_mode=$PublishMode
        metaeditor_path=""
        terminal_path=""
        mt5_data_path=""
        stage35=[ordered]@{
            enabled=$false
            expert=""
            symbol="XAUUSD"
            period="M1"
            from_date=""
            to_date=""
            report_name="KatarinaStage35"
            model=4
            deposit=10000
            leverage=100
            timeout_seconds=3600
            portable=$false
        }
        live_risk_ready=$false
        live_execution_enabled=$false
    }
    Write-JsonFile $config $ConfigPath
}

function Get-LocalConfig {
    Ensure-LocalConfig
    return Read-JsonFile $ConfigPath
}

function Find-Executable {
    param([string]$Explicit,[string]$Name)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return $Explicit }
    $roots=@()
    if ($env:ProgramFiles) { $roots+=$env:ProgramFiles }
    $pf86=[Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf86) { $roots+=$pf86 }
    foreach ($root in $roots) {
        $direct=Join-Path (Join-Path $root "MetaTrader 5") $Name
        if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
        $found=Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName $Name } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($found) { return [string]$found }
    }
    return $null
}

function Find-Mt5DataPath {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Container)) { return $Explicit }
    $root=Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $found=Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "MQL5") -PathType Container } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($found) { return Join-Path $found.FullName "MQL5" }
    return $null
}

function New-StepResult {
    param([string]$Name,[string]$Status,[int]$ExitCode,[string]$Detail)
    return [ordered]@{name=$Name;status=$Status;exit_code=$ExitCode;detail=(Sanitize-Text $Detail)}
}

function Invoke-PythonStep {
    param($Python,[string]$Name,[string[]]$Arguments,[System.Collections.ArrayList]$Steps,[System.Text.StringBuilder]$Log)
    $allArgs=@($Python.Prefix)+$Arguments
    [void]$Log.AppendLine("=== $Name ===")
    $r=Invoke-Captured -File $Python.File -Arguments $allArgs -WorkingDirectory $RepoRoot -TimeoutSeconds 1800
    [void]$Log.AppendLine($r.Combined)
    $status=if($r.ExitCode -eq 0){"PASS"}else{"FAIL"}
    [void]$Steps.Add((New-StepResult $Name $status $r.ExitCode $r.Combined))
    return ($r.ExitCode -eq 0)
}

function Compile-Mql5 {
    param([string]$MetaEditor,[string]$Mt5DataPath,[System.Collections.ArrayList]$Steps,[System.Text.StringBuilder]$Log,[string]$RunRoot)
    if (-not $MetaEditor) {
        [void]$Steps.Add((New-StepResult "MQL5_COMPILE" "BLOCKED" 20 "metaeditor64.exe not found"))
        return "BLOCKED"
    }
    if (-not $Mt5DataPath) {
        [void]$Steps.Add((New-StepResult "MQL5_COMPILE" "BLOCKED" 21 "MT5 data folder not found"))
        return "BLOCKED"
    }
    $includeSource=Join-Path $RepoRoot "mt5\Include\Katarina"
    $includeTarget=Join-Path $Mt5DataPath "Include\Katarina"
    if (-not (Test-Path -LiteralPath $includeSource -PathType Container)) {
        [void]$Steps.Add((New-StepResult "MQL5_COMPILE" "FAIL" 22 "Katarina include source missing"))
        return "FAIL"
    }
    New-Item -ItemType Directory -Force -Path $includeTarget | Out-Null
    Copy-Item -Path (Join-Path $includeSource "*") -Destination $includeTarget -Recurse -Force

    $compileRoot=Join-Path $RunRoot "mql5"
    New-Item -ItemType Directory -Force -Path $compileRoot | Out-Null
    $files=@()
    $files+=Get-ChildItem -LiteralPath (Join-Path $RepoRoot "mt5\Experts") -Filter *.mq5 -File -ErrorAction SilentlyContinue
    $files+=Get-ChildItem -LiteralPath (Join-Path $RepoRoot "mt5\Tests") -Filter *.mq5 -File -ErrorAction SilentlyContinue
    $failures=0
    foreach($file in $files) {
        $logPath=Join-Path $compileRoot ($file.BaseName+".log")
        $args=@(('/compile:"{0}"' -f $file.FullName),('/log:"{0}"' -f $logPath))
        $r=Invoke-Captured -File $MetaEditor -Arguments $args -WorkingDirectory (Split-Path -Parent $MetaEditor) -TimeoutSeconds 120
        Start-Sleep -Milliseconds 300
        $text=if(Test-Path -LiteralPath $logPath){Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue}else{$r.Combined}
        [void]$Log.AppendLine("=== MQL5 $($file.Name) ===")
        [void]$Log.AppendLine($text)
        $bad=(-not (Test-Path -LiteralPath $logPath)) -or ($text -match '(?im)\berror\s+\d+\s*:') -or ($text -match '(?im)\b[1-9]\d*\s+errors?\b')
        if($bad) {
            $failures++
            [void]$Steps.Add((New-StepResult ("MQL5_"+$file.Name) "FAIL" 24 $text))
        } else {
            [void]$Steps.Add((New-StepResult ("MQL5_"+$file.Name) "PASS" 0 $text))
        }
    }
    if($failures -gt 0){return "FAIL"}
    return "PASS"
}

function Invoke-Stage35 {
    param($Config,[string]$Terminal,[System.Collections.ArrayList]$Steps,[System.Text.StringBuilder]$Log)
    $s35=Get-PropertyValue $Config "stage35" $null
    if(-not [bool](Get-PropertyValue $s35 "enabled" $false)) {
        [void]$Steps.Add((New-StepResult "STAGE35_RUNTIME" "READY_NOT_RUN" 0 "Enable in C:\KatarinaRuntime\vps-local.json"))
        return "READY_NOT_RUN"
    }
    if(-not $Terminal) {
        [void]$Steps.Add((New-StepResult "STAGE35_RUNTIME" "BLOCKED" 30 "terminal64.exe not found"))
        return "BLOCKED"
    }
    $expert=[string](Get-PropertyValue $s35 "expert" "")
    $symbol=[string](Get-PropertyValue $s35 "symbol" "")
    $fromDate=[string](Get-PropertyValue $s35 "from_date" "")
    $toDate=[string](Get-PropertyValue $s35 "to_date" "")
    if(-not $expert -or -not $symbol -or -not $fromDate -or -not $toDate) {
        [void]$Steps.Add((New-StepResult "STAGE35_RUNTIME" "BLOCKED" 31 "Stage35 config incomplete"))
        return "BLOCKED"
    }
    $runner=Join-Path $RepoRoot "scripts\stage35\Run-KatarinaStage35Tester.ps1"
    $args=@("-NoProfile","-ExecutionPolicy","Bypass","-File",$runner,"-TerminalPath",$Terminal,"-Expert",$expert,"-Symbol",$symbol,
        "-Period",([string](Get-PropertyValue $s35 "period" "M1")),"-FromDate",$fromDate,"-ToDate",$toDate,
        "-ReportName",([string](Get-PropertyValue $s35 "report_name" "KatarinaStage35")),
        "-Model",([string](Get-PropertyValue $s35 "model" 4)),
        "-Deposit",([string](Get-PropertyValue $s35 "deposit" 10000)),
        "-Leverage",([string](Get-PropertyValue $s35 "leverage" 100)),
        "-TimeoutSeconds",([string](Get-PropertyValue $s35 "timeout_seconds" 3600)))
    if([bool](Get-PropertyValue $s35 "portable" $false)){$args+="-Portable"}
    $r=Invoke-Captured -File "powershell.exe" -Arguments $args -WorkingDirectory $RepoRoot -TimeoutSeconds ([int](Get-PropertyValue $s35 "timeout_seconds" 3600)+120)
    [void]$Log.AppendLine("=== STAGE35_RUNTIME ===")
    [void]$Log.AppendLine($r.Combined)
    $status=if($r.ExitCode -eq 0){"PASS"}else{"FAIL"}
    [void]$Steps.Add((New-StepResult "STAGE35_RUNTIME" $status $r.ExitCode $r.Combined))
    return $status
}

function Get-LocalDiff {
    [void](Invoke-GitCaptured @("fetch","origin","main:refs/remotes/origin/main") 120)
    $diff=Invoke-GitCaptured @("diff","--binary","origin/main...HEAD") 120
    if($diff.ExitCode -ne 0){$diff=Invoke-GitCaptured @("diff","--binary","origin/main") 120}
    return Sanitize-Text $diff.Stdout
}

function Publish-Report {
    Ensure-Directories
    $latestJson=Join-Path $ReportsRoot "latest.json"
    $latestLog=Join-Path $ReportsRoot "latest.log"
    $latestDiff=Join-Path $ReportsRoot "latest.diff"
    if(-not (Test-Path -LiteralPath $latestJson -PathType Leaf)){return $false}
    $git=Resolve-Git
    if(-not $git){
        "git.exe missing"|Out-File -LiteralPath (Join-Path $OutboxRoot "pending-report.txt") -Encoding utf8
        return $false
    }
    $fetch=Invoke-GitCaptured @("fetch","origin",($ReportsBranch+":refs/remotes/origin/"+$ReportsBranch)) 120
    if($fetch.ExitCode -ne 0){
        "fetch vps-reports failed"|Out-File -LiteralPath (Join-Path $OutboxRoot "pending-report.txt") -Encoding utf8
        return $false
    }
    $temp=Join-Path $env:TEMP ("KatarinaVpsReport-"+[Guid]::NewGuid().ToString("N"))
    try {
        $wt=Invoke-GitCaptured @("worktree","add","--detach",$temp,("origin/"+$ReportsBranch)) 120
        if($wt.ExitCode -ne 0){throw "worktree add failed"}
        $dest=Join-Path $temp "vps_bridge\reports"
        New-Item -ItemType Directory -Force -Path $dest|Out-Null
        Copy-Item -LiteralPath $latestJson -Destination (Join-Path $dest "latest.json") -Force
        if(Test-Path -LiteralPath $latestLog){(Sanitize-Text (Get-Content -LiteralPath $latestLog -Raw))|Out-File -LiteralPath (Join-Path $dest "latest.log") -Encoding utf8}
        if(Test-Path -LiteralPath $latestDiff){(Sanitize-Text (Get-Content -LiteralPath $latestDiff -Raw))|Out-File -LiteralPath (Join-Path $dest "latest.diff") -Encoding utf8}
        $add=Invoke-Captured -File $git -Arguments @("-C",$temp,"add","vps_bridge/reports") -WorkingDirectory $RepoRoot -TimeoutSeconds 120
        if($add.ExitCode -ne 0){throw "git add failed"}
        $status=Invoke-Captured -File $git -Arguments @("-C",$temp,"status","--porcelain") -WorkingDirectory $RepoRoot -TimeoutSeconds 120
        if(-not $status.Stdout.Trim()){
            Remove-Item -LiteralPath (Join-Path $OutboxRoot "pending-report.txt") -Force -ErrorAction SilentlyContinue
            return $true
        }
        $obj=Read-JsonFile $latestJson
        $result=[string](Get-PropertyValue $obj "result" "UNKNOWN")
        $runId=[string](Get-PropertyValue $obj "run_id" "unknown")
        $commit=Invoke-Captured -File $git -Arguments @("-C",$temp,"-c","user.name=KATARINA VPS","-c","user.email=katarina-vps@local.invalid","commit","-m",("vps-report: "+$runId+" "+$result)) -WorkingDirectory $RepoRoot -TimeoutSeconds 120
        if($commit.ExitCode -ne 0){throw "commit failed"}
        $push=Invoke-Captured -File $git -Arguments @("-C",$temp,"push","origin",("HEAD:refs/heads/"+$ReportsBranch)) -WorkingDirectory $RepoRoot -TimeoutSeconds 180
        if($push.ExitCode -ne 0){throw "push failed: "+$push.Combined}
        Remove-Item -LiteralPath (Join-Path $OutboxRoot "pending-report.txt") -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        $_.Exception.Message|Out-File -LiteralPath (Join-Path $OutboxRoot "pending-report.txt") -Encoding utf8
        return $false
    } finally {
        [void](Invoke-GitCaptured @("worktree","remove","--force",$temp) 60)
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    }
}

function Build-Katarina {
    param([bool]$PublishResult=$true)
    Ensure-Directories
    Enable-Tls12
    Ensure-LocalConfig
    $config=Get-LocalConfig
    $runId=[DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
    $runRoot=Join-Path $ReportsRoot $runId
    New-Item -ItemType Directory -Force -Path $runRoot|Out-Null
    $steps=New-Object System.Collections.ArrayList
    $log=New-Object System.Text.StringBuilder
    $sourceHead=(Invoke-GitCaptured @("rev-parse","HEAD") 60).Stdout.Trim()
    $currentBranch=(Invoke-GitCaptured @("rev-parse","--abbrev-ref","HEAD") 60).Stdout.Trim()
    $dirty=(Invoke-GitCaptured @("status","--porcelain") 60).Stdout.Trim()
    $python=Resolve-Python
    $overall="PASS"
    if(-not $python) {
        [void]$steps.Add((New-StepResult "PYTHON_ENV" "BLOCKED" 10 "python.exe / py.exe not found"))
        $overall="BLOCKED_PYTHON"
    } else {
        $env:PYTHONPATH=Join-Path $RepoRoot "src"
        $pythonSteps=@(
            @("PY_DEPS",@("-m","pip","install","--disable-pip-version-check","--only-binary=:all:","-r","requirements-stage07.txt")),
            @("PY_COMPILE",@("-m","compileall","-q","src")),
            @("UNIT_TESTS",@("-m","unittest","discover","-s","tests/unit","-p","test_*.py")),
            @("STATIC_TESTS",@("-m","unittest","discover","-s","tests/static","-p","test_*.py")),
            @("STAGE10_AUDIT",@("scripts/stage10/audit_stage10_final.py","--repo-root",".","--output",(Join-Path $runRoot "stage10.json"))),
            @("CONSTITUTION_GUARD",@("scripts/governance/audit_constitution_guard.py","--repo-root",".","--output",(Join-Path $runRoot "constitution.json"))),
            @("BODY_FRAMEWORK",@("scripts/body/audit_body_framework.py","--repo-root",".","--output",(Join-Path $runRoot "body-framework.json"))),
            @("BODY_FUNCTIONAL",@("scripts/body/audit_functional_body.py","--repo-root",".","--output",(Join-Path $runRoot "body-functional.json"))),
            @("CROSS_STAGE",@("scripts/body/audit_cross_stage_pipeline.py"))
        )
        foreach($pair in $pythonSteps){
            if(-not (Invoke-PythonStep $python $pair[0] $pair[1] $steps $log)){$overall="FAIL_PYTHON";break}
        }
    }

    $metaEditor=$null
    $terminal=$null
    $mt5Data=$null
    $mqlStatus="NOT_RUN"
    $stage35Status="NOT_RUN"
    if($overall -eq "PASS"){
        $metaEditor=Find-Executable ([string](Get-PropertyValue $config "metaeditor_path" "")) "metaeditor64.exe"
        $terminal=Find-Executable ([string](Get-PropertyValue $config "terminal_path" "")) "terminal64.exe"
        $mt5Data=Find-Mt5DataPath ([string](Get-PropertyValue $config "mt5_data_path" ""))
        $mqlStatus=Compile-Mql5 $metaEditor $mt5Data $steps $log $runRoot
        if($mqlStatus -eq "FAIL"){$overall="FAIL_MQL5"}
        elseif($mqlStatus -eq "BLOCKED"){$overall="BLOCKED_MT5_ENV"}
    }
    if($overall -eq "PASS"){
        $stage35Status=Invoke-Stage35 $config $terminal $steps $log
        if($stage35Status -eq "FAIL"){$overall="FAIL_STAGE35"}
        elseif($stage35Status -eq "BLOCKED"){$overall="BLOCKED_STAGE35"}
        elseif($stage35Status -eq "READY_NOT_RUN"){$overall="READY_FOR_MT5_TESTER"}
    }

    (Get-LocalDiff)|Out-File -LiteralPath (Join-Path $ReportsRoot "latest.diff") -Encoding utf8
    (Sanitize-Text $log.ToString())|Out-File -LiteralPath (Join-Path $ReportsRoot "latest.log") -Encoding utf8
    $report=[ordered]@{
        schema_version=1
        proof_type="KATARINA_VPS_2012R2_BUILD"
        run_id=$runId
        generated_utc=[DateTime]::UtcNow.ToString("o")
        os=[Environment]::OSVersion.VersionString
        powershell_version=$PSVersionTable.PSVersion.ToString()
        repo_root=$RepoRoot
        source_head=$sourceHead
        source_branch=$currentBranch
        working_tree_clean=(-not [bool]$dirty)
        metaeditor_path=$metaEditor
        terminal_path=$terminal
        mt5_data_path=$mt5Data
        mql5_status=$mqlStatus
        stage35_status=$stage35Status
        publish_mode=$PublishMode
        steps=$steps
        live_risk_ready=$false
        live_execution_enabled=$false
        result=$overall
    }
    $runJson=Join-Path $runRoot "report.json"
    $latestJson=Join-Path $ReportsRoot "latest.json"
    Write-JsonFile $report $runJson
    Copy-Item -LiteralPath $runJson -Destination $latestJson -Force
    Write-Host "KATARINA VPS BUILD: $overall"
    Write-Host "Report: $latestJson"
    Write-Host "Local config: $ConfigPath"
    if($PublishResult){[void](Publish-Report)}
    if($overall -like "FAIL*"){return 2}
    if($overall -like "BLOCKED*"){return 3}
    return 0
}

function Save-BridgeState {
    param([int]$Sequence,[string]$Action)
    Write-JsonFile ([ordered]@{schema_version=1;last_sequence=$Sequence;last_action=$Action;updated_utc=[DateTime]::UtcNow.ToString("o")}) $StatePath
}

function Get-LastSequence {
    $state=Read-JsonFile $StatePath
    if($null -eq $state){return -1}
    return [int](Get-PropertyValue $state "last_sequence" -1)
}

function Checkpoint-LocalChanges {
    $status=Invoke-GitCaptured @("status","--porcelain") 60
    if(-not $status.Stdout.Trim()){return $true}
    if((Invoke-GitCaptured @("add","-A") 60).ExitCode -ne 0){return $false}
    $commit=Invoke-GitCaptured @("-c","user.name=KATARINA VPS","-c","user.email=katarina-vps@local.invalid","commit","-m","vps-local: checkpoint before remote patch") 120
    return ($commit.ExitCode -eq 0)
}

function Apply-ControlPatch {
    param($Control)
    $patchPath=[string](Get-PropertyValue $Control "patch_path" "")
    if(-not $patchPath){throw "patch_path is empty"}
    $spec="origin/"+$ControlBranch+":"+$patchPath
    $show=Invoke-GitCaptured @("show",$spec) 120
    if($show.ExitCode -ne 0){throw "Unable to fetch patch"}
    $sequence=[int](Get-PropertyValue $Control "sequence" -1)
    $localPatch=Join-Path $InboxRoot ("control-"+$sequence+".patch")
    $show.Stdout|Out-File -LiteralPath $localPatch -Encoding ascii
    $expected=[string](Get-PropertyValue $Control "patch_sha256" "")
    if($expected){
        $sha=[Security.Cryptography.SHA256]::Create()
        try {
            $bytes=[IO.File]::ReadAllBytes($localPatch)
            $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","")
        } finally { $sha.Dispose() }
        if($actual.ToUpperInvariant() -ne $expected.ToUpperInvariant()){throw "Patch SHA256 mismatch"}
    }
    if(-not (Checkpoint-LocalChanges)){throw "Unable to checkpoint local changes"}
    $check=Invoke-GitCaptured @("apply","--check",$localPatch) 120
    if($check.ExitCode -ne 0){throw "git apply --check failed: "+$check.Combined}
    $apply=Invoke-GitCaptured @("apply",$localPatch) 120
    if($apply.ExitCode -ne 0){throw "git apply failed"}
    [void](Invoke-GitCaptured @("add","-A") 60)
    $commit=Invoke-GitCaptured @("-c","user.name=KATARINA VPS","-c","user.email=katarina-vps@local.invalid","commit","-m",("vps-local: apply control sequence "+$sequence)) 120
    if($commit.ExitCode -ne 0){throw "local commit failed"}
}

function Run-Bridge {
    Ensure-Directories
    Enable-Tls12
    Ensure-LocalConfig
    Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue
    $PID|Out-File -LiteralPath $BridgePidPath -Encoding ascii
    try {
        while($true){
            if(Test-Path -LiteralPath $StopPath){break}
            if(Test-Path -LiteralPath (Join-Path $OutboxRoot "pending-report.txt")){[void](Publish-Report)}
            $refspec=$ControlBranch+":refs/remotes/origin/"+$ControlBranch
            $fetch=Invoke-GitCaptured @("fetch","origin",$refspec) 120
            if($fetch.ExitCode -eq 0){
                $controlSpec="origin/"+$ControlBranch+":vps_bridge/control.json"
                $show=Invoke-GitCaptured @("show",$controlSpec) 60
                if($show.ExitCode -eq 0){
                    try {
                        $controlObj=$show.Stdout|ConvertFrom-Json
                        $sequence=[int](Get-PropertyValue $controlObj "sequence" -1)
                        $action=([string](Get-PropertyValue $controlObj "action" "IDLE")).ToUpperInvariant()
                        $last=Get-LastSequence
                        if($sequence -gt $last){
                            if($action -eq "IDLE"){
                                Save-BridgeState $sequence $action
                            } elseif($action -eq "RUN_BUILD"){
                                [void](Build-Katarina $true)
                                Save-BridgeState $sequence $action
                            } elseif($action -eq "APPLY_PATCH_AND_BUILD"){
                                try {
                                    Apply-ControlPatch $controlObj
                                    [void](Build-Katarina $true)
                                    Save-BridgeState $sequence $action
                                } catch {
                                    $message=Sanitize-Text $_.Exception.Message
                                    $failure=[ordered]@{
                                        schema_version=1
                                        proof_type="KATARINA_VPS_BRIDGE_ERROR"
                                        run_id=[DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
                                        generated_utc=[DateTime]::UtcNow.ToString("o")
                                        control_sequence=$sequence
                                        action=$action
                                        error=$message
                                        live_risk_ready=$false
                                        live_execution_enabled=$false
                                        result="FAIL_BRIDGE_PATCH"
                                    }
                                    Write-JsonFile $failure (Join-Path $ReportsRoot "latest.json")
                                    $message|Out-File -LiteralPath (Join-Path $ReportsRoot "latest.log") -Encoding utf8
                                    ""|Out-File -LiteralPath (Join-Path $ReportsRoot "latest.diff") -Encoding utf8
                                    [void](Publish-Report)
                                    Save-BridgeState $sequence $action
                                }
                            } elseif($action -eq "STOP"){
                                Save-BridgeState $sequence $action
                                break
                            }
                        }
                    } catch {}
                }
            }
            $config=Get-LocalConfig
            $poll=[int](Get-PropertyValue $config "poll_seconds" 120)
            if($poll -lt 30){$poll=30}
            Start-Sleep -Seconds $poll
        }
    } finally {
        Remove-Item -LiteralPath $BridgePidPath -Force -ErrorAction SilentlyContinue
    }
}

function Start-BridgeBackground {
    if(Test-Path -LiteralPath $BridgePidPath){
        try {
            $oldPid=[int](Get-Content -LiteralPath $BridgePidPath|Select-Object -First 1)
            if(Get-Process -Id $oldPid -ErrorAction SilentlyContinue){
                Write-Host "KATARINA VPS bridge already running (PID $oldPid)"
                return
            }
        } catch {}
    }
    $args=@("-NoProfile","-ExecutionPolicy","Bypass","-File",$MyInvocation.MyCommand.Path,"-Mode","Bridge","-RepoRoot",$RepoRoot)
    Start-Process -FilePath "powershell.exe" -ArgumentList (($args|ForEach-Object{Quote-Argument $_}) -join " ") -WindowStyle Minimized|Out-Null
    Start-Sleep -Seconds 1
    Write-Host "KATARINA VPS bridge started."
}

function Setup-Katarina {
    Ensure-Directories
    Enable-Tls12
    if(-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))){
        Write-Host "ERROR: use a Git clone, not a ZIP copy." -ForegroundColor Red
        return 10
    }
    $git=Resolve-Git
    if(-not $git){
        Write-Host "ERROR: git.exe not found. Install Git for Windows first." -ForegroundColor Red
        return 11
    }
    $python=Resolve-Python
    if(-not $python){
        Write-Host "ERROR: Python 3 not found. Python 3.12 is recommended." -ForegroundColor Red
        return 12
    }
    Ensure-LocalConfig
    if((Invoke-GitCaptured @("remote","get-url","origin") 60).ExitCode -ne 0){
        Write-Host "ERROR: origin remote missing." -ForegroundColor Red
        return 13
    }
    $access=Invoke-GitCaptured @("ls-remote","origin",("refs/heads/"+$ControlBranch)) 120
    if($access.ExitCode -ne 0){
        Write-Host "ERROR: GitHub authentication/access failed." -ForegroundColor Red
        Write-Host $access.Combined
        return 14
    }
    $current=(Invoke-GitCaptured @("rev-parse","--abbrev-ref","HEAD") 60).Stdout.Trim()
    if($current -ne "vps-local"){
        $dirty=(Invoke-GitCaptured @("status","--porcelain") 60).Stdout.Trim()
        if(-not $dirty){
            $checkout=Invoke-GitCaptured @("checkout","-B","vps-local") 120
            if($checkout.ExitCode -ne 0){Write-Warning "Could not switch to vps-local; continuing on $current"}
        }
    }
    Write-Host "Repo: $RepoRoot"
    Write-Host "Git: $git"
    Write-Host "Python: $($python.File)"
    Write-Host "Runtime: $RuntimeRoot"
    Write-Host "GitHub writes: reports only; source stays local."
    $rc=Build-Katarina $true
    Start-BridgeBackground
    return $rc
}

function Stop-Bridge {
    Ensure-Directories
    "stop"|Out-File -LiteralPath $StopPath -Encoding ascii
    if(Test-Path -LiteralPath $BridgePidPath){
        try {
            $targetPid=[int](Get-Content -LiteralPath $BridgePidPath|Select-Object -First 1)
            Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Remove-Item -LiteralPath $BridgePidPath -Force -ErrorAction SilentlyContinue
    Write-Host "KATARINA VPS bridge stopped."
}

function Show-Status {
    Ensure-Directories
    $report=Read-JsonFile (Join-Path $ReportsRoot "latest.json")
    $state=Read-JsonFile $StatePath
    Write-Host "Repo: $RepoRoot"
    Write-Host "Runtime: $RuntimeRoot"
    if($report){
        Write-Host ("Latest result: "+[string](Get-PropertyValue $report "result" "UNKNOWN"))
        Write-Host ("Latest run: "+[string](Get-PropertyValue $report "run_id" "UNKNOWN"))
    } else { Write-Host "Latest result: NONE" }
    if($state){Write-Host ("Control sequence: "+[string](Get-PropertyValue $state "last_sequence" "-1"))}
    if(Test-Path -LiteralPath $BridgePidPath){
        Write-Host ("Bridge PID: "+(Get-Content -LiteralPath $BridgePidPath|Select-Object -First 1))
    } else { Write-Host "Bridge: not running" }
}

Ensure-Directories
switch($Mode){
    "Setup"{exit (Setup-Katarina)}
    "Build"{exit (Build-Katarina ([bool]$Publish))}
    "Bridge"{Run-Bridge;exit 0}
    "Publish"{if(Publish-Report){exit 0}else{exit 2}}
    "Stop"{Stop-Bridge;exit 0}
    "Status"{Show-Status;exit 0}
}
