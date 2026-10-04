param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceRoot = "C:\KatarinaDev",

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Version = "3.11.9"
$RuntimeRoot = Join-Path $WorkspaceRoot "runtime"
$PythonRoot = Join-Path $RuntimeRoot "python"
$DownloadRoot = Join-Path $RuntimeRoot "downloads"
$SourceRoot = Join-Path $WorkspaceRoot "workspace"

New-Item -ItemType Directory -Force -Path $OutputDir,$RuntimeRoot,$DownloadRoot | Out-Null

$PythonExe = Join-Path $PythonRoot "python.exe"
$Archive = Join-Path $DownloadRoot ("python-" + $Version + "-embed-amd64.zip")
$PythonUrl = "https://www.python.org/ftp/python/$Version/python-$Version-embed-amd64.zip"

if (!(Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    if (!(Test-Path -LiteralPath $Archive -PathType Leaf)) {
        Invoke-WebRequest -Uri $PythonUrl -OutFile $Archive -UseBasicParsing
    }

    if (Test-Path -LiteralPath $PythonRoot) {
        Remove-Item -LiteralPath $PythonRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $PythonRoot | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$PythonRoot)

    $Pth = Join-Path $PythonRoot "python311._pth"
    if (!(Test-Path -LiteralPath $Pth -PathType Leaf)) {
        throw "Embedded Python python311._pth is missing."
    }

    $Existing = @(Get-Content -LiteralPath $Pth)
    $Updated = @()
    $HaveSitePackages = $false
    $HaveImportSite = $false

    foreach ($Line in $Existing) {
        if ($Line -eq "Lib\site-packages") {
            $HaveSitePackages = $true
        }
        if ($Line -match '^\s*#?\s*import site\s*$') {
            if (-not $HaveImportSite) {
                $Updated += "import site"
                $HaveImportSite = $true
            }
            continue
        }
        $Updated += $Line
    }

    if (-not $HaveSitePackages) {
        $Updated += "Lib\site-packages"
    }
    if (-not $HaveImportSite) {
        $Updated += "import site"
    }

    $Updated | Set-Content -LiteralPath $Pth -Encoding ASCII
    New-Item -ItemType Directory -Force -Path (Join-Path $PythonRoot "Lib\site-packages") | Out-Null
}

$VersionOutput = & $PythonExe --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Portable Python executable failed to start."
}
$VersionOutput | Set-Content -LiteralPath (Join-Path $OutputDir "python_version.txt") -Encoding UTF8

$GetPip = Join-Path $DownloadRoot "get-pip.py"
if (!(Test-Path -LiteralPath $GetPip -PathType Leaf)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip -UseBasicParsing
}

& $PythonExe -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
    & $PythonExe $GetPip --disable-pip-version-check --no-warn-script-location *>&1 |
        Set-Content -LiteralPath (Join-Path $OutputDir "get_pip.log") -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "get-pip failed for portable Python."
    }
}

$Requirements = Join-Path $SourceRoot "requirements-stage07.txt"
if (Test-Path -LiteralPath $Requirements -PathType Leaf) {
    & $PythonExe -m pip install --disable-pip-version-check --only-binary=:all: -r $Requirements *>&1 |
        Set-Content -LiteralPath (Join-Path $OutputDir "pip_install.log") -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "Stage-07 Python dependency installation failed."
    }
}

$ProbeScript = Join-Path $OutputDir "python_probe.py"
@'
import sys
print(sys.version)
import zmq
import tornado
print("pyzmq=" + zmq.__version__)
print("libzmq=" + zmq.zmq_version())
print("tornado=" + tornado.version)
'@ | Set-Content -LiteralPath $ProbeScript -Encoding ASCII

& $PythonExe $ProbeScript *>&1 |
    Set-Content -LiteralPath (Join-Path $OutputDir "python_probe.txt") -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
    throw "Portable Python dependency probe failed."
}

$Evidence = [ordered]@{
    schema_version = 1
    runtime = "CPYTHON_EMBEDDABLE"
    python_version = $Version
    python_exe = $PythonExe
    workspace = $SourceRoot
    requirements = $(if (Test-Path -LiteralPath $Requirements) { $Requirements } else { $null })
    result = "PASS"
    completed_utc = [DateTime]::UtcNow.ToString("o")
}
$Evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDir "python_bootstrap.json") -Encoding UTF8
exit 0
