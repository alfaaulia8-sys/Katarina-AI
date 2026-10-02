param(
    [Parameter(Mandatory=$true)]
    [string]$TerminalDataPath,

    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath = ""
)

$ErrorActionPreference = "Stop"

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

function Assert-CompileSuccess {
    param(
        [string]$LogPath,
        [string]$TargetName
    )

    if (!(Test-Path $LogPath)) {
        throw "Compile log not created for $TargetName"
    }

    $text = Get-Content -Path $LogPath -Raw
    if ($text -notmatch "0 errors") {
        Write-Host $text
        throw "MetaEditor compile failed for $TargetName"
    }

    Write-Host "PASS: $TargetName compiled with 0 errors"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$dataRoot = (Resolve-Path $TerminalDataPath).Path
$mqlRoot = Join-Path $dataRoot "MQL5"

if (!(Test-Path $mqlRoot)) {
    throw "MQL5 directory not found under TerminalDataPath: $mqlRoot"
}

$metaEditor = Resolve-MetaEditorPath -Requested $MetaEditorPath

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

$testSource = Join-Path $repoRoot "mt5\Tests\KatarinaStage06SelfTest.mq5"
$testTarget = Join-Path $scriptTargetDir "KatarinaStage06SelfTest.mq5"
Copy-Item -Path $testSource -Destination $testTarget -Force

$eaLog = Join-Path $buildDir "KatarinaBridgeEA.compile.log"
$testLog = Join-Path $buildDir "KatarinaStage06SelfTest.compile.log"

Remove-Item $eaLog -ErrorAction SilentlyContinue
Remove-Item $testLog -ErrorAction SilentlyContinue

$eaArgs = @(
    "/compile:`"$eaTarget`"",
    "/log:`"$eaLog`""
)
Start-Process -FilePath $metaEditor -ArgumentList $eaArgs -Wait | Out-Null
Assert-CompileSuccess -LogPath $eaLog -TargetName "KatarinaBridgeEA.mq5"

$testArgs = @(
    "/compile:`"$testTarget`"",
    "/log:`"$testLog`""
)
Start-Process -FilePath $metaEditor -ArgumentList $testArgs -Wait | Out-Null
Assert-CompileSuccess -LogPath $testLog -TargetName "KatarinaStage06SelfTest.mq5"

Write-Host ""
Write-Host "Stage 06 MetaEditor compile proof complete."
Write-Host "EA log:   $eaLog"
Write-Host "Test log: $testLog"
Write-Host ""
Write-Host "Next manual proof: run KatarinaStage06SelfTest from MT5 Scripts and confirm PASSED."
