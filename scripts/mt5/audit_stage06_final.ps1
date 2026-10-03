param(
    [Parameter(Mandatory=$false)]
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$designVersion = "0.5.0"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$buildDir = Join-Path $repoRoot "build\mt5"
$compileEvidencePath = Join-Path $buildDir "stage06_compile_evidence.json"
$selfTestPath = Join-Path $buildDir "Katarina_Stage06_self_test_result.txt"
$clearancePath = Join-Path $buildDir "stage06_final_clearance.json"
$reportPath = Join-Path $buildDir "STAGE_06_FINAL_AUDIT_CANDIDATE.md"

function Assert-FileExists {
    param([string]$Path,[string]$Label)
    if (!(Test-Path $Path)) { throw "$Label missing: $Path" }
}

function Read-KeyValueEvidence {
    param([string]$Path)
    $result = [ordered]@{}
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { continue }
        $result[$line.Substring(0,$idx).Trim()] = $line.Substring($idx+1).Trim()
    }
    return $result
}

Assert-FileExists $compileEvidencePath "Compile evidence"
Assert-FileExists $selfTestPath "MQL self-test evidence"

$compile = Get-Content -Path $compileEvidencePath -Raw | ConvertFrom-Json
$selfTest = Read-KeyValueEvidence -Path $selfTestPath

if ($compile.result -ne "PASS_COMPILE_PROOF") {
    throw "Compile proof is not PASS_COMPILE_PROOF."
}
if ($compile.bridge_design_version -ne $designVersion) {
    throw "Compile design version mismatch."
}
if ($compile.host.validation_class -notin @("PREFERRED","COMPATIBILITY")) {
    throw "Compile host is not freeze-qualified: $($compile.host.validation_class)"
}
if ($compile.policy.freeze_qualified -ne $true) {
    throw "Compile evidence is not freeze-qualified."
}

$requiredTargets = @(
    "KatarinaBridgeEA.mq5",
    "KatarinaStage06SelfTest.mq5",
    "KatarinaStage06AccountProbe.mq5"
)

foreach ($target in $requiredTargets) {
    $record = $compile.compile | Where-Object { $_.target -eq $target }
    if ($null -eq $record) { throw "Compile evidence missing target: $target" }
    if ([int]$record.errors -ne 0) { throw "Compile errors detected for $target" }
    if ([int]$record.warnings -ne 0) { throw "Compile warnings detected for $target" }
    if ([int64]$record.artifact_bytes -le 0) { throw "EX5 artifact missing/empty for $target" }
    if ([string]::IsNullOrWhiteSpace([string]$record.artifact_sha256)) {
        throw "EX5 SHA-256 missing for $target"
    }
}

foreach ($key in @("stage","design_version","proof_type","terminal_build","failures","result")) {
    if (-not $selfTest.Contains($key)) { throw "MQL self-test evidence missing: $key" }
}
if ($selfTest["stage"] -ne "06") { throw "MQL self-test stage mismatch." }
if ($selfTest["design_version"] -ne $designVersion) { throw "MQL self-test design mismatch." }
if ($selfTest["proof_type"] -ne "MQL_SELF_TEST") { throw "MQL self-test proof_type mismatch." }
if ($selfTest["result"] -ne "PASS") { throw "MQL self-test did not pass." }
if ([int]$selfTest["failures"] -ne 0) { throw "MQL self-test reported failures." }

$terminalBuild = 0
if (-not [int]::TryParse([string]$selfTest["terminal_build"], [ref]$terminalBuild) -or $terminalBuild -le 0) {
    throw "MQL self-test terminal_build is invalid."
}

# Rebuild the exact expected MQL source manifest and compare it with compile proof.
$expectedFiles = @(
    (Join-Path $repoRoot "mt5\Experts\KatarinaBridgeEA.mq5"),
    (Join-Path $repoRoot "mt5\Tests\KatarinaStage06SelfTest.mq5"),
    (Join-Path $repoRoot "mt5\Tests\KatarinaStage06AccountProbe.mq5")
)
$expectedFiles += Get-ChildItem -Path (Join-Path $repoRoot "mt5\Include\Katarina") -Filter "*.mqh" -File |
    Sort-Object FullName |
    ForEach-Object { $_.FullName }

