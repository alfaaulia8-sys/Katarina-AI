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
    $json = ConvertTo-Json -InputObject $Value -Depth 16
    $json | Set-Content -LiteralPath $Path -Encoding UTF8
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

        $version="3.11.9"
        $pythonRoot=Join-Path $Runtime "python"
        $downloadRoot=Join-Path $Runtime "downloads"
        New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null

        $python=Join-Path $pythonRoot "python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) {
            $zip=Join-Path $downloadRoot ("python-"+$version+"-embed-amd64.zip")
            $url="https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip"
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

            if(Test-Path -LiteralPath $pythonRoot) {
                Remove-Item -LiteralPath $pythonRoot -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $pythonRoot | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip,$pythonRoot)

            $pth=Join-Path $pythonRoot "python311._pth"
            if(!(Test-Path -LiteralPath $pth -PathType Leaf)) { throw "Embedded Python _pth file missing." }
            $lines=@(Get-Content -LiteralPath $pth)
            $out=@()
            $haveSite=$false
            $havePackages=$false
            foreach($line in $lines) {
                if($line -match '^#?import site        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
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
) {
                    $out += "import site"
                    $haveSite=$true
                    continue
                }
                if($line -eq "Lib\site-packages") { $havePackages=$true }
                $out += $line
            }
            if(!$havePackages) { $out += "Lib\site-packages" }
            if(!$haveSite) { $out += "import site" }
            $out | Set-Content -LiteralPath $pth -Encoding ASCII
            New-Item -ItemType Directory -Force -Path (Join-Path $pythonRoot "Lib\site-packages") | Out-Null
        }

        $versionLog=Join-Path $OutputDir "python_version.txt"
        & $python --version 2>&1 | Set-Content -LiteralPath $versionLog -Encoding UTF8
        if($LASTEXITCODE -ne 0) { throw "Portable Python failed to start." }

        $getPip=Join-Path $downloadRoot "get-pip.py"
        if(!(Test-Path -LiteralPath $getPip -PathType Leaf)) {
            Invoke-WebRequest -Uri "https://bootstrap.pypa.io/pip/3.11/get-pip.py" -OutFile $getPip -UseBasicParsing
        }

        $pipCheck=& $python -m pip --version 2>&1
        if($LASTEXITCODE -ne 0) {
            & $python $getPip --no-warn-script-location 2>&1 | Set-Content -LiteralPath (Join-Path $OutputDir "get_pip.log") -Encoding UTF8
            if($LASTEXITCODE -ne 0) { throw "get-pip failed for portable Python." }
        }

        $requirements=Join-Path $Workspace "requirements-stage07.txt"
        if(Test-Path -LiteralPath $requirements -PathType Leaf) {
            & $python -m pip install --disable-pip-version-check -r $requirements 2>&1 | Set-Content -LiteralPath (Join-Path $OutputDir "pip_install.log") -Encoding UTF8
            if($LASTEXITCODE -ne 0) { throw "Stage-07 Python dependency installation failed." }
        }

        $probe=Join-Path $OutputDir "python_probe.txt"
        & $python -c "import sys; print(sys.version); import zmq, tornado; print('pyzmq='+zmq.__version__); print('libzmq='+zmq.zmq_version()); print('tornado='+tornado.version)" 2>&1 | Set-Content -LiteralPath $probe -Encoding UTF8
        if($LASTEXITCODE -ne 0) { throw "Portable Python dependency probe failed." }
    }

    "WORKSPACE_SNAPSHOT" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $label=[string]$request.args.label
        if([string]::IsNullOrWhiteSpace($label)) { $label="manual" }
        if($label -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
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

    "WORKSPACE_READ" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $paths=@($request.args.paths)
        if($paths.Count -lt 1 -or $paths.Count -gt 20) { throw "WORKSPACE_READ requires 1-20 paths." }

        $parts=@()
        $total=0
        foreach($raw in $paths) {
            $relative=([string]$raw).Replace("\","/")
            if([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith("/") -or $relative.Contains("..") -or $relative.Contains(":")) {
                throw "Unsafe workspace read path."
            }
            $target=Join-Path $Workspace ($relative.Replace("/","\"))
            if(!(Test-Path -LiteralPath $target -PathType Leaf)) { throw "Workspace read file missing: $relative" }
            $info=Get-Item -LiteralPath $target
            if($info.Length -gt 262144) { throw "Workspace read file exceeds 256 KiB." }
            $text=Get-Content -LiteralPath $target -Raw
            $total += [Text.Encoding]::UTF8.GetByteCount($text)
            if($total -gt 524288) { throw "Workspace read exceeds 512 KiB total." }
            $parts += "===== $relative ====="
            $parts += $text
        }
        ($parts -join [Environment]::NewLine) | Set-Content -LiteralPath (Join-Path $OutputDir "workspace_read.txt") -Encoding UTF8
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
