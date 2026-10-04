param(
    [Parameter(Mandatory=$true)]
    [string]$RequestFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputDir,
    [Parameter(Mandatory=$true)]
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-JsonFile {
    param([string]$Path,$Value)
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ArgValue {
    param($ArgsObject,[string]$Name,$Default=$null)
    if ($null -eq $ArgsObject) { return $Default }
    $prop = $ArgsObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Get-WorkspaceLayout {
    $root="C:\KatarinaDev"
    return [ordered]@{
        root=$root
        source=(Join-Path $root "workspace\source")
        runtime=(Join-Path $root "runtime")
        tools=(Join-Path $root "tools")
        evidence=(Join-Path $root "evidence")
        artifacts=(Join-Path $root "artifacts")
        snapshots=(Join-Path $root "snapshots")
        logs=(Join-Path $root "logs")
        state=(Join-Path $root "state")
    }
}

function Assert-SafeRelativePath {
    param([string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "Workspace path cannot be empty." }
    $normalized=$RelativePath.Replace("\","/").TrimStart("/")
    if ($normalized.Contains("..") -or $normalized.Contains(":") -or $normalized.StartsWith("/") -or
        $normalized -match '(^|/)\.git(/|$)' -or
        $normalized -match '(^|/)ops/vps/(requests|results)(/|$)') {
        throw "Unsafe workspace path: $RelativePath"
    }

    $allowedPrefixes=@("src/","mt5/","tests/","scripts/","config/","docs/","protocol/",".github/","requirements")
    $allowedExact=@("README.md","pyproject.toml","pytest.ini",".gitignore")
    $allowed=$false
    foreach ($prefix in $allowedPrefixes) {
        if ($normalized.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { $allowed=$true; break }
    }
    if (-not $allowed) {
        foreach ($exact in $allowedExact) {
            if ([string]::Equals($normalized,$exact,[StringComparison]::OrdinalIgnoreCase)) { $allowed=$true; break }
        }
    }
    if (-not $allowed) { throw "Workspace path is outside allowlisted project roots: $RelativePath" }
    return $normalized
}

function Get-Manifest {
    param([string]$SourceRoot)
    $records=@()
    if (!(Test-Path -LiteralPath $SourceRoot -PathType Container)) { return $records }
    foreach ($file in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)) {
        $relative=$file.FullName.Substring($SourceRoot.Length).TrimStart("\")
        $records += [pscustomobject]@{
            path=($relative -replace "\\","/")
            size_bytes=[int64]$file.Length
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return $records
}

function Copy-Baseline {
    param([string]$From,[string]$To)
    if (Test-Path -LiteralPath $To) { Remove-Item -LiteralPath $To -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $From -Force)) {
        if ($item.Name -in @(".git","ops","build")) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $To -Recurse -Force
    }
}

function New-ChangesetBackup {
    param([string]$SourceRoot,[string]$BackupRoot,$Changes)
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $backupMeta=@()
    foreach ($change in $Changes) {
        $safe=Assert-SafeRelativePath ([string]$change.path)
        $source=Join-Path $SourceRoot ($safe -replace "/","\")
        $existed=Test-Path -LiteralPath $source -PathType Leaf
        if ($existed) {
            $dest=Join-Path $BackupRoot ($safe -replace "/","\")
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $source -Destination $dest -Force
        }
        $backupMeta += [pscustomobject]@{ path=$safe; existed_before=$existed }
    }
    Write-JsonFile (Join-Path $BackupRoot "backup.json") $backupMeta
}

if (!(Test-Path -LiteralPath $RequestFile -PathType Leaf)) { throw "Request file not found." }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$request=Get-Content -LiteralPath $RequestFile -Raw | ConvertFrom-Json
$mode=([string](Get-ArgValue $request.args "mode" "")).ToUpperInvariant()
$layout=Get-WorkspaceLayout

foreach ($key in @("root","runtime","tools","evidence","artifacts","snapshots","logs","state")) {
    New-Item -ItemType Directory -Force -Path ([string]$layout[$key]) | Out-Null
}

switch ($mode) {
    "WORKSPACE_INIT" {
        $force=[bool](Get-ArgValue $request.args "force_rebaseline" $false)
        $sourceSha=[string](Get-ArgValue $request.args "source_sha" "")
        $metadataPath=Join-Path $layout.state "workspace.json"

        if ((Test-Path -LiteralPath $layout.source -PathType Container) -and -not $force) {
            throw "Persistent workspace already exists."
        }

        if ((Test-Path -LiteralPath $layout.source -PathType Container) -and $force) {
            $stamp=[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
            $backup=Join-Path $layout.snapshots ("rebaseline_"+$stamp)
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            $before=Get-Manifest -SourceRoot $layout.source
            Write-JsonFile (Join-Path $backup "pre_rebaseline_manifest.json") $before
            if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
                Copy-Item -LiteralPath $metadataPath -Destination (Join-Path $backup "workspace.json") -Force
            }
        }

        Copy-Baseline -From $RepoRoot -To $layout.source
        $manifest=@(Get-Manifest -SourceRoot $layout.source)
        Write-JsonFile (Join-Path $layout.state "baseline_manifest.json") $manifest

        $totalBytes=0
        foreach ($item in $manifest) { $totalBytes += [int64]$item.size_bytes }
        $metadata=[ordered]@{
            schema_version=1
            mode="VPS_FIRST_DEVELOPMENT"
            workspace_root=$layout.root
            source_root=$layout.source
            source_ref=[string]$request.ref
            source_sha=$sourceSha
            initialized_utc=[DateTime]::UtcNow.ToString("o")
            file_count=@($manifest).Count
            total_bytes=[int64]$totalBytes
            github_role="COMMAND_BUS_CANONICAL_RELEASE"
            development_role="VPS_PRIMARY"
        }
        Write-JsonFile $metadataPath $metadata
        Write-JsonFile (Join-Path $OutputDir "workspace_init.json") $metadata
    }

    "WORKSPACE_STATUS" {
        $metadataPath=Join-Path $layout.state "workspace.json"
        $baselinePath=Join-Path $layout.state "baseline_manifest.json"
        if (!(Test-Path -LiteralPath $metadataPath -PathType Leaf) -or
            !(Test-Path -LiteralPath $baselinePath -PathType Leaf) -or
            !(Test-Path -LiteralPath $layout.source -PathType Container)) {
            throw "Persistent workspace is not initialized."
        }

        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $baseline=@(Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json)
        $current=@(Get-Manifest -SourceRoot $layout.source)
        $baseMap=@{}
        foreach ($item in $baseline) { $baseMap[[string]$item.path]=[string]$item.sha256 }
        $currentMap=@{}
        foreach ($item in $current) { $currentMap[[string]$item.path]=[string]$item.sha256 }

        $modified=@(); $added=@(); $deleted=@()
        foreach ($p in $currentMap.Keys) {
            if (-not $baseMap.ContainsKey($p)) { $added += $p }
            elseif ($baseMap[$p] -ne $currentMap[$p]) { $modified += $p }
        }
        foreach ($p in $baseMap.Keys) {
            if (-not $currentMap.ContainsKey($p)) { $deleted += $p }
        }

        $status=[ordered]@{
            schema_version=1
            workspace_root=$layout.root
            source_sha=[string]$metadata.source_sha
            initialized_utc=[string]$metadata.initialized_utc
            current_file_count=@($current).Count
            modified_count=@($modified).Count
            added_count=@($added).Count
            deleted_count=@($deleted).Count
            modified=@($modified | Sort-Object | Select-Object -First 200)
            added=@($added | Sort-Object | Select-Object -First 200)
            deleted=@($deleted | Sort-Object | Select-Object -First 200)
            clean=((@($modified).Count+@($added).Count+@($deleted).Count) -eq 0)
            checked_utc=[DateTime]::UtcNow.ToString("o")
        }
        Write-JsonFile (Join-Path $OutputDir "workspace_status.json") $status
    }

    "WORKSPACE_APPLY_CHANGESET" {
        if (!(Test-Path -LiteralPath $layout.source -PathType Container)) { throw "Persistent workspace is not initialized." }
        $changesetId=[string](Get-ArgValue $request.args "changeset_id" "")
        if ($changesetId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "changeset_id is missing or unsafe." }

        $changes=@(Get-ArgValue $request.args "changes" @())
        if ($changes.Count -lt 1 -or $changes.Count -gt 200) { throw "changes must contain between 1 and 200 operations." }

        $backupRoot=Join-Path $layout.snapshots ("changeset_"+$changesetId)
        if (Test-Path -LiteralPath $backupRoot) { throw "changeset backup already exists." }
        New-ChangesetBackup -SourceRoot $layout.source -BackupRoot $backupRoot -Changes $changes

        $applied=@()
        foreach ($change in $changes) {
            $safe=Assert-SafeRelativePath ([string]$change.path)
            $operation=([string]$change.operation).ToUpperInvariant()
            $target=Join-Path $layout.source ($safe -replace "/","\")

            if ($operation -eq "WRITE") {
                $encoded=[string]$change.content_base64
                if ([string]::IsNullOrWhiteSpace($encoded)) { throw "WRITE operation missing content_base64 for $safe" }
                $bytes=[Convert]::FromBase64String($encoded)
                if ($bytes.Length -gt 2097152) { throw "Single workspace write exceeds 2 MiB." }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                [IO.File]::WriteAllBytes($target,$bytes)
            }
            elseif ($operation -eq "DELETE") {
                if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            }
            else { throw "Unsupported workspace operation." }

            $applied += [pscustomobject]@{path=$safe;operation=$operation}
        }

        $record=[ordered]@{
            schema_version=1
            changeset_id=$changesetId
            request_id=[string]$request.request_id
            applied_utc=[DateTime]::UtcNow.ToString("o")
            operations=$applied
            backup_root=$backupRoot
        }
        $changesetDir=Join-Path $layout.state "changesets"
        New-Item -ItemType Directory -Force -Path $changesetDir | Out-Null
        Write-JsonFile (Join-Path $changesetDir ($changesetId+".json")) $record
        Write-JsonFile (Join-Path $OutputDir "workspace_changeset.json") $record
    }

    "WORKSPACE_READ" {
        if (!(Test-Path -LiteralPath $layout.source -PathType Container)) { throw "Persistent workspace is not initialized." }
        $paths=@(Get-ArgValue $request.args "paths" @())
        if ($paths.Count -lt 1 -or $paths.Count -gt 20) { throw "paths must contain between 1 and 20 files." }

        $parts=@(); $total=0
        foreach ($requestedPath in $paths) {
            $safe=Assert-SafeRelativePath ([string]$requestedPath)
            $target=Join-Path $layout.source ($safe -replace "/","\")
            if (!(Test-Path -LiteralPath $target -PathType Leaf)) { throw "Workspace file not found: $safe" }
            $info=Get-Item -LiteralPath $target
            if ($info.Length -gt 262144) { throw "Workspace read file exceeds 256 KiB: $safe" }
            $text=Get-Content -LiteralPath $target -Raw
            $total += [Text.Encoding]::UTF8.GetByteCount($text)
            if ($total -gt 524288) { throw "Workspace read exceeds 512 KiB total." }
            $parts += "===== $safe ====="
            $parts += $text
        }
        ($parts -join [Environment]::NewLine) | Set-Content -LiteralPath (Join-Path $OutputDir "workspace_read.txt") -Encoding UTF8
    }

    "WORKSPACE_SNAPSHOT" {
        if (!(Test-Path -LiteralPath $layout.source -PathType Container)) { throw "Persistent workspace is not initialized." }
        $label=[string](Get-ArgValue $request.args "label" "manual")
        if ($label -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Unsafe snapshot label." }

        $stamp=[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
        $zipPath=Join-Path $layout.snapshots ($stamp+"_"+$label+".zip")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($layout.source,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$false)

        $snapshot=[ordered]@{
            schema_version=1
            label=$label
            path=$zipPath
            size_bytes=[int64](Get-Item -LiteralPath $zipPath).Length
            sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            created_utc=[DateTime]::UtcNow.ToString("o")
        }
        Write-JsonFile (Join-Path $OutputDir "workspace_snapshot.json") $snapshot
    }

    default { throw "Unsupported workspace mode: $mode" }
}

$summary=[ordered]@{
    schema_version=1
    mode=$mode
    workspace_root=$layout.root
    completed_utc=[DateTime]::UtcNow.ToString("o")
    result="PASS"
}
Write-JsonFile (Join-Path $OutputDir "workspace_task.json") $summary
exit 0
