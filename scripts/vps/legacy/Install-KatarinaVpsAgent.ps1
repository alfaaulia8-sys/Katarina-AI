param(
    [Parameter(Mandatory=$true)]
    [string]$AgentId,

    [Parameter(Mandatory=$false)]
    [string]$Repository = "alfaaulia8-sys/Katarina-AI",

    [Parameter(Mandatory=$false)]
    [string]$Branch = "main",

    [Parameter(Mandatory=$false)]
    [string]$InstallRoot = "C:\KatarinaVPSAgent",

    [Parameter(Mandatory=$false)]
    [int]$PollSeconds = 15
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    Add-Type -AssemblyName System.Security -ErrorAction Stop
} catch {
    # Type can already be loaded on Windows Server 2012 R2.
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this installer from an elevated PowerShell window (Run as Administrator)."
    }
}

function Protect-Token {
    param([string]$PlainToken,[string]$Path)
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainToken)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    [IO.File]::WriteAllBytes($Path,$encrypted)
}

Assert-Administrator

$preflight = Join-Path $PSScriptRoot "Test-KatarinaVpsPrerequisites.ps1"
if (Test-Path $preflight) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preflight
    if ($LASTEXITCODE -ne 0) {
        throw "VPS prerequisite preflight failed. Installation stopped before any agent changes."
    }
}

if ($PollSeconds -lt 5) {
    throw "PollSeconds must be at least 5."
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$sourceAgent = Join-Path $PSScriptRoot "KatarinaVpsAgent.ps1"
$sourceWatchdog = Join-Path $PSScriptRoot "KatarinaVpsAgentWatchdog.ps1"
if (!(Test-Path $sourceAgent)) {
    throw "KatarinaVpsAgent.ps1 must be in the same folder as this installer."
}
if (!(Test-Path $sourceWatchdog)) {
    throw "KatarinaVpsAgentWatchdog.ps1 must be in the same folder as this installer."
}

$targetAgent = Join-Path $InstallRoot "KatarinaVpsAgent.ps1"
$targetWatchdog = Join-Path $InstallRoot "KatarinaVpsAgentWatchdog.ps1"
Copy-Item -Path $sourceAgent -Destination $targetAgent -Force
Copy-Item -Path $sourceWatchdog -Destination $targetWatchdog -Force

$config = [ordered]@{
    schema_version = 1
    agent_id = $AgentId
    repository = $Repository
    branch = $Branch
    poll_seconds = $PollSeconds
    installed_utc = [DateTime]::UtcNow.ToString("o")
}

$configPath = Join-Path $InstallRoot "agent.json"
$config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "GitHub Fine-Grained PAT is required once." -ForegroundColor Yellow
Write-Host "Repository: $Repository" -ForegroundColor Yellow
Write-Host "Permission: Contents = Read and write" -ForegroundColor Yellow
Write-Host "Do NOT paste the token into ChatGPT." -ForegroundColor Yellow
Write-Host ""

$secure = Read-Host "Paste the PAT here on the VPS only" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw "Token cannot be empty."
    }
    $tokenPath = Join-Path $InstallRoot "token.bin"
    Protect-Token -PlainToken $plain -Path $tokenPath
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$tokenPath = Join-Path $InstallRoot "token.bin"
try {
    & icacls.exe $tokenPath /inheritance:r /grant:r "*S-1-5-18:(R)" "*S-1-5-32-544:(F)" | Out-Null
} catch {
    Write-Warning "Could not tighten token ACL automatically. Review permissions on $tokenPath."
}

$taskName = "KatarinaVPSAgent"
$taskCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $targetAgent + '" -ConfigPath "' + $configPath + '"'

& schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN $taskName /TR $taskCommand | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to register scheduled task $taskName."
}

& schtasks.exe /Run /TN $taskName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Scheduled task was created but could not be started."
}

$watchdogTaskName = "KatarinaVPSAgentWatchdog"
$watchdogCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $targetWatchdog + '" -InstallRoot "' + $InstallRoot + '"'
& schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN $watchdogTaskName /TR $watchdogCommand | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to register scheduled task $watchdogTaskName."
}
& schtasks.exe /Run /TN $watchdogTaskName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Watchdog task was created but could not be started."
}

Write-Host ""
Write-Host "Katarina VPS Agent installed." -ForegroundColor Green
Write-Host "Agent ID: $AgentId"
Write-Host "Install:  $InstallRoot"
Write-Host "Task:     $taskName"
Write-Host ""
Write-Host "The agent uses outbound HTTPS only. No inbound firewall port is required."
