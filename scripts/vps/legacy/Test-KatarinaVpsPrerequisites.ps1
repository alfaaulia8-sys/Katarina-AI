param()

$ErrorActionPreference = "Stop"

$results = @()
function Add-Check {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $script:results += [pscustomobject]@{
        check = $Name
        passed = $Passed
        detail = $Detail
    }
}

$psOk = $PSVersionTable.PSVersion.Major -ge 4
Add-Check "PowerShell >= 4" $psOk $PSVersionTable.PSVersion.ToString()

$os = Get-WmiObject Win32_OperatingSystem
Add-Check "64-bit Windows" ($os.OSArchitecture -match "64") ($os.Caption + " " + $os.OSArchitecture)

try {
    $null = [Security.Cryptography.ProtectedData]
    Add-Check "DPAPI available" $true "System.Security.Cryptography.ProtectedData"
} catch {
    Add-Check "DPAPI available" $false $_.Exception.Message
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri "https://api.github.com" -UseBasicParsing -Headers @{"User-Agent"="Katarina-VPS-Preflight"} -TimeoutSec 20
    Add-Check "GitHub API over TLS 1.2" ($response.StatusCode -eq 200) ("HTTP " + $response.StatusCode)
} catch {
    Add-Check "GitHub API over TLS 1.2" $false $_.Exception.Message
}

$taskScheduler = Get-Command schtasks.exe -ErrorAction SilentlyContinue
Add-Check "Task Scheduler CLI" ($null -ne $taskScheduler) ($(if($taskScheduler){$taskScheduler.Source}else{"not found"}))

$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
if ($disk) {
    $freeGb = [math]::Round(([double]$disk.FreeSpace / 1GB),2)
    Add-Check "C: free space >= 2 GB" ($disk.FreeSpace -ge 2GB) ("$freeGb GB free")
} else {
    Add-Check "C: disk available" $false "C: not found"
}

$results | Format-Table -AutoSize

$failed = @($results | Where-Object { -not $_.passed })
if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "KATARINA VPS PREFLIGHT: FAIL"
    exit 1
}

Write-Host ""
Write-Host "KATARINA VPS PREFLIGHT: PASS"
exit 0
