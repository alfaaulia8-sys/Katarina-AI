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

    "WORKSPACE_TEST" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $python=Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python")
        if(!$python) { throw "Workspace Python runtime is not available yet." }
        Push-Location $Workspace
        try {
            & $python -m unittest tests.unit.transport.test_stage07_communication tests.unit.transport.test_stage07_stage06_contract -v
            if($LASTEXITCODE -ne 0) { throw "Workspace tests failed." }
        } finally { Pop-Location }
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
