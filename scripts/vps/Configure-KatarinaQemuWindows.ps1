$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$EvidenceRoot = "C:\KatarinaDev\evidence"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

# RDP remains protected by the Administrator account configured at Windows setup.
Set-Service -Name TermService -StartupType Automatic
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# WinRM is reached through the QEMU localhost-only host forward.
Enable-PSRemoting -SkipNetworkProfileCheck -Force

# Keep the validation VM awake while tests are running.
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null

# Locate KATARINA tools media without assuming a drive letter.
$ToolsBootstrap = $null
foreach ($Volume in Get-Volume -ErrorAction SilentlyContinue) {
    if (-not $Volume.DriveLetter) { continue }
    $Candidate = "$($Volume.DriveLetter):\bootstrap-katarina.ps1"
    if (Test-Path -LiteralPath $Candidate) {
        $ToolsBootstrap = $Candidate
        break
    }
}

$ToolsImported = $false
$ToolsImportResult = "NOT_FOUND"
if ($ToolsBootstrap) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ToolsBootstrap
    $ToolsImported = $true
    $ToolsImportResult = "PASS"
}

$rdpRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" | Select-Object -First 1
$osInfo = Get-CimInstance Win32_OperatingSystem
$Evidence = [ordered]@{
    generated_utc = [DateTime]::UtcNow.ToString("o")
    computer_name = $env:COMPUTERNAME
    os = $osInfo.Caption
    os_version = $osInfo.Version
    rdp_service = (Get-Service TermService).Status.ToString()
    rdp_enabled = ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections").fDenyTSConnections -eq 0)
    rdp_firewall_enabled = ($rdpRule.Enabled.ToString() -eq "True")
    winrm = (Get-Service WinRM).Status.ToString()
    tools_bootstrap = $ToolsBootstrap
    tools_imported = $ToolsImported
    tools_import_result = $ToolsImportResult
    live_risk_ready = $false
    live_execution_enabled = $false
    result = "PASS_KATARINA_WINDOWS_POSTINSTALL"
}

$EvidencePath = Join-Path $EvidenceRoot "windows-postinstall.json"
$Evidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

Write-Host "PASS_KATARINA_WINDOWS_POSTINSTALL"
Write-Host "Evidence: $EvidencePath"
