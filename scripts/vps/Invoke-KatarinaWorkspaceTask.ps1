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
        $normalized=($relative -replace "\\","/")
        if($normalized -match '(^|/)(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache)(/|$)') { continue }
        if($normalized -match '\.(pyc|pyo)

function Resolve-SafeWorkspaceFile {
    param([string]$RelativePath)

    if([string]::IsNullOrWhiteSpace($RelativePath)) { throw "Workspace path cannot be empty." }
    $p=$RelativePath.Replace("\","/").TrimStart("/")
    if($p.StartsWith("/") -or $p.Contains("..") -or $p.Contains(":") -or $p.Contains("//")) {
        throw "Unsafe workspace path: $RelativePath"
    }

    $allowed=@("src/","mt5/","tests/","config/","scripts/","docs/","protocol/",".github/")
    $rootFiles=@("README.md","pyproject.toml","requirements.txt","requirements-stage07.txt",".gitignore")
    $ok=$false
    foreach($prefix in $allowed) {
        if($p.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { $ok=$true; break }
    }
    if($rootFiles -contains $p) { $ok=$true }
    if(!$ok) { throw "Workspace path is outside allowlist: $RelativePath" }

    return [pscustomobject]@{
        relative=$p
        full=(Join-Path $Workspace ($p.Replace("/","\")))
    }
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
        $baseline=Build-Manifest
        Write-Json (Join-Path $Metadata "baseline_manifest.json") $baseline
        Write-Json (Join-Path $Metadata "workspace.json") ([ordered]@{
            schema_version=1
            workspace_version="1.1"
            source_ref=[string]$request.ref
            source_sha=$(if($null -ne $request.args.PSObject.Properties["source_sha"]) { [string]$request.args.source_sha } else { "" })
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

    "WORKSPACE_READ" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $paths=@($request.args.paths)
        if($paths.Count -lt 1 -or $paths.Count -gt 20) { throw "WORKSPACE_READ requires 1-20 paths." }

        $parts=@()
        $totalBytes=0
        foreach($requested in $paths) {
            $resolved=Resolve-SafeWorkspaceFile ([string]$requested)
            if(!(Test-Path -LiteralPath $resolved.full -PathType Leaf)) { throw "Workspace file missing: $($resolved.relative)" }
            $info=Get-Item -LiteralPath $resolved.full
            if($info.Length -gt 262144) { throw "Workspace file exceeds 256 KiB: $($resolved.relative)" }
            $text=Get-Content -LiteralPath $resolved.full -Raw
            $totalBytes += [Text.Encoding]::UTF8.GetByteCount($text)
            if($totalBytes -gt 524288) { throw "WORKSPACE_READ exceeds 512 KiB total." }
            $parts += "===== $($resolved.relative) ====="
            $parts += $text
        }
        ($parts -join [Environment]::NewLine) | Set-Content -LiteralPath (Join-Path $OutputDir "workspace_read.txt") -Encoding UTF8
    }

    "WORKSPACE_SNAPSHOT" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $label=[string]$request.args.label
        if([string]::IsNullOrWhiteSpace($label)) { $label="manual" }
        if($label -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}
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

$added=@()
$modified=@()
$deleted=@()
$baselinePath=Join-Path $Metadata "baseline_manifest.json"
if(Test-Path -LiteralPath $baselinePath -PathType Leaf) {
    $baseline=@(Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json)
    $baseMap=@{}
    foreach($item in $baseline) { $baseMap[[string]$item.path]=[string]$item.sha256 }
    $curMap=@{}
    foreach($item in $manifest) { $curMap[[string]$item.path]=[string]$item.sha256 }

    foreach($p in $curMap.Keys) {
        if(!$baseMap.ContainsKey($p)) { $added += $p }
        elseif($baseMap[$p] -ne $curMap[$p]) { $modified += $p }
    }
    foreach($p in $baseMap.Keys) {
        if(!$curMap.ContainsKey($p)) { $deleted += $p }
    }
}

Write-Json (Join-Path $OutputDir "workspace_status.json") ([ordered]@{
    schema_version=1
    mode=$mode
    root=$WorkspaceRoot
    workspace=$Workspace
    file_count=$manifest.Count
    python_runtime=(Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python"))
    dirty=((@($added).Count+@($modified).Count+@($deleted).Count) -gt 0)
    added_count=@($added).Count
    modified_count=@($modified).Count
    deleted_count=@($deleted).Count
    added=@($added | Sort-Object | Select-Object -First 200)
    modified=@($modified | Sort-Object | Select-Object -First 200)
    deleted=@($deleted | Sort-Object | Select-Object -First 200)
    result="PASS"
})
) { continue }
        if($normalized.StartsWith("build/")) { continue }

        $records += [ordered]@{
            path=$normalized
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
) { throw "Unsafe snapshot label." }

        $zip=Join-Path $Snapshots ([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")+"_"+$label+".zip")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($Workspace,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
        Write-Json (Join-Path $OutputDir "workspace_snapshot.json") ([ordered]@{
            schema_version=1
            label=$label
            path=$zip
            size_bytes=[int64](Get-Item -LiteralPath $zip).Length
            sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            created_utc=[DateTime]::UtcNow.ToString("o")
        })
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
) { continue }
        if($normalized.StartsWith("build/")) { continue }

        $records += [ordered]@{
            path=$normalized
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
