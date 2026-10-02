param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalDataPath,

    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath = ""
)

$ErrorActionPreference = "Stop"

function Get-Stage06HostProfile {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = [string]$os.Caption
    $normalized = "UNKNOWN"
    $class = "UNSUPPORTED"

    if (-not [Environment]::Is64BitOperatingSystem) {
        $normalized = "WINDOWS_X86_32_BIT"
        $class = "UNSUPPORTED"
    }
    elseif ($caption -match "Windows Server 2012 R2") {
        $normalized = "WINDOWS_SERVER_2012_R2_X64"
        $class = "DEFERRED"
    }
    elseif ($caption -match "Windows Server 2016") {
        $normalized = "WINDOWS_SERVER_2016_X64"
        $class = "COMPATIBILITY"
    }
    elseif ($caption -match "Windows Server 2019") {
        $normalized = "WINDOWS_SERVER_2019_X64"
        $class = "COMPATIBILITY"
    }
    elseif ($caption -match "Windows Server 2022") {
        $normalized = "WINDOWS_SERVER_2022_X64"
        $class = "PREFERRED"
    }
    elseif ($caption -match "Windows 11") {
        $normalized = "WINDOWS_11_X64"
        $class = "PREFERRED"
    }
    elseif ($caption -match "Windows 10") {
        $normalized = "WINDOWS_10_X64"
        $class = "COMPATIBILITY"
    }

    [pscustomobject]@{
        caption = $caption
        version = [string]$os.Version
        architecture = [string]$os.OSArchitecture
        normalized = $normalized
        validation_class = $class
        powershell_version = $PSVersionTable.PSVersion.ToString()
        is_64_bit = [Environment]::Is64BitOperatingSystem
    }
}

function Assert-Stage06Host {
    param($Profile)

    if ($Profile.validation_class -eq "DEFERRED") {
        throw "Windows Server 2012 R2 is intentionally deferred and cannot produce the current Stage 06 freeze proof."
    }

    if ($Profile.validation_class -eq "UNSUPPORTED") {
        throw "This Windows host is outside the current Stage 06 validation baseline."
    }
}

