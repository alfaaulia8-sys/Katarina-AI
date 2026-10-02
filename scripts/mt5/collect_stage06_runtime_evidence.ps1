param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalCommonDataPath
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourceDir = Join-Path $TerminalCommonDataPath "Files\Katarina\Stage06"
$buildDir = Join-Path $repoRoot "build\mt5"
$bundleDir = Join-Path $buildDir "runtime-evidence"

if (!(Test-Path $sourceDir)) {
    throw "Stage 06 runtime evidence directory not found: $sourceDir"
}

New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

$required = @(
    "Katarina_Stage06_self_test_result.txt",
    "Katarina_Stage06_account_probe_STANDARD_LIKE.txt",
    "Katarina_Stage06_account_probe_CENT_LIKE.txt"
)

function Read-KeyValueEvidence {
    param([string]$Path)

    $result = [ordered]@{}
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0,$idx).Trim()
        $value = $line.Substring($idx+1).Trim()
        $result[$key] = $value
    }
    return $result
}

$records = @()
foreach ($name in $required) {
    $source = Join-Path $sourceDir $name
    if (!(Test-Path $source)) {
        throw "Required runtime evidence missing: $source"
    }

    $target = Join-Path $bundleDir $name
    Copy-Item -Path $source -Destination $target -Force

    $parsed = Read-KeyValueEvidence -Path $target
    if (-not $parsed.Contains("result")) {
        throw "Evidence has no result field: $name"
    }
    if ($parsed["result"] -ne "PASS") {
        throw "Runtime evidence did not pass: $name -> $($parsed["result"])"
    }

    $records += [pscustomobject]@{
        file = $name
        sha256 = (Get-FileHash -Path $target -Algorithm SHA256).Hash
        values = $parsed
    }
}

$standard = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_STANDARD_LIKE.txt" }
$cent = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_CENT_LIKE.txt" }

if ($standard.values["account_class"] -ne "STANDARD_LIKE") {
    throw "Standard account evidence is not typed STANDARD_LIKE."
}
if ($cent.values["account_class"] -ne "CENT_LIKE") {
    throw "Cent account evidence is not typed CENT_LIKE."
}

$compileEvidence = Join-Path $buildDir "stage06_compile_evidence.json"
if (!(Test-Path $compileEvidence)) {
    throw "Compile evidence missing: $compileEvidence"
}

$compile = Get-Content -Path $compileEvidence -Raw | ConvertFrom-Json
if ($compile.result -ne "PASS_COMPILE_PROOF") {
    throw "Compile evidence is not PASS_COMPILE_PROOF."
}

$manifest = [ordered]@{
    schema_version = "1.0"
    stage = "06"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    compile_evidence_sha256 = (Get-FileHash -Path $compileEvidence -Algorithm SHA256).Hash
    runtime_records = $records
    result = "PASS_RUNTIME_EVIDENCE"
}

$manifestPath = Join-Path $buildDir "stage06_runtime_evidence.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "PASS: Stage 06 runtime evidence collected."
Write-Host "Manifest: $manifestPath"
Write-Host "Bundle:   $bundleDir"
Write-Host ""
Write-Host "Final Stage 06 audit may now consume compile + runtime evidence."
