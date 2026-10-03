param()

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PreflightVersion = "1.1.1"
$results = @()

function Add-Check {
    param([string]$Name,[bool]$Passed,[string]$Detail,[bool]$Required=$true)
    $script:results += [pscustomobject]@{
        check = $Name
        passed = $Passed
        required = $Required
        detail = $Detail
    }
}

function Test-DpapiRoundTrip {
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    } catch {
        # On some Windows/.NET builds the type may already be loaded even if Add-Type reports oddly.
    }

    try {
        $type = [System.Security.Cryptography.ProtectedData]
        $scopeType = [System.Security.Cryptography.DataProtectionScope]
        $plain = [Text.Encoding]::UTF8.GetBytes("KATARINA_DPAPI_PREFLIGHT")
        $encrypted = $type::Protect($plain,$null,$scopeType::LocalMachine)
        $decrypted = $type::Unprotect($encrypted,$null,$scopeType::LocalMachine)
        $roundTrip = [Text.Encoding]::UTF8.GetString($decrypted)
        return [pscustomobject]@{
            Passed = ($roundTrip -eq "KATARINA_DPAPI_PREFLIGHT")
            Detail = "LocalMachine protect/unprotect round-trip"
        }
    } catch {
        return [pscustomobject]@{
            Passed = $false
            Detail = $_.Exception.Message
        }
    }
}

Write-Host ""
Write-Host "KATARINA VPS PREFLIGHT v$PreflightVersion" -ForegroundColor Cyan
Write-Host "Target baseline: Windows Server 2012 R2 x64" -ForegroundColor Cyan
Write-Host ""

# PowerShell
$psVersion = $PSVersionTable.PSVersion.ToString()
$psOk = $PSVersionTable.PSVersion.Major -ge 4
Add-Check "PowerShell >= 4" $psOk $psVersion

# OS / architecture
try {
    $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
    $caption = [string]$os.Caption
    $version = [string]$os.Version
    $arch = [string]$os.OSArchitecture
    Add-Check "Windows detected" $true ("$caption | Version $version")
    Add-Check "64-bit Windows" ($arch -match "64") $arch

    $is2012R2 = (($caption -match "Windows Server 2012 R2") -or ($version -like "6.3*"))
    Add-Check "Windows Server 2012 R2 baseline" $is2012R2 ("$caption | $version") $false
} catch {
    Add-Check "Windows detected" $false $_.Exception.Message
    Add-Check "64-bit Windows" $false "OS query failed"
}

# .NET
try {
    $clr = [Environment]::Version.ToString()
    Add-Check ".NET CLR available" $true $clr
} catch {
    Add-Check ".NET CLR available" $false $_.Exception.Message
}

# DPAPI — explicit assembly load + real round trip
$dpapi = Test-DpapiRoundTrip
Add-Check "DPAPI LocalMachine round-trip" $dpapi.Passed $dpapi.Detail

# ZIP support used by the legacy agent
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zipType = [System.IO.Compression.ZipFile]
    Add-Check "ZIP extraction support" $true "System.IO.Compression.FileSystem"
} catch {
    Add-Check "ZIP extraction support" $false $_.Exception.Message
}

# GitHub over TLS 1.2
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri "https://api.github.com" -UseBasicParsing -Headers @{"User-Agent"="Katarina-VPS-Preflight/$PreflightVersion"} -TimeoutSec 20
    Add-Check "GitHub API over TLS 1.2" ($response.StatusCode -eq 200) ("HTTP " + $response.StatusCode)
} catch {
    Add-Check "GitHub API over TLS 1.2" $false $_.Exception.Message
}

# Task scheduler
$taskScheduler = Get-Command schtasks.exe -ErrorAction SilentlyContinue
Add-Check "Task Scheduler CLI" ($null -ne $taskScheduler) ($(if($taskScheduler){$taskScheduler.Source}else{"not found"}))

# Temp write
try {
    $probe = Join-Path $env:TEMP ("katarina-preflight-" + [Guid]::NewGuid().ToString("N") + ".txt")
    "KATARINA" | Set-Content -Path $probe -Encoding ASCII
    $ok = Test-Path $probe
    Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue
    Add-Check "Temporary file write" $ok $env:TEMP
} catch {
    Add-Check "Temporary file write" $false $_.Exception.Message
}

# Disk
try {
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    if ($disk) {
        $freeGb = [math]::Round(([double]$disk.FreeSpace / 1GB),2)
        Add-Check "C: free space >= 2 GB" ($disk.FreeSpace -ge 2GB) ("$freeGb GB free")
    } else {
        Add-Check "C: free space >= 2 GB" $false "C: not found"
    }
} catch {
    Add-Check "C: free space >= 2 GB" $false $_.Exception.Message
}

$results | Format-Table check,passed,required,detail -AutoSize

$failed = @($results | Where-Object { $_.required -and -not $_.passed })
Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "KATARINA VPS PREFLIGHT: FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "Required checks that failed:" -ForegroundColor Red
    foreach ($item in $failed) {
        Write-Host (" - " + $item.check + ": " + $item.detail) -ForegroundColor Red
    }
    exit 1
}

Write-Host "KATARINA VPS PREFLIGHT: PASS" -ForegroundColor Green
exit 0
