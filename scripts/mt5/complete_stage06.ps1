param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalDataPath,

    [Parameter(Mandatory=$true)]
    [string]$TerminalCommonDataPath,

    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath = "",

    [Parameter(Mandatory=$false)]
    [int]$RuntimeWaitMinutes = 90
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$commonFiles = Join-Path $TerminalCommonDataPath "Files"

if (!(Test-Path $commonFiles)) {
    throw "MT5 Common Files directory not found: $commonFiles"
}

$runtimeFiles = @(
    "Katarina_Stage06_self_test_result.txt",
    "Katarina_Stage06_account_probe_STANDARD_LIKE.txt",
    "Katarina_Stage06_account_probe_CENT_LIKE.txt"
)

Write-Host "=== Katarina Stage 06 complete clearance ==="
Write-Host ""
Write-Host "Step A: removing stale Stage-06 runtime evidence..."
foreach ($name in $runtimeFiles) {
    Remove-Item (Join-Path $commonFiles $name) -ErrorAction SilentlyContinue
}

Write-Host "Step B: host/static/MetaEditor proof..."
$verifyArgs = @{
    TerminalDataPath = $TerminalDataPath
}
if ($MetaEditorPath) {
    $verifyArgs.MetaEditorPath = $MetaEditorPath
}

& (Join-Path $PSScriptRoot "verify_stage06_modern_windows.ps1") @verifyArgs

Write-Host ""
Write-Host "=== COMPILE PROOF PASSED ==="
Write-Host ""
Write-Host "Now complete these read-only MT5 runtime steps:"
Write-Host "  1. In MT5 Navigator > Scripts, run KatarinaStage06SelfTest once."
Write-Host "  2. On a STANDARD-LIKE account, run KatarinaStage06AccountProbe with InpAccountClass=STANDARD_LIKE."
Write-Host "  3. On a CENT-LIKE account, run KatarinaStage06AccountProbe with InpAccountClass=CENT_LIKE."
Write-Host ""
Write-Host "No Katarina Stage-06 script submits broker orders."
Write-Host "This console will wait for all three fresh proof files."
Write-Host ""

$deadline = [DateTime]::UtcNow.AddMinutes($RuntimeWaitMinutes)

while ([DateTime]::UtcNow -lt $deadline) {
    $missing = @()

    foreach ($name in $runtimeFiles) {
        if (!(Test-Path (Join-Path $commonFiles $name))) {
            $missing += $name
        }
    }

    if ($missing.Count -eq 0) {
        break
    }

    Write-Host ("Waiting for runtime proof. Missing: " + ($missing -join ", "))
    Start-Sleep -Seconds 5
}

$stillMissing = @()
foreach ($name in $runtimeFiles) {
    if (!(Test-Path (Join-Path $commonFiles $name))) {
        $stillMissing += $name
    }
}

if ($stillMissing.Count -gt 0) {
    throw ("Runtime proof timeout. Missing: " + ($stillMissing -join ", "))
}

Write-Host ""
Write-Host "Step C: collecting and validating runtime evidence..."
& (Join-Path $PSScriptRoot "collect_stage06_runtime_evidence.ps1") -TerminalCommonDataPath $TerminalCommonDataPath

Write-Host ""
Write-Host "Step D: final evidence-bound audit..."
& (Join-Path $PSScriptRoot "audit_stage06_final.ps1")

Write-Host ""
Write-Host "=================================================="
Write-Host "STAGE 06 TECHNICAL CLEARANCE COMPLETE"
Write-Host "=================================================="
Write-Host ""
Write-Host "Generated:"
Write-Host "  build\mt5\stage06_compile_evidence.json"
Write-Host "  build\mt5\stage06_runtime_evidence.json"
Write-Host "  build\mt5\stage06_final_clearance.json"
Write-Host "  build\mt5\STAGE_06_FINAL_AUDIT_CANDIDATE.md"
Write-Host ""
Write-Host "After review, the repository can be frozen as Stage 06 v1.0.0."