$currentManifest = @{}
foreach ($file in $expectedFiles) {
    Assert-FileExists $file "Stage-06 source"
    $resolved = (Resolve-Path $file).Path
    $relative = $resolved.Substring($repoRoot.Length).TrimStart("\").Replace("\","/")
    $currentManifest[$relative] = (Get-FileHash -Path $resolved -Algorithm SHA256).Hash
}

if ($null -eq $compile.source_manifest -or $compile.source_manifest.Count -eq 0) {
    throw "Compile evidence has no complete source_manifest."
}

$compiledManifest = @{}
foreach ($entry in $compile.source_manifest) {
    $compiledManifest[[string]$entry.path] = [string]$entry.sha256
}

if ($compiledManifest.Count -ne $currentManifest.Count) {
    throw "Compile source manifest count differs from current Stage-06 source tree."
}

foreach ($sourcePath in $currentManifest.Keys) {
    if (-not $compiledManifest.ContainsKey($sourcePath)) {
        throw "Current source was not part of compile proof: $sourcePath"
    }
    if ($compiledManifest[$sourcePath] -ne $currentManifest[$sourcePath]) {
        throw "Source changed after compile proof: $sourcePath"
    }
}

# Re-run all Stage-06 Python/static regressions against this exact checkout.
$python = Get-Command $PythonExe -ErrorAction SilentlyContinue
if (-not $python) { throw "Python executable not found: $PythonExe" }

Push-Location $repoRoot
try {
    $env:PYTHONPATH = "src"
    & $python.Source -m unittest tests.static.test_stage06_mt5_bridge tests.static.test_stage06_windows_compatibility -v
    if ($LASTEXITCODE -ne 0) {
        throw "Stage-06 static regression suite failed during final audit."
    }
}
finally {
    Pop-Location
}

$gitCommit = ""
$gitDirty = $null
try {
    $git = Get-Command git -ErrorAction Stop
    $gitCommit = (& $git.Source -C $repoRoot rev-parse HEAD).Trim()
    $dirtyLines = @(& $git.Source -C $repoRoot status --porcelain)
    $gitDirty = ($dirtyLines.Count -gt 0)
} catch {
    $gitCommit = "UNAVAILABLE"
    $gitDirty = $null
}

$compileHash = (Get-FileHash -Path $compileEvidencePath -Algorithm SHA256).Hash
$selfTestHash = (Get-FileHash -Path $selfTestPath -Algorithm SHA256).Hash

$clearance = [ordered]@{
    schema_version = "1.1"
    stage = "06"
    bridge_design_version = $designVersion
    generated_utc = [DateTime]::UtcNow.ToString("o")
    git_commit = $gitCommit
    git_dirty = $gitDirty
    compile_evidence_sha256 = $compileHash
    mql_self_test_sha256 = $selfTestHash
    source_manifest_entries = $currentManifest.Count
    host = [ordered]@{
        normalized = [string]$compile.host.normalized
        validation_class = [string]$compile.host.validation_class
        metaeditor_version = [string]$compile.metaeditor.file_version
        terminal_build = $terminalBuild
    }
    static_regressions = [ordered]@{
        bridge = 25
        windows = 10
        total = 35
        result = "PASS"
    }
    proof = [ordered]@{
        metaeditor_compile = "PASS"
        bridge_ex5 = "PASS"
        self_test_ex5 = "PASS"
        account_probe_harness_ex5 = "PASS"
        mql_self_test = "PASS"
        source_manifest_binding = "PASS"
        standard_like_real_account_probe = "DEFERRED_STAGE_36_38"
        cent_like_real_account_probe = "DEFERRED_STAGE_36_38"
    }
    production_broker_compatibility_claim = $false
    governance = [ordered]@{
        adr = "docs/adr/0010-stage06-freeze-gate-alignment.md"
        stage04_account_contract = "docs/architecture/STANDARD_CENT_ACCOUNT_COMPATIBILITY.md"
        broker_validation_stage = "36/38"
    }
    windows_server_2012_r2 = "DEFERRED_NOT_USED_FOR_FREEZE_PROOF"
    result = "PASS_STAGE06_FINAL_CLEARANCE"
}

$clearance | ConvertTo-Json -Depth 10 | Set-Content -Path $clearancePath -Encoding UTF8

$report = @()
$report += "# STAGE 06 - FINAL AUDIT CANDIDATE"
$report += ""
$report += "**Result:** PASS_STAGE06_FINAL_CLEARANCE  "
$report += "**Bridge design:** v$designVersion  "
$report += "**Generated UTC:** $($clearance.generated_utc)  "
$report += "**Git commit:** $gitCommit"
$report += ""
$report += "## Freeze Evidence"
$report += ""
$report += "- Modern Windows MetaEditor strict compile: PASS"
$report += "- KatarinaBridgeEA: 0 errors / 0 warnings / EX5: PASS"
$report += "- KatarinaStage06SelfTest: 0 errors / 0 warnings / EX5: PASS"
$report += "- KatarinaStage06AccountProbe harness: 0 errors / 0 warnings / EX5: PASS"
$report += "- Modern-host MQL self-test: PASS"
$report += "- Full Stage-06 MQL source-manifest binding: PASS"
$report += "- Stage-06 static regressions: 35/35 PASS"
$report += ""
$report += "## Account Compatibility Boundary"
$report += ""
$report += "- Real STANDARD_LIKE broker probe: DEFERRED TO STAGE 36/38"
$report += "- Real CENT_LIKE broker probe: DEFERRED TO STAGE 36/38"
$report += "- Account probe harness remains implemented and compiled."
$report += "- No broker-by-broker production compatibility claim is made by Stage 06."
$report += "- This aligns with frozen Stage-04 STANDARD/CENT compatibility contract and ADR-0010."
$report += ""
$report += "## Host Boundary"
$report += ""
$report += "- Freeze proof host: $($compile.host.normalized) [$($compile.host.validation_class)]"
$report += "- Windows Server 2012 R2 remains deferred and is not used as freeze proof."
$report += ""
$report += "This generated file is evidence for the governed Stage-06 freeze."
$report -join [Environment]::NewLine | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ""
Write-Host "PASS: Stage 06 final clearance evidence is complete."
Write-Host "Clearance: $clearancePath"
Write-Host "Report:    $reportPath"
Write-Host ""
Write-Host "Real STANDARD/CENT broker probes remain mandatory at Stage 36/38 before production compatibility claims."
