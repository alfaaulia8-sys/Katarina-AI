param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceRoot = "C:\KatarinaDev",

    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = "",

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$StdoutPath,
        [Parameter(Mandatory=$true)][string]$StderrPath
    )

    Remove-Item -LiteralPath $StdoutPath,$StderrPath -Force -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    return [int]$p.ExitCode
}

$Version = "3.12.10"
$RuntimeRoot = Join-Path $WorkspaceRoot "runtime"
$PythonRoot = Join-Path $RuntimeRoot "python"
$DownloadRoot = Join-Path $RuntimeRoot "downloads"
if (!$SourceRoot) { $SourceRoot = Join-Path $WorkspaceRoot "workspace" }
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

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

    $Pth = Join-Path $PythonRoot "python312._pth"
    if (!(Test-Path -LiteralPath $Pth -PathType Leaf)) {
        throw "Embedded Python python312._pth is missing."
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

# Normalize the embeddable runtime path on every run. Another workspace task may
# replace the Python directory, so this must not live only inside first-install logic.
$Pth = Join-Path $PythonRoot "python312._pth"
if (!(Test-Path -LiteralPath $Pth -PathType Leaf)) {
    throw "Embedded Python python312._pth is missing."
}

$Existing = @(Get-Content -LiteralPath $Pth)
$Updated = @()
$RequiredPaths = @("Lib\site-packages","..\..\workspace","..\..\workspace\src")
$Seen = @{}
$HaveImportSite = $false

foreach ($Line in $Existing) {
    $Trimmed = ([string]$Line).Trim()
    if ($Trimmed -match '^\s*#?\s*import site\s*$') {
        if (-not $HaveImportSite) {
            $Updated += "import site"
            $HaveImportSite = $true
        }
        continue
    }

    foreach ($Required in $RequiredPaths) {
        if ($Trimmed -ieq $Required) {
            $Seen[$Required] = $true
        }
    }
    $Updated += $Line
}

foreach ($Required in $RequiredPaths) {
    if (-not $Seen.ContainsKey($Required)) {
        $Updated += $Required
    }
}
if (-not $HaveImportSite) {
    $Updated += "import site"
}

$Updated | Set-Content -LiteralPath $Pth -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $PythonRoot "Lib\site-packages") | Out-Null

# The installer root and approved Git checkout can differ. Embedded Python
# ignores PYTHONPATH, including in nested -c probes, so bind the checkout explicitly.
$Binder = Join-Path $SourceRoot "scripts\pc\bind_portable_runtime.py"
if (!(Test-Path -LiteralPath $Binder -PathType Leaf)) { throw "Approved source runtime binder missing." }
$BindOut = Join-Path $OutputDir "source_binding.txt"
$BindErr = Join-Path $OutputDir "source_binding_error.txt"
$QuotedBinder = '"'+$Binder+'"'
$QuotedRuntime = '"'+$PythonRoot+'"'
$QuotedSource = '"'+$SourceRoot+'"'
$Exit = Invoke-NativeChecked -FilePath $PythonExe -Arguments @($QuotedBinder,'--runtime-root',$QuotedRuntime,'--source-root',$QuotedSource) -StdoutPath $BindOut -StderrPath $BindErr
if ($Exit -ne 0) { throw "Portable Python source binding failed." }

$VersionStdout = Join-Path $OutputDir "python_version.txt"
$VersionStderr = Join-Path $OutputDir "python_version_error.txt"
$Exit = Invoke-NativeChecked -FilePath $PythonExe -Arguments @("--version") -StdoutPath $VersionStdout -StderrPath $VersionStderr
if($Exit -ne 0) { throw "Portable Python executable failed to start." }

$GetPip = Join-Path $DownloadRoot "get-pip.py"
if (!(Test-Path -LiteralPath $GetPip -PathType Leaf)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip -UseBasicParsing
}

$GetPipOut = Join-Path $OutputDir "get_pip.log"
$GetPipErr = Join-Path $OutputDir "get_pip_error.log"
$Exit = Invoke-NativeChecked -FilePath $PythonExe -Arguments @($GetPip,"--disable-pip-version-check","--no-warn-script-location") -StdoutPath $GetPipOut -StderrPath $GetPipErr
if($Exit -ne 0) { throw "get-pip failed for portable Python." }

$Requirements = Join-Path $SourceRoot "requirements-stage07.txt"
if(Test-Path -LiteralPath $Requirements -PathType Leaf) {
    $PipOut = Join-Path $OutputDir "pip_install.log"
    $PipErr = Join-Path $OutputDir "pip_install_error.log"
    $Exit = Invoke-NativeChecked -FilePath $PythonExe -Arguments @("-m","pip","install","--disable-pip-version-check","--only-binary=:all:","-r",$Requirements) -StdoutPath $PipOut -StderrPath $PipErr
    if($Exit -ne 0) { throw "Stage-07 Python dependency installation failed." }
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

$ProbeOut = Join-Path $OutputDir "python_probe.txt"
$ProbeErr = Join-Path $OutputDir "python_probe_error.txt"
$Exit = Invoke-NativeChecked -FilePath $PythonExe -Arguments @($ProbeScript) -StdoutPath $ProbeOut -StderrPath $ProbeErr
if($Exit -ne 0) { throw "Portable Python dependency probe failed." }

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
