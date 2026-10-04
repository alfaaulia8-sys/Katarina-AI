param(
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = "C:\KatarinaDev"
$Workspace = Join-Path $WorkspaceRoot "workspace"
$Metadata = Join-Path $WorkspaceRoot "metadata"
$Evidence = Join-Path $WorkspaceRoot "evidence"
$Artifacts = Join-Path $WorkspaceRoot "artifacts"
$Snapshots = Join-Path $WorkspaceRoot "snapshots"
$Logs = Join-Path $WorkspaceRoot "logs"
$Runtime = Join-Path $WorkspaceRoot "runtime"

function Write-Json([string]$Path,$Value) {
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-Exe([string[]]$Candidates) {
    foreach($candidate in $Candidates) {
        if(!$candidate) { continue }
        if(Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
        $cmd=Get-Command $candidate -ErrorAction SilentlyContinue
        if($cmd) { return $cmd.Source }
    }
    return $null
}

function Build-Manifest {
    if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
    $records=@()
    foreach($file in @(Get-ChildItem -LiteralPath $Workspace -File -Recurse -ErrorAction Stop)) {
        $relative=$file.FullName.Substring($Workspace.Length).TrimStart("\")
        $records += [ordered]@{
            path=($relative -replace "\\","/")
            size=[int64]$file.Length
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return @($records | Sort-Object path)
}

$request=Get-Content -LiteralPath $RequestFile -Raw | ConvertFrom-Json
$mode=([string]$request.args.mode).ToUpperInvariant()
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

switch($mode) {
    "WORKSPACE_INIT" {
        foreach($dir in @($WorkspaceRoot,$Metadata,$Evidence,$Artifacts,$Snapshots,$Logs,$Runtime)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        if(Test-Path -LiteralPath $Workspace) {
            $backup=Join-Path $Snapshots ("pre_init_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
            Move-Item -LiteralPath $Workspace -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
        foreach($item in Get-ChildItem -LiteralPath $RepoRoot -Force) {
            if(@(".git","ops") -contains $item.Name) { continue }
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Workspace $item.Name) -Recurse -Force
        }
        Write-Json (Join-Path $Metadata "workspace.json") ([ordered]@{
            schema_version=1
            workspace_version="1.0"
            source_ref=[string]$request.ref
            initialized_utc=[DateTime]::UtcNow.ToString("o")
            computer_name=$env:COMPUTERNAME
            development_mode="VPS_FIRST"
            github_role="COMMAND_BUS_AND_CANONICAL_RELEASE"
        })
    }

    "WORKSPACE_STATUS" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
    }

    "WORKSPACE_APPLY" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        if($null -eq $request.args.PSObject.Properties["changeset"]) { throw "changeset is required." }
        $json=$request.args.changeset | ConvertTo-Json -Depth 16
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) { throw "Changeset exceeds 256 KiB command-bus limit." }
        $file=Join-Path $OutputDir "workspace_changeset.json"
        $json | Set-Content -LiteralPath $file -Encoding UTF8
        $engine=Join-Path $RepoRoot "scripts\vps\Apply-KatarinaWorkspaceChangeset.ps1"
        if(!(Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Workspace changeset engine missing." }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine -ChangesetPath $file -WorkspaceRoot $Workspace -EvidenceRoot $Evidence
        if($LASTEXITCODE -ne 0) { throw "Workspace changeset application failed." }
    }

    "WORKSPACE_BOOTSTRAP_PYTHON" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $bootstrap=Join-Path $RepoRoot "scripts\vps\Bootstrap-KatarinaPortablePython.ps1"
        if(!(Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw "Portable Python bootstrap script missing." }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap -WorkspaceRoot $WorkspaceRoot -OutputDir $OutputDir
        if($LASTEXITCODE -ne 0) { throw "Portable Python bootstrap failed." }
    }

    "WORKSPACE_RUNTIME_BOOTSTRAP" {
        foreach($dir in @($WorkspaceRoot,$Runtime,$Metadata,$Logs)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $pythonDir=Join-Path $Runtime "python"
        $packagesDir=Join-Path $Runtime "packages"
        $downloadDir=Join-Path $Runtime "downloads"
        New-Item -ItemType Directory -Force -Path $downloadDir,$packagesDir | Out-Null

        $pythonUrl="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
        $pythonMd5="fe8ef205f2e9c3ba44d0cf9954e1abd3"
        $pythonZip=Join-Path $downloadDir "python-3.12.10-embed-amd64.zip"
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZip -UseBasicParsing
        $actualMd5=(Get-FileHash -LiteralPath $pythonZip -Algorithm MD5).Hash.ToLowerInvariant()
        if($actualMd5 -ne $pythonMd5) { throw "Python embeddable checksum mismatch." }

        if(Test-Path -LiteralPath $pythonDir) { Remove-Item -LiteralPath $pythonDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($pythonZip,$pythonDir)

        $pth=Join-Path $pythonDir "python312._pth"
        if(!(Test-Path -LiteralPath $pth -PathType Leaf)) { throw "Python embedded _pth file missing." }
        @(
            "python312.zip",
            ".",
            $packagesDir,
            $Workspace,
            (Join-Path $Workspace "src"),
            "import site"
        ) | Set-Content -LiteralPath $pth -Encoding ASCII

        $pypi=Invoke-RestMethod -Method Get -Uri "https://pypi.org/pypi/pyzmq/25.1.1/json"
        $wheelName="pyzmq-25.1.1-cp312-cp312-win_amd64.whl"
        $expectedWheelSha256="eadbefd5e92ef8a345f0525b5cfd01cf4e4cc651a2cffb8f23c0dd184975d787"
        $wheelRecord=@($pypi.urls | Where-Object { $_.filename -eq $wheelName }) | Select-Object -First 1
        if($null -eq $wheelRecord) { throw "Pinned pyzmq wheel is missing from PyPI metadata." }
        if(([string]$wheelRecord.digests.sha256).ToLowerInvariant() -ne $expectedWheelSha256) {
            throw "Pinned pyzmq metadata SHA-256 mismatch."
        }
        $wheelUri=[Uri]([string]$wheelRecord.url)
        if($wheelUri.Scheme -ne "https" -or $wheelUri.Host -ne "files.pythonhosted.org") {
            throw "Pinned pyzmq download host is not allowlisted."
        }

        $wheel=Join-Path $downloadDir $wheelName
        Invoke-WebRequest -Uri $wheelUri.AbsoluteUri -OutFile $wheel -UseBasicParsing
        $actualWheelSha256=(Get-FileHash -LiteralPath $wheel -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actualWheelSha256 -ne $expectedWheelSha256) { throw "Downloaded pyzmq wheel SHA-256 mismatch." }

        if(Test-Path -LiteralPath $packagesDir) { Remove-Item -LiteralPath $packagesDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $packagesDir | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($wheel,$packagesDir)

        $pythonExe=Join-Path $pythonDir "python.exe"
        if(!(Test-Path -LiteralPath $pythonExe -PathType Leaf)) { throw "Portable Python executable missing." }

        $probeOut=Join-Path $OutputDir "python_runtime_probe.txt"
        $psi=New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName=$pythonExe
        $psi.Arguments='-c "import sys,zmq; print(sys.version); print(zmq.__version__); print(sys.executable)"'
        $psi.WorkingDirectory=$Workspace
        $psi.UseShellExecute=$false
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $proc=New-Object System.Diagnostics.Process
        $proc.StartInfo=$psi
        [void]$proc.Start()
        $probeStdout=$proc.StandardOutput.ReadToEnd()
        $probeStderr=$proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        ($probeStdout+[Environment]::NewLine+$probeStderr) | Set-Content -LiteralPath $probeOut -Encoding UTF8
        if($proc.ExitCode -ne 0) { throw "Portable Python/pyzmq probe failed." }

        Write-Json (Join-Path $Metadata "runtime.json") ([ordered]@{
            schema_version=1
            python_version="3.12.10"
            python_source=$pythonUrl
            python_md5=$actualMd5
            pyzmq_version="25.1.1"
            pyzmq_sha256=$actualWheelSha256
            installed_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
    }

    "WORKSPACE_MT5_COMPILE" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }

        $terminalDataPath=[string]$request.args.terminal_data_path
        $metaEditorPath=[string]$request.args.metaeditor_path
        if([string]::IsNullOrWhiteSpace($terminalDataPath) -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
            throw "terminal_data_path is required for WORKSPACE_MT5_COMPILE."
        }
        if([string]::IsNullOrWhiteSpace($metaEditorPath) -or !(Test-Path -LiteralPath $metaEditorPath -PathType Leaf)) {
            throw "metaeditor_path is required for WORKSPACE_MT5_COMPILE."
        }

        $includeSource=Join-Path $Workspace "mt5\Include\Katarina"
        $includeDest=Join-Path $terminalDataPath "MQL5\Include\Katarina"
        $expertsSource=Join-Path $Workspace "mt5\Experts"
        $testsSource=Join-Path $Workspace "mt5\Tests"
        $expertsDest=Join-Path $terminalDataPath "MQL5\Experts"
        $scriptsDest=Join-Path $terminalDataPath "MQL5\Scripts"
        $mqlRoot=Join-Path $terminalDataPath "MQL5"

        if(!(Test-Path -LiteralPath $includeSource -PathType Container)) { throw "Workspace Katarina include tree missing." }
        New-Item -ItemType Directory -Force -Path $includeDest,$expertsDest,$scriptsDest | Out-Null
        Copy-Item -Path (Join-Path $includeSource "*") -Destination $includeDest -Recurse -Force

        $targets=@()
        $stage07Ea=Join-Path $expertsSource "KatarinaBridgeStage07EA.mq5"
        if(!(Test-Path -LiteralPath $stage07Ea -PathType Leaf)) { throw "Stage-07 bridge EA source missing." }
        $eaDest=Join-Path $expertsDest "KatarinaBridgeStage07EA.mq5"
        Copy-Item -LiteralPath $stage07Ea -Destination $eaDest -Force
        $targets += [pscustomobject]@{ name="KatarinaBridgeStage07EA"; source=$eaDest; kind="EXPERT" }

        foreach($test in @(Get-ChildItem -LiteralPath $testsSource -Filter "KatarinaStage07*.mq5" -File | Sort-Object Name)) {
            $dest=Join-Path $scriptsDest $test.Name
            Copy-Item -LiteralPath $test.FullName -Destination $dest -Force
            $targets += [pscustomobject]@{ name=$test.BaseName; source=$dest; kind="SCRIPT" }
        }

        if($targets.Count -lt 2) { throw "Stage-07 compile target discovery is incomplete." }

        $records=@()
        $failed=$false
        foreach($target in $targets) {
            $ex5=[IO.Path]::ChangeExtension([string]$target.source,".ex5")
            if(Test-Path -LiteralPath $ex5) { Remove-Item -LiteralPath $ex5 -Force }
            $log=Join-Path $OutputDir ([string]$target.name + ".compile.log")
            if(Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

            $compileArgs=@(
                "/compile:`"$([string]$target.source)`"",
                "/inc:`"$mqlRoot`"",
                "/log:`"$log`""
            )
            $proc=Start-Process -FilePath $metaEditorPath -ArgumentList $compileArgs -Wait -PassThru
            $logText=""
            if(Test-Path -LiteralPath $log) { $logText=Get-Content -LiteralPath $log -Raw }
            $pass=(Test-Path -LiteralPath $log -PathType Leaf) -and
                  (Test-Path -LiteralPath $ex5 -PathType Leaf) -and
                  ($logText -match "0 errors, 0 warnings")
            if(!$pass) { $failed=$true }

            $records += [ordered]@{
                target=[string]$target.name
                kind=[string]$target.kind
                process_exit_code=[int]$proc.ExitCode
                compile_result=$(if($pass){"PASS_0_ERRORS_0_WARNINGS"}else{"FAIL"})
                ex5_exists=(Test-Path -LiteralPath $ex5 -PathType Leaf)
                ex5_sha256=$(if(Test-Path -LiteralPath $ex5 -PathType Leaf){(Get-FileHash -LiteralPath $ex5 -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null})
                log_file=[IO.Path]::GetFileName($log)
            }
        }

        $compileEvidence=[ordered]@{
            schema_version=1
            stage="07"
            proof_type="VPS_WORKSPACE_MT5_COMPILE"
            workspace_root=$Workspace
            terminal_data_path=$terminalDataPath
            metaeditor_path=$metaEditorPath
            target_count=$records.Count
            targets=$records
            generated_utc=[DateTime]::UtcNow.ToString("o")
            result=$(if($failed){"FAIL"}else{"PASS_0_ERRORS_0_WARNINGS"})
        }
        Write-Json (Join-Path $OutputDir "workspace_mt5_compile.json") $compileEvidence
        if($failed) { throw "One or more Stage-07 workspace MT5 targets failed strict compilation." }
    }

    "WORKSPACE_TEST" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $python=Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python")
        if(!$python) { throw "Workspace Python runtime is not available yet." }

        $runner=Join-Path $OutputDir "workspace_test_runner.py"
        $workspacePy=$Workspace.Replace("\","\\")
        @"
import pathlib
import sys
import unittest

root = pathlib.Path(r"$workspacePy")
sys.path.insert(0, str(root))
sys.path.insert(0, str(root / "src"))

names = [
    "tests.unit.transport.test_stage07_communication",
    "tests.unit.transport.test_stage07_stage06_contract",
]
suite = unittest.defaultTestLoader.loadTestsFromNames(names)
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
"@ | Set-Content -LiteralPath $runner -Encoding ASCII

        $stdout=Join-Path $OutputDir "workspace_test_stdout.txt"
        $stderr=Join-Path $OutputDir "workspace_test_stderr.txt"
        $p=Start-Process -FilePath $python -ArgumentList @($runner) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if($p.ExitCode -ne 0) { throw "Workspace tests failed." }
    }

    default { throw "Unsupported workspace mode: $mode" }
}

$manifest=Build-Manifest
Write-Json (Join-Path $Metadata "manifest.json") ([ordered]@{
    schema_version=1
    generated_utc=[DateTime]::UtcNow.ToString("o")
    file_count=$manifest.Count
    files=$manifest
})
Write-Json (Join-Path $OutputDir "workspace_status.json") ([ordered]@{
    schema_version=1
    mode=$mode
    root=$WorkspaceRoot
    workspace=$Workspace
    file_count=$manifest.Count
    python_runtime=(Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python"))
    result="PASS"
})
