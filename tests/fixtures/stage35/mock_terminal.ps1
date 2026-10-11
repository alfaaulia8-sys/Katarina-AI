param([string]$Runner, [string]$Work, [string]$Mode)
$ErrorActionPreference = 'Stop'
$Terminal = Join-Path $Work 'terminal64.exe'
$Experts = Join-Path $Work 'MQL5/Experts'
$ReportRoot = $Work
if ($Mode -in @('existing','wrong_origin','both_modes')) {
    $ReportRoot = Join-Path $Work 'existing data'
    $Experts = Join-Path $ReportRoot 'MQL5/Experts'
    New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
    $OriginValue = if ($Mode -eq 'wrong_origin') { Join-Path $Work 'other terminal' } else { $Work }
    Set-Content (Join-Path $ReportRoot 'origin.txt') $OriginValue
}
New-Item -ItemType Directory -Force -Path $Experts | Out-Null
Set-Content -LiteralPath $Terminal -Value 'mock terminal'
Set-Content -LiteralPath (Join-Path $Experts 'Test.ex5') -Value 'mock compiled expert'
function Get-Process {
    param($Name, $ErrorAction)
    if ($Mode -eq 'running') { [PSCustomObject]@{Path=$Terminal} }
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$PassThru)
    $Arg = @($ArgumentList | Where-Object { $_ -like '/config:*' })[0]
    $Config = $Arg.Substring(8).Trim('"')
    $Values = @{}
    foreach ($Line in Get-Content -LiteralPath $Config) {
        if ($Line.Contains('=')) { $Pair=$Line.Split('=',2); $Values[$Pair[0]]=$Pair[1] }
    }
    if ($Values['AllowLiveTrading'] -ne '0') { throw 'Real trading not disabled' }
    if ($Mode -eq 'existing') {
        if ($ArgumentList -contains '/portable') { throw 'Existing installation launched as portable' }
        if (-not $Values['ExpertParameters']) { throw 'Explicit parameters missing' }
    } elseif ($ArgumentList -notcontains '/portable') { throw 'Portable mode missing' }
    $Report = Join-Path $ReportRoot ($Values['Report'] + '.htm')
    if ($Mode -eq 'unrelated') { $Report = Join-Path $Work 'old-report.htm' }
    if ($Mode -ne 'missing') {
        [IO.File]::WriteAllText($Report, '<html>Mock tester report</html>')
        if ($Mode -eq 'empty') { [IO.File]::WriteAllText($Report, '') }
        if ($Mode -eq 'stale') { (Get-Item $Report).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-1) }
    }
    $Code = if ($Mode -eq 'nonzero') { 7 } else { 0 }
    $P = [PSCustomObject]@{ Id=987654; ExitCode=$Code }
    $P | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
    return $P
}
function Wait-Process {
    param($Id,$Timeout,$ErrorAction)
    if ($Mode -eq 'timeout') { throw 'simulated timeout' }
}
function Stop-Process {
    param($Id,[switch]$Force,$ErrorAction)
    if ($Id -ne 987654) { throw 'Attempt to stop unrelated process' }
}
$Args = @{
    TerminalPath=$Terminal; Expert='Test'; Symbol='XAUUSD';
    FromDate='2026.01.01'; ToDate='2026.02.01'; Portable=$true;
    OutputRoot=(Join-Path $Work 'evidence with spaces')
}
if ($Mode -eq 'injection') { $Args.Symbol = "XAUUSD`nAllowLiveTrading=1" }
if ($Mode -eq 'dates') { $Args.ToDate = '2025.01.01' }
if ($Mode -eq 'traversal') { $Args.Expert = '../Test' }
if ($Mode -eq 'nonportable') { $Args.Portable = $false }
if ($Mode -in @('existing','wrong_origin','both_modes')) {
    $Args.Portable = ($Mode -eq 'both_modes')
    $Args.ExistingTerminalDataPath = $ReportRoot
}
if ($Mode -eq 'existing') {
    $Args.ParametersPath = Join-Path $Work 'fixture.set'
    Set-Content $Args.ParametersPath 'InpEnableBuy=true'
}
$global:LASTEXITCODE = 0
try {
    & $Runner @Args
    $RunnerSucceeded = $?
    $RunnerExitCode = $LASTEXITCODE
    if ($RunnerExitCode -ne 0) { exit $RunnerExitCode }
    if (-not $RunnerSucceeded) { exit 1 }  # Windows PowerShell 4 may suppress failed script exit.
    exit 0
} catch {
    [Console]::Error.WriteLine([string]$_)
    exit 1
}
