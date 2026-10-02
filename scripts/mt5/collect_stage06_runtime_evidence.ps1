param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalCommonDataPath
)

$ErrorActionPreference = "Stop"
$designVersion = "0.5.0"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourceDir = Join-Path $TerminalCommonDataPath "Files"
$buildDir = Join-Path $repoRoot "build\mt5"
$bundleDir = Join-Path $buildDir "runtime-evidence"

if (!(Test-Path $sourceDir)) {
    throw "MT5 Common Files directory not found: $sourceDir"
}

New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

$compileEvidence = Join-Path $buildDir "stage06_compile_evidence.json"
if (!(Test-Path $compileEvidence)) {
    throw "Compile evidence missing: $compileEvidence"
}

$compile = Get-Content -Path $compileEvidence -Raw | ConvertFrom-Json
if ($compile.result -ne "PASS_COMPILE_PROOF") {
    throw "Compile evidence is not PASS_COMPILE_PROOF."
}
if ($compile.bridge_design_version -ne $designVersion) {
    throw "Compile evidence design version mismatch. Expected $designVersion, got $($compile.bridge_design_version)."
}

$compileUtc = [DateTime]::Parse(
    [string]$compile.generated_utc,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind
).ToUniversalTime()

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

    $sourceInfo = Get-Item $source

    # Allow a small host clock tolerance, but reject evidence clearly older than
    # the source/compiler proof that is being finalized.
    if ($sourceInfo.LastWriteTimeUtc -lt $compileUtc.AddMinutes(-5)) {
        throw "Stale runtime evidence: $name predates the current compile proof."
    }

    $target = Join-Path $bundleDir $name
    Copy-Item -Path $source -Destination $target -Force

    $parsed = Read-KeyValueEvidence -Path $target

    foreach ($key in @("stage","design_version","proof_type","terminal_build","result")) {
        if (-not $parsed.Contains($key)) {
            throw "Evidence $name is missing required field: $key"
        }
    }

    if ($parsed["stage"] -ne "06") {
        throw "Evidence belongs to another stage: $name"
    }
    if ($parsed["design_version"] -ne $designVersion) {
        throw "Runtime evidence design version mismatch in $name. Expected $designVersion."
    }
    if ($parsed["result"] -ne "PASS") {
        throw "Runtime evidence did not pass: $name -> $($parsed["result"])"
    }

    $terminalBuild = 0
    if (-not [int]::TryParse([string]$parsed["terminal_build"], [ref]$terminalBuild) -or $terminalBuild -le 0) {
        throw "Invalid terminal_build in runtime evidence: $name"
    }

    $generatedEpoch = 0L
    if ($parsed.Contains("generated_epoch_seconds")) {
        if (-not [long]::TryParse([string]$parsed["generated_epoch_seconds"], [ref]$generatedEpoch) -or $generatedEpoch -le 0) {
            throw "Invalid generated_epoch_seconds in runtime evidence: $name"
        }
    }

    $records += [pscustomobject]@{
        file = $name
        last_write_utc = $sourceInfo.LastWriteTimeUtc.ToString("o")
        sha256 = (Get-FileHash -Path $target -Algorithm SHA256).Hash
        values = $parsed
    }
}

$selfTest = $records | Where-Object { $_.file -eq "Katarina_Stage06_self_test_result.txt" }
$standard = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_STANDARD_LIKE.txt" }
$cent = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_CENT_LIKE.txt" }

if ($selfTest.values["proof_type"] -ne "MQL_SELF_TEST") {
    throw "Self-test evidence has unexpected proof_type."
}
if ($standard.values["proof_type"] -ne "ACCOUNT_PROBE" -or
    $standard.values["account_class"] -ne "STANDARD_LIKE") {
    throw "Standard account evidence is not a valid STANDARD_LIKE account probe."
}
if ($cent.values["proof_type"] -ne "ACCOUNT_PROBE" -or
    $cent.values["account_class"] -ne "CENT_LIKE") {
    throw "Cent account evidence is not a valid CENT_LIKE account probe."
}

$manifest = [ordered]@{
    schema_version = "1.1"
    stage = "06"
    bridge_design_version = $designVersion
    generated_utc = [DateTime]::UtcNow.ToString("o")
    compile_evidence_sha256 = (Get-FileHash -Path $compileEvidence -Algorithm SHA256).Hash
    compile_generated_utc = $compile.generated_utc
    runtime_records = $records
    result = "PASS_RUNTIME_EVIDENCE"
}

$manifestPath = Join-Path $buildDir "stage06_runtime_evidence.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "PASS: Stage 06 runtime evidence collected."
Write-Host "Design:   $designVersion"
Write-Host "Manifest: $manifestPath"
Write-Host "Bundle:   $bundleDir"
Write-Host ""
Write-Host "Final Stage 06 audit may now consume compile + runtime evidence."
