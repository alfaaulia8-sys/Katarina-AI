param()

$ErrorActionPreference = "Stop"

$DesignVersion = "0.5.0"
$CommonFiles = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
$RunRoot = Join-Path "C:\KatarinaStage06Runtime" ([DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss"))

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=== " + $Text + " ===") -ForegroundColor Cyan
}

function Read-Evidence {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $idx = $line.IndexOf("=")
        if ($idx -gt 0) {
            $values[$line.Substring(0,$idx).Trim()] = $line.Substring($idx+1).Trim()
        }
    }
    return $values
}

function Get-TerminalInstances {
    $instances = @()
    $originPattern = Join-Path $env:APPDATA "MetaQuotes\Terminal\*\origin.txt"

    foreach ($origin in @(Get-ChildItem -Path $originPattern -ErrorAction SilentlyContinue)) {
        try {
            $home = (Get-Content -LiteralPath $origin.FullName -Raw).Trim()
            if (-not $home) { continue }

            $terminal = Join-Path $home "terminal64.exe"
            $metaeditor = Join-Path $home "metaeditor64.exe"
            $data = Split-Path -Parent $origin.FullName
            $selfTest = Join-Path $data "MQL5\Scripts\KatarinaStage06SelfTest.ex5"
            $probe = Join-Path $data "MQL5\Scripts\KatarinaStage06AccountProbe.ex5"

            if ((Test-Path -LiteralPath $terminal) -and
                (Test-Path -LiteralPath $metaeditor) -and
                (Test-Path -LiteralPath $selfTest) -and
                (Test-Path -LiteralPath $probe)) {
                $instances += [pscustomobject]@{
                    Name = Split-Path -Leaf $home
                    Home = $home
                    Terminal = $terminal
                    MetaEditor = $metaeditor
                    Data = $data
                    SelfTest = $selfTest
                    Probe = $probe
                }
            }
        } catch {}
    }

    return @($instances)
}

