param(
    [string]$InstallRoot = "C:\KatarinaVPSAgent",
    [string]$Repository = "alfaauliau-katarinaAI/Katarina-AI",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch {}

function Unprotect-Token([string]$Path) {
    $encrypted = [IO.File]::ReadAllBytes($Path)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [Text.Encoding]::UTF8.GetString($plain)
}

function Get-RepoText([string]$RepoPath,[hashtable]$Headers) {
    $escaped = ($RepoPath -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Repository/contents/$escaped?ref=$([Uri]::EscapeDataString($Branch))"
    $item = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers
    $raw = [Convert]::FromBase64String(([string]$item.content -replace "\s",""))
    return [Text.Encoding]::UTF8.GetString($raw)
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$tokenPath = Join-Path $InstallRoot "token.bin"
$configPath = Join-Path $InstallRoot "agent.json"
if(!(Test-Path -LiteralPath $tokenPath -PathType Leaf)){ throw "token.bin missing." }
if(!(Test-Path -LiteralPath $configPath -PathType Leaf)){ throw "agent.json missing." }

$token = Unprotect-Token $tokenPath
$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "Katarina-Agent-Repair/1.0"
}

$agentText = Get-RepoText "scripts/vps/legacy/KatarinaVpsAgent.ps1" $headers
$watchdogText = Get-RepoText "scripts/vps/legacy/KatarinaVpsAgentWatchdog.ps1" $headers

$agentPath = Join-Path $InstallRoot "KatarinaVpsAgent.ps1"
$watchdogPath = Join-Path $InstallRoot "KatarinaVpsAgentWatchdog.ps1"
$agentText | Set-Content -LiteralPath $agentPath -Encoding UTF8
$watchdogText | Set-Content -LiteralPath $watchdogPath -Encoding UTF8

$agentTask = "KatarinaVPSAgent"
$watchdogTask = "KatarinaVPSAgentWatchdog"

try { & schtasks.exe /End /TN $agentTask | Out-Null } catch {}
Start-Sleep -Seconds 2

$agentCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $agentPath + '" -ConfigPath "' + $configPath + '"'
& schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN $agentTask /TR $agentCommand | Out-Null
if($LASTEXITCODE -ne 0){ throw "Failed to recreate KatarinaVPSAgent." }

$watchdogCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $watchdogPath + '" -InstallRoot "' + $InstallRoot + '"'
& schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN $watchdogTask /TR $watchdogCommand | Out-Null
if($LASTEXITCODE -ne 0){ throw "Failed to create KatarinaVPSAgentWatchdog." }

& schtasks.exe /Run /TN $agentTask | Out-Null
if($LASTEXITCODE -ne 0){ throw "Failed to start KatarinaVPSAgent." }

Start-Sleep -Seconds 3
& schtasks.exe /Run /TN $watchdogTask | Out-Null
if($LASTEXITCODE -ne 0){ throw "Failed to start KatarinaVPSAgentWatchdog." }

Write-Host "KATARINA AGENT REPAIR PASS"
Write-Host "Agent task: $agentTask"
Write-Host "Watchdog task: $watchdogTask"
Write-Host "No PAT was requested; existing encrypted token.bin was reused."
