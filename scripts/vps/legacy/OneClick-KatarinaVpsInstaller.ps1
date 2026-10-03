param()

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch {}

$InstallerVersion = "1.2.0"
$AgentId = "katarina-vps-2012r2-01"
$Repository = "alfaaulia-katarina/Katarina-AI"
$Branch = "main"
$InstallRoot = "C:\KatarinaVPSAgent"
$PreflightScript = Join-Path $PSScriptRoot "Test-KatarinaVpsPrerequisites.ps1"
$AgentSource = Join-Path $PSScriptRoot "KatarinaVpsAgent.ps1"
$SessionId = "bootstrap-" + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0,8))
$LocalLog = Join-Path $env:TEMP ("katarina-" + $SessionId + ".log")
$script:Headers = $null

function Log-Line {
    param([string]$Text)
    $line = "[{0}] {1}" -f [DateTime]::UtcNow.ToString("o"), $Text
    Add-Content -Path $LocalLog -Value $line -Encoding UTF8
    Write-Host $Text
}

function New-GitHubHeaders {
    param([string]$Token)
    return @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "Katarina-OneClick/$InstallerVersion"
    }
}

function Put-GitHubTextFile {
    param([string]$Path,[string]$Text,[string]$Message)

    $escaped = ($Path -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Repository/contents/$escaped"
    $sha = $null

    try {
        $existing = Invoke-RestMethod -Method GET -Uri ($uri + "?ref=" + [Uri]::EscapeDataString($Branch)) -Headers $script:Headers
        $sha = [string]$existing.sha
    } catch {}

    $body = [ordered]@{
        message = $Message
        content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
        branch = $Branch
    }
    if ($sha) { $body["sha"] = $sha }

    $json = $body | ConvertTo-Json -Depth 8
    Invoke-RestMethod -Method PUT -Uri $uri -Headers $script:Headers -ContentType "application/json" -Body $json | Out-Null
}

function Upload-Telemetry {
    param([string]$Status,[string]$ErrorText="")

    if ($null -eq $script:Headers) { return }

    try {
        $os = $null
        try { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop } catch {}

        $summary = [ordered]@{
            schema_version = 1
            installer_version = $InstallerVersion
            session_id = $SessionId
            agent_id = $AgentId
            status = $Status
            error = $ErrorText
            computer_name = $env:COMPUTERNAME
            os_caption = $(if($os){$os.Caption}else{$null})
            os_version = $(if($os){$os.Version}else{$null})
            powershell_version = $PSVersionTable.PSVersion.ToString()
            generated_utc = [DateTime]::UtcNow.ToString("o")
        } | ConvertTo-Json -Depth 8

        $base = "ops/vps/bootstrap/$AgentId/$SessionId"
        Put-GitHubTextFile -Path "$base/summary.json" -Text $summary -Message "vps-bootstrap: $AgentId $Status"

        if (Test-Path $LocalLog) {
            $logText = Get-Content -Path $LocalLog -Raw
            if ($logText.Length -gt 900000) {
                $logText = $logText.Substring($logText.Length - 900000)
            }
            Put-GitHubTextFile -Path "$base/installer.log" -Text $logText -Message "vps-bootstrap: installer log $SessionId"
        }
    } catch {
        Write-Host ("Telemetry upload failed: " + $_.Exception.Message) -ForegroundColor DarkYellow
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

function Read-Pat {
    Write-Host ""
    Write-Host "Paste GitHub Fine-Grained PAT once." -ForegroundColor Yellow
    Write-Host "Repository: $Repository" -ForegroundColor Yellow
    Write-Host "Permission: Contents = Read and write" -ForegroundColor Yellow
    Write-Host "The PAT is never printed or added to logs." -ForegroundColor Yellow
    $secure = Read-Host "GitHub PAT" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ([string]::IsNullOrWhiteSpace($plain)) { throw "PAT cannot be empty." }
        return $plain
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " KATARINA AI VPS BOOTSTRAP v$InstallerVersion" -ForegroundColor Cyan
Write-Host " Connect First / Automatic Error Telemetry" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$pat = $null

try {
    Log-Line "Bootstrap session: $SessionId"

    $pat = Read-Pat
    $script:Headers = New-GitHubHeaders -Token $pat

    Log-Line "Checking authenticated GitHub connection..."
    $repoCheck = Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$Repository" -Headers $script:Headers
    if ([string]$repoCheck.full_name -ne $Repository) {
        throw "Unexpected repository returned by GitHub."
    }

    Log-Line "GitHub connection: PASS"
    Upload-Telemetry -Status "CONNECTED"

    if (!(Test-Path $PreflightScript)) { throw "Missing preflight script." }
    if (!(Test-Path $AgentSource)) { throw "Missing KatarinaVpsAgent.ps1." }

    Log-Line "Running VPS preflight..."
    $preflightOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreflightScript 2>&1
    foreach ($line in @($preflightOutput)) { Log-Line ([string]$line) }

    if ($LASTEXITCODE -ne 0) {
        throw "VPS prerequisite check failed."
    }

    Log-Line "Preflight: PASS"
    Log-Line "Installing persistent agent..."

    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Copy-Item -Path $AgentSource -Destination (Join-Path $InstallRoot "KatarinaVpsAgent.ps1") -Force

    $config = [ordered]@{
        schema_version = 1
        agent_id = $AgentId
        repository = $Repository
        branch = $Branch
        poll_seconds = 15
        installed_utc = [DateTime]::UtcNow.ToString("o")
    }
    $configPath = Join-Path $InstallRoot "agent.json"
    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

    $tokenPath = Join-Path $InstallRoot "token.bin"
    Protect-Token -PlainToken $pat -Path $tokenPath
    try {
        & icacls.exe $tokenPath /inheritance:r /grant:r "*S-1-5-18:(R)" "*S-1-5-32-544:(F)" | Out-Null
    } catch {}

    $taskName = "KatarinaVPSAgent"
    $targetAgent = Join-Path $InstallRoot "KatarinaVpsAgent.ps1"
    $taskCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $targetAgent + '" -ConfigPath "' + $configPath + '"'

    & schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN $taskName /TR $taskCommand | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create KatarinaVPSAgent scheduled task." }

    & schtasks.exe /Run /TN $taskName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "KatarinaVPSAgent task was created but failed to start." }

    Start-Sleep -Seconds 3
    & schtasks.exe /Query /TN $taskName /FO LIST /V > $null 2>&1
    if ($LASTEXITCODE -ne 0) { throw "KatarinaVPSAgent task verification failed." }

    Log-Line "Persistent agent installed and started: PASS"
    Upload-Telemetry -Status "INSTALLED"

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " KATARINA VPS CONNECTED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Runtime errors can now report themselves to GitHub." -ForegroundColor Green
    Write-Host "Return to ChatGPT and type: cek koneksi VPS" -ForegroundColor Yellow
    exit 0
}
catch {
    $err = $_.Exception.Message
    Log-Line ("ERROR: " + $err)
    Upload-Telemetry -Status "FAILED" -ErrorText $err

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " INSTALLATION FAILED - DIAGNOSTIC LOG SENT TO GITHUB" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "No screenshot is required." -ForegroundColor Yellow
    Write-Host "Return to ChatGPT and type: cek error VPS" -ForegroundColor Yellow
    exit 1
}
finally {
    $pat = $null
}
