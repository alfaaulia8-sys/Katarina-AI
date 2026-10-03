param()

$ErrorActionPreference = "Stop"

$DesignVersion = "0.5.0"
$AdministratorRoaming = "C:\Users\Administrator\AppData\Roaming"
$CommonFiles = Join-Path $AdministratorRoaming "MetaQuotes\Terminal\Common\Files"
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

    $known = @(
        [pscustomobject]@{
            Name = "MetaTrader 5 ALFA"
            Home = "C:\Program Files\MetaTrader 5 ALFA"
            Data = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\2698BCED53B80670A80FF375C9E8D6A1"
        },
        [pscustomobject]@{
            Name = "MetaTrader 5"
            Home = "C:\Program Files\MetaTrader 5"
            Data = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
        }
    )

    foreach ($item in $known) {
        $terminal = Join-Path $item.Home "terminal64.exe"
        $metaeditor = Join-Path $item.Home "metaeditor64.exe"
        $selfTest = Join-Path $item.Data "MQL5\Scripts\KatarinaStage06SelfTest.ex5"
        $probe = Join-Path $item.Data "MQL5\Scripts\KatarinaStage06AccountProbe.ex5"

        if ((Test-Path -LiteralPath $terminal) -and
            (Test-Path -LiteralPath $metaeditor) -and
            (Test-Path -LiteralPath $selfTest) -and
            (Test-Path -LiteralPath $probe)) {
            $instances += [pscustomobject]@{
                Name = $item.Name
                Home = $item.Home
                Terminal = $terminal
                MetaEditor = $metaeditor
                Data = $item.Data
                SelfTest = $selfTest
                Probe = $probe
            }
        }
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
    $configLines = @(
        "[Experts]",
        "AllowLiveTrading=0",
        "AllowDllImport=0",
        "Enabled=1",
        "Account=0",
        "Profile=0",
        "",
        "[StartUp]",
        ("Script=" + $ScriptName)
    )
    if (-not [string]::IsNullOrWhiteSpace($Symbol)) {
        $configLines += ("Symbol=" + $Symbol)
    }
    $configLines += @(
        "Period=H1",
        "ShutdownTerminal=1"
    )
    $configLines | Set-Content -LiteralPath $config -Encoding ASCII

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

function Get-EvidenceNumber {
    param($Evidence,[string]$Key)

    $raw = [string]$Evidence.Values[$Key]
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $value = 0.0
    $style = [Globalization.NumberStyles]::Float -bor [Globalization.NumberStyles]::AllowThousands
    if ([double]::TryParse($raw,$style,[Globalization.CultureInfo]::InvariantCulture,[ref]$value)) {
        return $value
    }
    if ([double]::TryParse($raw,[ref]$value)) {
        return $value
    }
    return $null
}

function Resolve-AutomaticAccountClasses {
    param($Instances,$Discoveries)

    if ($Instances.Count -ne 2 -or $Discoveries.Count -ne 2) {
        throw "Automatic Stage-06 classification currently requires exactly two verified MT5 account instances."
    }

    $scores = @(0,0)
    $strong = @(0,0)
    $reasons = @((New-Object System.Collections.ArrayList),(New-Object System.Collections.ArrayList))

    for ($i=0; $i -lt 2; $i++) {
        $currency = ([string]$Discoveries[$i].Values["account_currency"]).ToUpperInvariant()
        if ($currency -match "(CENT|USC|USCENT|CENTS)") {
            $scores[$i] += 2
            [void]$reasons[$i].Add("native account currency contains a cent-unit hint")
        }

        $server = ([string]$Discoveries[$i].Values["broker_server"]).ToUpperInvariant()
        if ($server -match "(^|[^A-Z])CENT([^A-Z]|$)") {
            $scores[$i] += 1
            [void]$reasons[$i].Add("broker server contains a cent hint (supporting only)")
        }
    }

    $contract = @(
        (Get-EvidenceNumber $Discoveries[0] "contract_size"),
        (Get-EvidenceNumber $Discoveries[1] "contract_size")
    )
    $vmin = @(
        (Get-EvidenceNumber $Discoveries[0] "volume_min"),
        (Get-EvidenceNumber $Discoveries[1] "volume_min")
    )
    $tick = @(
        (Get-EvidenceNumber $Discoveries[0] "tick_value"),
        (Get-EvidenceNumber $Discoveries[1] "tick_value")
    )

    if ($contract[0] -gt 0 -and $contract[1] -gt 0 -and $vmin[0] -gt 0 -and $vmin[1] -gt 0) {
        $minExposure = @($contract[0]*$vmin[0],$contract[1]*$vmin[1])
        $maxExp = [Math]::Max($minExposure[0],$minExposure[1])
        $minExp = [Math]::Min($minExposure[0],$minExposure[1])
        if ($minExp -gt 0 -and ($maxExp/$minExp) -ge 20.0) {
            $cent = $(if ($minExposure[0] -lt $minExposure[1]) { 0 } else { 1 })
            $scores[$cent] += 6
            $strong[$cent]++
            [void]$reasons[$cent].Add(("minimum tradable contract exposure is {0:N2}x smaller" -f ($maxExp/$minExp)))
        }
    }

    if ($contract[0] -gt 0 -and $contract[1] -gt 0 -and $tick[0] -gt 0 -and $tick[1] -gt 0) {
        $density = @($tick[0]/$contract[0],$tick[1]/$contract[1])
        $maxDen = [Math]::Max($density[0],$density[1])
        $minDen = [Math]::Min($density[0],$density[1])
        if ($minDen -gt 0 -and ($maxDen/$minDen) -ge 20.0) {
            $cent = $(if ($density[0] -gt $density[1]) { 0 } else { 1 })
            $scores[$cent] += 6
            $strong[$cent]++
            [void]$reasons[$cent].Add(("native tick-value density is {0:N2}x larger" -f ($maxDen/$minDen)))
        }
    }

    $difference = [Math]::Abs($scores[0]-$scores[1])
    $candidate = $(if ($scores[0] -gt $scores[1]) { 0 } elseif ($scores[1] -gt $scores[0]) { 1 } else { -1 })

    $report = [ordered]@{
        mode = "AUTO_FAIL_CLOSED"
        score_1 = $scores[0]
        score_2 = $scores[1]
        strong_evidence_1 = $strong[0]
        strong_evidence_2 = $strong[1]
        reasons_1 = @($reasons[0])
        reasons_2 = @($reasons[1])
        result = "AMBIGUOUS"
    }

    if ($candidate -lt 0 -or $difference -lt 5 -or $strong[$candidate] -lt 1) {
        return [pscustomobject]@{
            Passed = $false
            StandardIndex = -1
            CentIndex = -1
            Report = $report
        }
    }

    $standard = 1-$candidate
    $report.result = "CLASSIFIED"
    $report.cent_index = $candidate+1
    $report.standard_index = $standard+1

    return [pscustomobject]@{
        Passed = $true
        StandardIndex = $standard
        CentIndex = $candidate
        Report = $report
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
    $diag = Join-Path $RunRoot "discovery_failure.txt"
    @(
        "windows_user=" + $identity.Name,
        "appdata=" + $env:APPDATA,
        "instances_found=" + $instances.Count,
        "expected_admin_roaming=" + $AdministratorRoaming
    ) | Set-Content -LiteralPath $diag -Encoding UTF8
    throw "At least two compiled MT5 instances are required. Found: $($instances.Count). Diagnostic: $diag"
}

foreach ($instance in $instances) {
    if (Test-TerminalAlreadyRunning -Executable $instance.Terminal) {
        throw "Close MT5 before finalization: $($instance.Terminal)"
    }
}

Write-Step "Account discovery (automatic gold symbol detection)"
$discoveries = @()
for ($i=0; $i -lt $instances.Count; $i++) {
    Write-Host ("Probing " + $instances[$i].Name + " ...")
    $d = Invoke-Stage06Script -Instance $instances[$i] -ScriptName "KatarinaStage06AccountProbe" -Symbol "" -AccountClass "DISCOVERY"
    $copy = Join-Path $RunRoot ("discovery-" + ($i+1) + ".txt")
    Copy-Item -LiteralPath $d.Path -Destination $copy -Force
    $discoveries += $d
    Show-Discovery -Index ($i+1) -Instance $instances[$i] -Evidence $d
}

Write-Step "Automatic STANDARD_LIKE / CENT_LIKE classification"
$classification = Resolve-AutomaticAccountClasses -Instances $instances -Discoveries $discoveries
$classification.Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunRoot "account_classification.json") -Encoding UTF8

if (-not $classification.Passed) {
    Write-Host "Automatic account classification is AMBIGUOUS. No account class was guessed." -ForegroundColor Yellow
    throw "Stage 06 automatic account classification is ambiguous. See account_classification.json."
}

$standardIndex = [int]$classification.StandardIndex
$centIndex = [int]$classification.CentIndex

$stdKey = [string]$discoveries[$standardIndex].Values["broker_server"] + "|" + [string]$discoveries[$standardIndex].Values["login_last4"]
$centKey = [string]$discoveries[$centIndex].Values["broker_server"] + "|" + [string]$discoveries[$centIndex].Values["login_last4"]
if ($stdKey -eq $centKey) {
    throw "Automatically selected terminals use the same broker account identity. Stage 06 requires distinct accounts."
}

Write-Host ("AUTO STANDARD_LIKE: [" + ($standardIndex+1) + "] " + $instances[$standardIndex].Name) -ForegroundColor Green
Write-Host ("AUTO CENT_LIKE    : [" + ($centIndex+1) + "] " + $instances[$centIndex].Name) -ForegroundColor Green

$standardSymbol = [string]$discoveries[$standardIndex].Values["symbol"]
$centSymbol = [string]$discoveries[$centIndex].Values["symbol"]

Write-Step "MQL self-test"
$self = Invoke-Stage06Script -Instance $instances[$standardIndex] -ScriptName "KatarinaStage06SelfTest" -Symbol $standardSymbol
Copy-Item -LiteralPath $self.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_self_test_result.txt") -Force
Write-Host "Self-test PASS." -ForegroundColor Green

Write-Step "STANDARD_LIKE probe"
$std = Invoke-Stage06Script -Instance $instances[$standardIndex] -ScriptName "KatarinaStage06AccountProbe" -Symbol $standardSymbol -AccountClass "STANDARD_LIKE"
Copy-Item -LiteralPath $std.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_account_probe_STANDARD_LIKE.txt") -Force
Write-Host "STANDARD_LIKE PASS." -ForegroundColor Green

Write-Step "CENT_LIKE probe"
$cent = Invoke-Stage06Script -Instance $instances[$centIndex] -ScriptName "KatarinaStage06AccountProbe" -Symbol $centSymbol -AccountClass "CENT_LIKE"
Copy-Item -LiteralPath $cent.Path -Destination (Join-Path $RunRoot "Katarina_Stage06_account_probe_CENT_LIKE.txt") -Force
Write-Host "CENT_LIKE PASS." -ForegroundColor Green

$summary = [ordered]@{
    schema_version = 1
    stage = "06"
    design_version = $DesignVersion
    generated_utc = [DateTime]::UtcNow.ToString("o")
    windows_user = $identity.Name
    symbol_mode = "AUTO_PER_MT5"
    account_classification_mode = "AUTO_FAIL_CLOSED"
    account_classification = $classification.Report
    standard = [ordered]@{
        symbol = $standardSymbol
        terminal = $instances[$standardIndex].Name
        broker_server = $std.Values["broker_server"]
        login_last4 = $std.Values["login_last4"]
        account_currency = $std.Values["account_currency"]
    }
    cent = [ordered]@{
        symbol = $centSymbol
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