function Resolve-MetaEditorPath {
    param([string]$Requested)

    if ($Requested -and (Test-Path $Requested)) {
        return (Resolve-Path $Requested).Path
    }

    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $candidates = @(
        "$env:ProgramFiles\MetaTrader 5\metaeditor64.exe",
        "$programFilesX86\MetaTrader 5\metaeditor64.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "MetaEditor64.exe not found. Pass -MetaEditorPath explicitly."
}

function Read-MetaEditorLog {
    param([string]$LogPath)

    if (!(Test-Path $LogPath)) {
        throw "Compile log not created: $LogPath"
    }

    # MetaEditor compile logs are commonly UTF-16LE. Read explicitly so result
    # parsing does not depend on the PowerShell host's default encoding.
    return [System.IO.File]::ReadAllText(
        (Resolve-Path $LogPath).Path,
        [System.Text.Encoding]::Unicode
    )
}

function Get-CompileSummary {
    param(
        [string]$LogPath,
        [string]$TargetName
    )

    $text = Read-MetaEditorLog -LogPath $LogPath
    $matches = [regex]::Matches(
        $text,
        "(?im)(?<errors>\d+)\s+errors?\s*,\s*(?<warnings>\d+)\s+warnings?"
    )

    if ($matches.Count -eq 0) {
        Write-Host $text
        throw "Could not find MetaEditor error/warning summary for $TargetName"
    }

    $last = $matches[$matches.Count - 1]
    $errors = [int]$last.Groups["errors"].Value
    $warnings = [int]$last.Groups["warnings"].Value

    [pscustomobject]@{
        target = $TargetName
        errors = $errors
        warnings = $warnings
        log_path = (Resolve-Path $LogPath).Path
    }
}

function Assert-CompileSuccess {
    param(
        [string]$LogPath,
        [string]$TargetName,
        [string]$ArtifactPath
    )

    $summary = Get-CompileSummary -LogPath $LogPath -TargetName $TargetName

    if ($summary.errors -ne 0) {
        Write-Host (Read-MetaEditorLog -LogPath $LogPath)
        throw "MetaEditor compile failed for $TargetName with $($summary.errors) error(s)."
    }

    if ($summary.warnings -ne 0) {
        Write-Host (Read-MetaEditorLog -LogPath $LogPath)
        throw "MetaEditor compile produced $($summary.warnings) warning(s) for $TargetName. Stage 06 uses a zero-warning freeze policy."
    }

    if (!(Test-Path $ArtifactPath)) {
        throw "Compile log passed but EX5 artifact was not created for $TargetName at $ArtifactPath"
    }

    $artifact = Get-Item $ArtifactPath
    if ($artifact.Length -le 0) {
        throw "EX5 artifact is empty for $TargetName"
    }

    $hash = (Get-FileHash -Path $ArtifactPath -Algorithm SHA256).Hash

    Write-Host "PASS: $TargetName -> 0 errors, 0 warnings, EX5 exists"

    [pscustomobject]@{
        target = $TargetName
        errors = 0
        warnings = 0
        artifact_path = $artifact.FullName
        artifact_bytes = $artifact.Length
        artifact_sha256 = $hash
        log_path = $summary.log_path
    }
}

function Invoke-MetaEditorCompile {
    param(
        [string]$MetaEditor,
        [string]$SourcePath,
        [string]$MqlRoot,
        [string]$LogPath
    )

    $args = @(
        "/compile:`"$SourcePath`"",
        "/inc:`"$MqlRoot`"",
        "/log:`"$LogPath`""
    )

    Start-Process -FilePath $MetaEditor -ArgumentList $args -Wait | Out-Null
}

$hostProfile = Get-Stage06HostProfile
Assert-Stage06Host -Profile $hostProfile

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$dataRoot = (Resolve-Path $TerminalDataPath).Path
$mqlRoot = Join-Path $dataRoot "MQL5"

if (!(Test-Path $mqlRoot)) {
    throw "MQL5 directory not found under TerminalDataPath: $mqlRoot"
}

$metaEditor = Resolve-MetaEditorPath -Requested $MetaEditorPath
$metaEditorInfo = Get-Item $metaEditor

$includeTarget = Join-Path $mqlRoot "Include\Katarina"
$expertTargetDir = Join-Path $mqlRoot "Experts"
$scriptTargetDir = Join-Path $mqlRoot "Scripts"
$buildDir = Join-Path $repoRoot "build\mt5"

New-Item -ItemType Directory -Force -Path $includeTarget | Out-Null
New-Item -ItemType Directory -Force -Path $expertTargetDir | Out-Null
New-Item -ItemType Directory -Force -Path $scriptTargetDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

Copy-Item -Path (Join-Path $repoRoot "mt5\Include\Katarina\*.mqh") -Destination $includeTarget -Force

$eaSource = Join-Path $repoRoot "mt5\Experts\KatarinaBridgeEA.mq5"
$eaTarget = Join-Path $expertTargetDir "KatarinaBridgeEA.mq5"
Copy-Item -Path $eaSource -Destination $eaTarget -Force

$selfTestSource = Join-Path $repoRoot "mt5\Tests\KatarinaStage06SelfTest.mq5"
$selfTestTarget = Join-Path $scriptTargetDir "KatarinaStage06SelfTest.mq5"
Copy-Item -Path $selfTestSource -Destination $selfTestTarget -Force

$probeSource = Join-Path $repoRoot "mt5\Tests\KatarinaStage06AccountProbe.mq5"
$probeTarget = Join-Path $scriptTargetDir "KatarinaStage06AccountProbe.mq5"
Copy-Item -Path $probeSource -Destination $probeTarget -Force

$eaArtifact = [System.IO.Path]::ChangeExtension($eaTarget, ".ex5")
$selfTestArtifact = [System.IO.Path]::ChangeExtension($selfTestTarget, ".ex5")
$probeArtifact = [System.IO.Path]::ChangeExtension($probeTarget, ".ex5")

$eaLog = Join-Path $buildDir "KatarinaBridgeEA.compile.log"
$selfTestLog = Join-Path $buildDir "KatarinaStage06SelfTest.compile.log"
$probeLog = Join-Path $buildDir "KatarinaStage06AccountProbe.compile.log"
$evidencePath = Join-Path $buildDir "stage06_compile_evidence.json"

foreach ($path in @(
    $eaLog,
    $selfTestLog,
    $probeLog,
    $evidencePath,
    $eaArtifact,
    $selfTestArtifact,
    $probeArtifact
)) {
    Remove-Item $path -ErrorAction SilentlyContinue
}

Invoke-MetaEditorCompile -MetaEditor $metaEditor -SourcePath $eaTarget -MqlRoot $mqlRoot -LogPath $eaLog
$eaResult = Assert-CompileSuccess -LogPath $eaLog -TargetName "KatarinaBridgeEA.mq5" -ArtifactPath $eaArtifact

Invoke-MetaEditorCompile -MetaEditor $metaEditor -SourcePath $selfTestTarget -MqlRoot $mqlRoot -LogPath $selfTestLog
$selfTestResult = Assert-CompileSuccess -LogPath $selfTestLog -TargetName "KatarinaStage06SelfTest.mq5" -ArtifactPath $selfTestArtifact

Invoke-MetaEditorCompile -MetaEditor $metaEditor -SourcePath $probeTarget -MqlRoot $mqlRoot -LogPath $probeLog
$probeResult = Assert-CompileSuccess -LogPath $probeLog -TargetName "KatarinaStage06AccountProbe.mq5" -ArtifactPath $probeArtifact

$evidence = [ordered]@{
    schema_version = "1.0"
    stage = "06"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    host = $hostProfile
    metaeditor = [ordered]@{
        path = $metaEditorInfo.FullName
        file_version = $metaEditorInfo.VersionInfo.FileVersion
        product_version = $metaEditorInfo.VersionInfo.ProductVersion
    }
    source = [ordered]@{
        bridge_sha256 = (Get-FileHash -Path $eaSource -Algorithm SHA256).Hash
        self_test_sha256 = (Get-FileHash -Path $selfTestSource -Algorithm SHA256).Hash
        account_probe_sha256 = (Get-FileHash -Path $probeSource -Algorithm SHA256).Hash
    }
    compile = @(
        $eaResult,
        $selfTestResult,
        $probeResult
    )
    policy = [ordered]@{
        zero_errors = $true
        zero_warnings = $true
        ex5_required = $true
        windows_server_2012_r2_deferred = $true
    }
    result = "PASS_COMPILE_PROOF"
}

$evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $evidencePath -Encoding UTF8

Write-Host ""
Write-Host "Katarina Stage 06 compile proof PASSED"
Write-Host "Host:       $($hostProfile.normalized) [$($hostProfile.validation_class)]"
Write-Host "MetaEditor: $($metaEditorInfo.VersionInfo.FileVersion)"
Write-Host "Evidence:   $evidencePath"
Write-Host ""
Write-Host "Next: run KatarinaStage06SelfTest and KatarinaStage06AccountProbe inside MT5."