function Test-TerminalAlreadyRunning {
    param([string]$Executable)

    try {
        foreach ($proc in @(Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue)) {
            if ($proc.ExecutablePath -and
                [string]::Equals($proc.ExecutablePath,$Executable,[StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    } catch {}
    return $false
}

function Wait-Evidence {
    param(
        [string]$Path,
        [DateTime]$NotBefore,
        [int]$Seconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $f = Get-Item -LiteralPath $Path
            if ($f.LastWriteTimeUtc -ge $NotBefore.AddSeconds(-2)) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-Stage06Script {
    param(
        $Instance,
        [string]$ScriptName,
        [string]$Symbol,
        [string]$AccountClass = ""
    )

    if (Test-TerminalAlreadyRunning -Executable $Instance.Terminal) {
        throw "Terminal is already running: $($Instance.Terminal). Close this MT5 instance and run the finalizer again."
    }

    if (-not (Test-Path -LiteralPath $CommonFiles)) {
        New-Item -ItemType Directory -Force -Path $CommonFiles | Out-Null
    }

    $controlFile = Join-Path $CommonFiles "Katarina_Stage06_probe_class.txt"
    if ($ScriptName -eq "KatarinaStage06AccountProbe") {
        Set-Content -LiteralPath $controlFile -Value $AccountClass -Encoding ASCII
        $evidence = Join-Path $CommonFiles ("Katarina_Stage06_account_probe_" + $AccountClass + ".txt")
    }
    else {
        $evidence = Join-Path $CommonFiles "Katarina_Stage06_self_test_result.txt"
    }

    Remove-Item -LiteralPath $evidence -Force -ErrorAction SilentlyContinue

    $config = Join-Path $RunRoot ("run-" + $ScriptName + "-" + ([Guid]::NewGuid().ToString("N")) + ".ini")
    @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Script=$ScriptName
Symbol=$Symbol
Period=H1
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $config -Encoding ASCII

    $started = [DateTime]::UtcNow
    $arg = '/config:"' + $config + '"'
    $p = Start-Process -FilePath $Instance.Terminal -ArgumentList $arg -PassThru

    if (-not $p.WaitForExit(90000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "Runtime script timed out: $ScriptName on $($Instance.Name)"
    }

    if (-not (Wait-Evidence -Path $evidence -NotBefore $started -Seconds 15)) {
        throw "Evidence not created by $ScriptName on $($Instance.Name). Check symbol '$Symbol' and saved MT5 account/profile."
    }

    $values = Read-Evidence -Path $evidence
    if ($values["stage"] -ne "06") { throw "Evidence stage mismatch." }
    if ($values["design_version"] -ne $DesignVersion) { throw "Evidence design version mismatch." }
    if ($values["result"] -ne "PASS") {
        throw "$ScriptName returned FAIL on $($Instance.Name)."
    }

    return [pscustomobject]@{
        Path = $evidence
        Values = $values
        ExitCode = $p.ExitCode
    }
}

function Show-Discovery {
    param([int]$Index,$Instance,$Evidence)

    $v = $Evidence.Values
    Write-Host ""
    Write-Host ("[" + $Index + "] " + $Instance.Name) -ForegroundColor Yellow
    Write-Host ("    Server        : " + $v["broker_server"])
    Write-Host ("    Login last4   : " + $v["login_last4"])
    Write-Host ("    Currency      : " + $v["account_currency"])
    Write-Host ("    Currency digit: " + $v["account_currency_digits"])
    Write-Host ("    Symbol        : " + $v["symbol"])
    Write-Host ("    Contract size : " + $v["contract_size"])
    Write-Host ("    Tick value    : " + $v["tick_value"])
    Write-Host ("    Volume min    : " + $v["volume_min"])
    Write-Host ("    Volume step   : " + $v["volume_step"])
    Write-Host ("    Connected     : " + $v["terminal_connected"])
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.Name -match "\\SYSTEM$") {
    throw "This finalizer must be run from the interactive Administrator/user session, not SYSTEM."
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
New-Item -ItemType Directory -Force -Path $CommonFiles | Out-Null

Write-Host ""
Write-Host "KATARINA AI - STAGE 06 RUNTIME FINALIZER" -ForegroundColor Green
Write-Host "Read-only proof. Live trading is disabled by startup configuration." -ForegroundColor Green
Write-Host ("Windows user: " + $identity.Name)
Write-Host ""

$instances = Get-TerminalInstances
if ($instances.Count -lt 2) {
    throw "At least two compiled MT5 instances are required for distinct STANDARD_LIKE and CENT_LIKE probes. Found: $($instances.Count)"
}

foreach ($instance in $instances) {
    if (Test-TerminalAlreadyRunning -Executable $instance.Terminal) {
        throw "Close MT5 before finalization: $($instance.Terminal)"
    }
}

$symbol = Read-Host "Symbol for account probe [XAUUSD]"
if ([string]::IsNullOrWhiteSpace($symbol)) { $symbol = "XAUUSD" }

Write-Step "Account discovery"
$discoveries = @()
for ($i=0; $i -lt $instances.Count; $i++) {
    Write-Host ("Probing " + $instances[$i].Name + " ...")
    $d = Invoke-Stage06Script -Instance $instances[$i] -ScriptName "KatarinaStage06AccountProbe" -Symbol $symbol -AccountClass "DISCOVERY"
    $copy = Join-Path $RunRoot ("discovery-" + ($i+1) + ".txt")
    Copy-Item -LiteralPath $d.Path -Destination $copy -Force
    $discoveries += $d
    Show-Discovery -Index ($i+1) -Instance $instances[$i] -Evidence $d
}

Write-Host ""
Write-Host "Katarina does NOT infer standard/cent from marketing labels or currency codes." -ForegroundColor Yellow
Write-Host "Choose the classes based on the actual broker accounts you configured." -ForegroundColor Yellow

$standardIndex = [int](Read-Host "Number for STANDARD_LIKE account") - 1
$centIndex = [int](Read-Host "Number for CENT_LIKE account") - 1

if ($standardIndex -lt 0 -or $standardIndex -ge $instances.Count) { throw "Invalid STANDARD_LIKE selection." }
if ($centIndex -lt 0 -or $centIndex -ge $instances.Count) { throw "Invalid CENT_LIKE selection." }
if ($standardIndex -eq $centIndex) { throw "STANDARD_LIKE and CENT_LIKE must use distinct account instances." }

$stdKey = [string]$discoveries[$standardIndex].Values["broker_server"] + "|" + [string]$discoveries[$standardIndex].Values["login_last4"]
$centKey = [string]$discoveries[$centIndex].Values["broker_server"] + "|" + [string]$discoveries[$centIndex].Values["login_last4"]
if ($stdKey -eq $centKey) {
    throw "Selected terminals appear to use the same broker account identity. Stage 06 requires distinct account probes."
}

Write-Step "MQL self-test"
$self = Invoke-Stage06Script -Instance $instances[$standardIndex] -ScriptName "KatarinaStage06SelfTest" -Symbol $symbol
Copy-Item -LiteralPath $self.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_self_test_result.txt") -Force
Write-Host "Self-test PASS." -ForegroundColor Green

Write-Step "STANDARD_LIKE probe"
$std = Invoke-Stage06Script -Instance $instances[$standardIndex] -ScriptName "KatarinaStage06AccountProbe" -Symbol $symbol -AccountClass "STANDARD_LIKE"
Copy-Item -LiteralPath $std.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_account_probe_STANDARD_LIKE.txt") -Force
Write-Host "STANDARD_LIKE PASS." -ForegroundColor Green

Write-Step "CENT_LIKE probe"
$cent = Invoke-Stage06Script -Instance $instances[$centIndex] -ScriptName "KatarinaStage06AccountProbe" -Symbol $symbol -AccountClass "CENT_LIKE"
Copy-Item -LiteralPath $cent.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_account_probe_CENT_LIKE.txt") -Force
Write-Host "CENT_LIKE PASS." -ForegroundColor Green

$summary = [ordered]@{
    schema_version = 1
    stage = "06"
    design_version = $DesignVersion
    generated_utc = [DateTime]::UtcNow.ToString("o")
    windows_user = $identity.Name
    symbol = $symbol
    standard = [ordered]@{
        terminal = $instances[$standardIndex].Name
        broker_server = $std.Values["broker_server"]
        login_last4 = $std.Values["login_last4"]
        account_currency = $std.Values["account_currency"]
    }
    cent = [ordered]@{
        terminal = $instances[$centIndex].Name
        broker_server = $cent.Values["broker_server"]
        login_last4 = $cent.Values["login_last4"]
        account_currency = $cent.Values["account_currency"]
    }
    result = "PASS_STAGE06_RUNTIME_PROBES"
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunRoot "runtime_summary.json") -Encoding UTF8

Remove-Item -LiteralPath (Join-Path $CommonFiles "Katarina_Stage06_probe_class.txt") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " STAGE 06 RUNTIME PROBES READY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ("Evidence remains in: " + $CommonFiles)
Write-Host ("Local audit copy : " + $RunRoot)
Write-Host ""
Write-Host "Return to ChatGPT and type: cek Stage 06 runtime" -ForegroundColor Yellow
