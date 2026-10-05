param(
    [Parameter(Mandatory=$true)][string]$TerminalPath,
    [Parameter(Mandatory=$true)][string]$Expert,
    [Parameter(Mandatory=$true)][string]$Symbol,
    [string]$Period = "M1",
    [Parameter(Mandatory=$true)][string]$FromDate,
    [Parameter(Mandatory=$true)][string]$ToDate,
    [string]$ReportName = "KatarinaStage35",
    [int]$Model = 4,
    [int]$Deposit = 10000,
    [int]$Leverage = 100,
    [int]$TimeoutSeconds = 3600,
    [switch]$Portable
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not (Test-Path -LiteralPath $TerminalPath -PathType Leaf)) {
    throw "terminal64.exe not found: $TerminalPath"
}
if ([IO.Path]::GetFileName($TerminalPath).ToLowerInvariant() -ne "terminal64.exe") {
    throw "TerminalPath must point to terminal64.exe"
}
if ($Model -notin @(0,1,2,3,4)) { throw "Unsupported MT5 tester Model=$Model" }
if ($Model -ne 4) {
    Write-Warning "Stage35 governed evidence should use Model=4 (Every tick based on real ticks)."
}
if ($TimeoutSeconds -lt 60) { throw "TimeoutSeconds must be >= 60" }

$Root = "C:\KatarinaDev\stage35"
$RunId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$RunRoot = Join-Path $Root $RunId
$EvidenceRoot = Join-Path $RunRoot "evidence"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$IniPath = Join-Path $RunRoot "tester.ini"
$Ini = @(
    "[Tester]",
    "Expert=$Expert",
    "Symbol=$Symbol",
    "Period=$Period",
    "Model=$Model",
    "FromDate=$FromDate",
    "ToDate=$ToDate",
    "ForwardMode=0",
    "Deposit=$Deposit",
    "Currency=USD",
    "Leverage=$Leverage",
    "Optimization=0",
    "Report=$ReportName",
    "ReplaceReport=1",
    "ShutdownTerminal=1",
    "Visual=0"
)
$Ini | Set-Content -LiteralPath $IniPath -Encoding UTF8

$Before = Get-Date
$LaunchArgs = @("/skipupdate", "/config:$IniPath")
if ($Portable) { $LaunchArgs += "/portable" }

$Process = Start-Process -FilePath $TerminalPath -ArgumentList $LaunchArgs -PassThru
$TimedOut = $false
try {
    Wait-Process -Id $Process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
} catch {
    $TimedOut = $true
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
}

$TerminalDir = Split-Path -Parent $TerminalPath
$Candidates = @()
$PortableReport = Join-Path $TerminalDir ($ReportName + ".htm")
if (Test-Path -LiteralPath $PortableReport) { $Candidates += Get-Item $PortableReport }

$AppDataRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (Test-Path -LiteralPath $AppDataRoot) {
    $Candidates += Get-ChildItem -LiteralPath $AppDataRoot -Filter ($ReportName + ".htm") -Recurse -File -ErrorAction SilentlyContinue
}

$Report = $Candidates | Where-Object { $_.LastWriteTime -ge $Before.AddMinutes(-1) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$ReportPath = if ($Report) { $Report.FullName } else { $null }
$ReportSha256 = if ($Report) { (Get-FileHash -LiteralPath $Report.FullName -Algorithm SHA256).Hash } else { $null }

$Evidence = [ordered]@{
    schema_version = 1
    proof_type = "KATARINA_STAGE35_MT5_TESTER"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    terminal_path = $TerminalPath
    expert = $Expert
    symbol = $Symbol
    period = $Period
    from_date = $FromDate
    to_date = $ToDate
    model = $Model
    model_real_ticks = ($Model -eq 4)
    optimization = 0
    shutdown_terminal = 1
    timed_out = $TimedOut
    process_exit_code = if ($TimedOut) { $null } else { $Process.ExitCode }
    report_path = $ReportPath
    report_sha256 = $ReportSha256
    report_present = ($null -ne $Report)
    live_risk_ready = $false
    live_execution_enabled = $false
    result = if ((-not $TimedOut) -and $Report -and ($Model -eq 4)) {
        "PASS_STAGE35_TESTER_INFRASTRUCTURE"
    } else {
        "FAIL_STAGE35_TESTER_INFRASTRUCTURE"
    }
}

$EvidencePath = Join-Path $EvidenceRoot "stage35-tester-evidence.json"
$Evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

Write-Host $Evidence.result
Write-Host "Evidence: $EvidencePath"
if ($Evidence.result -ne "PASS_STAGE35_TESTER_INFRASTRUCTURE") { exit 2 }
