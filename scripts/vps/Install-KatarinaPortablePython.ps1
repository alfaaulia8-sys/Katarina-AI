param(
 [string]$Url="https://www.python.org/ftp/python/3.8.10/python-3.8.10-embed-amd64.zip",
 [string]$RuntimeRoot="C:\KatarinaDev\runtime\python"
)
$ErrorActionPreference="Stop"
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$uri=[Uri]$Url
if($uri.Scheme -ne "https" -or $uri.Host -ne "www.python.org"){throw "Portable Python source is not allowlisted."}
if($uri.AbsolutePath -ne "/ftp/python/3.8.10/python-3.8.10-embed-amd64.zip"){throw "Unexpected Python package path."}
$parent=Split-Path -Parent $RuntimeRoot
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$tmp=Join-Path $parent "python-3.8.10-embed-amd64.zip"
Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
$sha=(Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
if(Test-Path -LiteralPath $RuntimeRoot){Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force}
New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($tmp,$RuntimeRoot)
$python=Join-Path $RuntimeRoot "python.exe"
if(!(Test-Path -LiteralPath $python -PathType Leaf)){throw "python.exe missing after extraction."}
$out=& $python -c "import sys,platform,json; print(json.dumps({'version':sys.version,'executable':sys.executable,'machine':platform.machine()}))"
if($LASTEXITCODE -ne 0){throw "Portable Python smoke test failed."}
[ordered]@{
 schema_version=1
 version="3.8.10"
 source=$Url
 archive_sha256=$sha
 executable=$python
 smoke_test=($out -join "")
 result="PASS"
} | ConvertTo-Json -Depth 6
