param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalDataPath,

    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $repoRoot

try {
    Write-Host "=== Stage 06 / Modern Windows host preflight ==="
    & (Join-Path $PSScriptRoot "check_stage06_host.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Host preflight failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "=== Stage 06 / Python static regression tests ==="

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "python.exe was not found. Install a supported Python on the modern Windows validation host before running the full verification."
    }

    $env:PYTHONPATH = "src"
    & $python.Source -m unittest tests.static.test_stage06_mt5_bridge tests.static.test_stage06_windows_compatibility -v

    if ($LASTEXITCODE -ne 0) {
        throw "Stage 06 Python static tests failed."
    }

    Write-Host ""
    Write-Host "=== Stage 06 / MetaEditor strict compile proof ==="

    $compileArgs = @{ TerminalDataPath = $TerminalDataPath }
    if ($MetaEditorPath) {
        $compileArgs.MetaEditorPath = $MetaEditorPath
    }

    & (Join-Path $PSScriptRoot "compile_stage06.ps1") @compileArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Stage 06 MetaEditor compile proof failed."
    }

    Write-Host ""
    Write-Host "=== AUTOMATED HOST-SIDE VERIFICATION PASSED ==="
    Write-Host ""
    Write-Host "Manual MT5 runtime proof still required:"
    Write-Host "  1. Run KatarinaStage06SelfTest from MT5 Scripts."
    Write-Host "  2. Run KatarinaStage06AccountProbe on a standard-like account."
    Write-Host "  3. Run KatarinaStage06AccountProbe on a cent-like account."
    Write-Host "  4. Verify a second bridge instance is blocked in the same terminal/account."
    Write-Host "  5. Preserve logs/evidence for the final Stage 06 audit."
}
finally {
    Pop-Location
}
