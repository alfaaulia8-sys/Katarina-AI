param()

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AgentId = "katarina-vps-2012r2-01"
$InstallScript = Join-Path $PSScriptRoot "Install-KatarinaVpsAgent.ps1"
$PreflightScript = Join-Path $PSScriptRoot "Test-KatarinaVpsPrerequisites.ps1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " KATARINA AI - ONE CLICK VPS INSTALLER" -ForegroundColor Cyan
Write-Host " Windows Server 2012 R2 x64" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This installer will automatically:" -ForegroundColor White
Write-Host "  1. Check VPS compatibility"
Write-Host "  2. Install Katarina VPS Agent"
Write-Host "  3. Register automatic startup"
Write-Host "  4. Start the agent"
Write-Host "  5. Verify the scheduled task"
Write-Host ""
Write-Host "You only need to paste your GitHub Fine-Grained PAT when asked." -ForegroundColor Yellow
Write-Host "The PAT must be limited to repository alfaaulia-katarina/Katarina-AI" -ForegroundColor Yellow
Write-Host "with Contents = Read and write." -ForegroundColor Yellow
Write-Host "Do NOT paste that PAT into ChatGPT." -ForegroundColor Yellow
Write-Host ""

if (!(Test-Path $PreflightScript)) {
    throw "Missing file: Test-KatarinaVpsPrerequisites.ps1"
}
if (!(Test-Path $InstallScript)) {
    throw "Missing file: Install-KatarinaVpsAgent.ps1"
}
if (!(Test-Path (Join-Path $PSScriptRoot "KatarinaVpsAgent.ps1"))) {
    throw "Missing file: KatarinaVpsAgent.ps1"
}

Write-Host "[1/3] Checking Windows Server..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreflightScript
if ($LASTEXITCODE -ne 0) {
    throw "VPS prerequisite check failed. Installation stopped before any agent changes."
}

Write-Host ""
Write-Host "[2/3] Installing Katarina VPS Agent..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -AgentId $AgentId
if ($LASTEXITCODE -ne 0) {
    throw "Katarina VPS Agent installer returned exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "[3/3] Verifying installation..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

$configPath = "C:\KatarinaVPSAgent\agent.json"
$agentPath = "C:\KatarinaVPSAgent\KatarinaVpsAgent.ps1"

if (!(Test-Path $configPath)) {
    throw "Installation verification failed: agent.json not found."
}
if (!(Test-Path $agentPath)) {
    throw "Installation verification failed: KatarinaVpsAgent.ps1 not found."
}

$taskOutput = & schtasks.exe /Query /TN "KatarinaVPSAgent" /FO LIST /V 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Installation verification failed: Scheduled Task KatarinaVPSAgent not found."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " KATARINA VPS AGENT INSTALLED SUCCESSFULLY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Agent ID : $AgentId"
Write-Host "Folder   : C:\KatarinaVPSAgent"
Write-Host "Task     : KatarinaVPSAgent"
Write-Host ""
Write-Host "You can now return to ChatGPT and type:" -ForegroundColor White
Write-Host "  cek koneksi VPS" -ForegroundColor Yellow
Write-Host ""
exit 0
