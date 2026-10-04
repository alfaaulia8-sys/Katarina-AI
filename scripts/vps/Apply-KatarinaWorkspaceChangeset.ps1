param(
    [Parameter(Mandatory=$true)][string]$ChangesetPath,
    [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\KatarinaDev\workspace",
    [Parameter(Mandatory=$false)][string]$EvidenceRoot = "C:\KatarinaDev\evidence"
)

$ErrorActionPreference = "Stop"

function Get-Sha256([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SafeRelativePath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "Empty changeset path." }
    $p = $RelativePath.Replace("\","/")
    if ($p.StartsWith("/") -or $p.Contains("..") -or $p.Contains("//") -or $p.Contains(":")) {
        throw "Unsafe changeset path: $RelativePath"
    }

    $allowedPrefixes = @("src/","mt5/","tests/","config/","scripts/","docs/","protocol/",".github/")
    $allowedRootFiles = @("README.md","pyproject.toml","requirements.txt",".gitignore")
    $ok = $false
    foreach ($prefix in $allowedPrefixes) {
        if ($p.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
    }
    if ($allowedRootFiles -contains $p) { $ok = $true }
    if (!$ok) { throw "Changeset path is outside the Katarina workspace allowlist: $RelativePath" }
    return $p
}

if (!(Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    throw "Workspace not initialized: $WorkspaceRoot"
}
if (!(Test-Path -LiteralPath $ChangesetPath -PathType Leaf)) {
    throw "Changeset not found: $ChangesetPath"
}

$changeset = Get-Content -LiteralPath $ChangesetPath -Raw | ConvertFrom-Json
if ([int]$changeset.schema_version -ne 1) { throw "Unsupported changeset schema." }
if ([string]::IsNullOrWhiteSpace([string]$changeset.changeset_id)) { throw "changeset_id is required." }
if ($null -eq $changeset.operations -or @($changeset.operations).Count -eq 0) { throw "No changeset operations." }

$backupRoot = Join-Path $EvidenceRoot ("changesets\" + [string]$changeset.changeset_id)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$receipt = @()
foreach ($op in @($changeset.operations)) {
    $relative = Assert-SafeRelativePath ([string]$op.path)
    $target = Join-Path $WorkspaceRoot ($relative.Replace("/","\"))
    $action = ([string]$op.action).ToUpperInvariant()
    $before = Get-Sha256 $target

    if ($null -ne $op.PSObject.Properties["base_sha256"] -and $op.base_sha256) {
        if ($before -ne ([string]$op.base_sha256).ToLowerInvariant()) {
            throw "Base hash mismatch for $relative"
        }
    }

    if ($before) {
        $backup = Join-Path $backupRoot ($relative.Replace("/","\"))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backup -Force
    }

    switch ($action) {
        "WRITE_TEXT" {
            if ($null -eq $op.PSObject.Properties["content_base64"]) { throw "content_base64 required for $relative" }
            $bytes = [Convert]::FromBase64String([string]$op.content_base64)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            [IO.File]::WriteAllBytes($target,$bytes)
        }
        "DELETE" {
            if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }
        default { throw "Unsupported changeset action: $action" }
    }

    $receipt += [ordered]@{
        path = $relative
        action = $action
        before_sha256 = $before
        after_sha256 = (Get-Sha256 $target)
    }
}

[ordered]@{
    schema_version = 1
    changeset_id = [string]$changeset.changeset_id
    applied_utc = [DateTime]::UtcNow.ToString("o")
    operation_count = $receipt.Count
    operations = $receipt
    result = "PASS"
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $backupRoot "receipt.json") -Encoding UTF8
