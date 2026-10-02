param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "C:\KatarinaVPSAgent\agent.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AgentVersion = "1.0.0"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Unprotect-Token {
    param([string]$Path)
    $encrypted = [IO.File]::ReadAllBytes($Path)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted,
        $null,
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [Text.Encoding]::UTF8.GetString($plain)
}

function New-GitHubHeaders {
    param([string]$Token)
    return @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "Katarina-VPS-Agent/$AgentVersion"
    }
}

function Invoke-GitHubJson {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        $Body = $null
    )

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }

    $json = $Body | ConvertTo-Json -Depth 12
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
}

function Get-GitHubFile {
    param(
        [string]$Repo,
        [string]$Path,
        [string]$Ref,
        [hashtable]$Headers
    )

    $escaped = ($Path -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Repo/contents/$escaped?ref=$([Uri]::EscapeDataString($Ref))"
    $item = Invoke-GitHubJson -Method "GET" -Uri $uri -Headers $Headers
    $raw = [Convert]::FromBase64String(($item.content -replace "\s",""))
    return [Text.Encoding]::UTF8.GetString($raw)
}

function Put-GitHubTextFile {
    param(
        [string]$Repo,
        [string]$Path,
        [string]$Branch,
        [string]$Message,
        [string]$Text,
        [hashtable]$Headers
    )

    $escaped = ($Path -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $uri = "https://api.github.com/repos/$Repo/contents/$escaped"
    $sha = $null

    try {
        $existing = Invoke-GitHubJson -Method "GET" -Uri ($uri + "?ref=" + [Uri]::EscapeDataString($Branch)) -Headers $Headers
        $sha = $existing.sha
    } catch {
        $sha = $null
    }

    $body = [ordered]@{
        message = $Message
        content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
        branch = $Branch
    }
    if ($sha) { $body["sha"] = $sha }

    [void](Invoke-GitHubJson -Method "PUT" -Uri $uri -Headers $Headers -Body $body)
}

function Download-RepoSnapshot {
    param(
        [string]$Repo,
        [string]$Ref,
        [string]$Destination,
        [hashtable]$Headers
    )

    if (Test-Path $Destination) {
        Remove-Item -Path $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    $zip = Join-Path $Destination "repo.zip"
    $extract = Join-Path $Destination "src"
    New-Item -ItemType Directory -Force -Path $extract | Out-Null

    $uri = "https://api.github.com/repos/$Repo/zipball/$([Uri]::EscapeDataString($Ref))"
    Invoke-WebRequest -Uri $uri -Headers $Headers -OutFile $zip -UseBasicParsing

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)

    $root = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
    if ($null -eq $root) {
        throw "Repository snapshot extraction produced no root directory."
    }
    return $root.FullName
}

function Redact-ResultText {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $value = $Text
    $value = [regex]::Replace(
        $value,
        '(?im)\b(password|passwd|token|api[_-]?key|secret)\b\s*[:=]\s*\S+',
        '$1=[REDACTED]'
    )
    $value = [regex]::Replace(
        $value,
        '(?im)\b(login|account)\b\s*[:=]?\s*\d{5,}',
        '$1=[REDACTED]'
    )
    return $value
}

if (!(Test-Path $ConfigPath)) {
    throw "Agent config not found: $ConfigPath"
}

$config = Read-JsonFile $ConfigPath
$installRoot = Split-Path -Parent $ConfigPath
$tokenPath = Join-Path $installRoot "token.bin"
$handledPath = Join-Path $installRoot "handled.txt"
$workRoot = Join-Path $installRoot "work"

if (!(Test-Path $tokenPath)) {
    throw "Encrypted GitHub token not found: $tokenPath"
}

New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
if (!(Test-Path $handledPath)) {
    New-Item -ItemType File -Force -Path $handledPath | Out-Null
}

$token = Unprotect-Token $tokenPath
$headers = New-GitHubHeaders $token
$repo = [string]$config.repository
$branch = [string]$config.branch
$agentId = [string]$config.agent_id
$pollSeconds = [int]$config.poll_seconds
$requestsDir = "ops/vps/requests/legacy"
$resultsDir = "ops/vps/results"

Write-Host "Katarina VPS Agent $AgentVersion"
Write-Host "Agent: $agentId"
Write-Host "Repo:  $repo"
Write-Host "Mode:  outbound HTTPS polling / allowlisted tasks only"

while ($true) {
    try {
        $listUri = "https://api.github.com/repos/$repo/contents/$requestsDir?ref=$([Uri]::EscapeDataString($branch))"
        $items = Invoke-GitHubJson -Method "GET" -Uri $listUri -Headers $headers

        foreach ($item in @($items | Where-Object { $_.name -like "*.json" } | Sort-Object name)) {
            $requestId = [IO.Path]::GetFileNameWithoutExtension([string]$item.name)

            if (Select-String -Path $handledPath -SimpleMatch -Quiet -Pattern $requestId) {
                continue
            }

            $requestText = Get-GitHubFile -Repo $repo -Path ([string]$item.path) -Ref $branch -Headers $headers
            $request = $requestText | ConvertFrom-Json

            if ([string]$request.target_agent -ne $agentId) {
                continue
            }

            $ref = "main"
            if ($null -ne $request.PSObject.Properties["ref"] -and $request.ref) {
                $ref = [string]$request.ref
            }

            $requestWork = Join-Path $workRoot $requestId
            $repoRoot = Download-RepoSnapshot -Repo $repo -Ref $ref -Destination $requestWork -Headers $headers
            $localRequest = Join-Path $requestWork "request.json"
            $requestText | Set-Content -Path $localRequest -Encoding UTF8
            $outputDir = Join-Path $requestWork "output"
            New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

            $runner = Join-Path $repoRoot "scripts\vps\Invoke-KatarinaRemoteTask.ps1"
            if (!(Test-Path $runner)) {
                throw "Remote task runner missing from requested ref: $ref"
            }

            $exitCode = 0
            try {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -RequestFile $localRequest -OutputDir $outputDir -AgentId $agentId -RepoRoot $repoRoot
                $exitCode = $LASTEXITCODE
            } catch {
                $exitCode = 1
                $_.Exception.Message | Set-Content -Path (Join-Path $outputDir "agent_error.txt") -Encoding UTF8
            }

            $allowedExtensions = @(".json",".txt",".log",".csv",".md")
            foreach ($file in Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue) {
                if ($allowedExtensions -notcontains $file.Extension.ToLowerInvariant()) {
                    continue
                }
                if ($file.Length -gt 1048576) {
                    continue
                }

                $text = Get-Content -Path $file.FullName -Raw
                $text = Redact-ResultText $text
                $remotePath = "$resultsDir/$agentId/$requestId/$($file.Name)"
                Put-GitHubTextFile -Repo $repo -Path $remotePath -Branch $branch -Message "vps-agent: $agentId $requestId $($file.Name)" -Text $text -Headers $headers
            }

            $receipt = [ordered]@{
                schema_version = 1
                agent_version = $AgentVersion
                agent_id = $agentId
                request_id = $requestId
                ref = $ref
                exit_code = $exitCode
                completed_utc = [DateTime]::UtcNow.ToString("o")
            }
            $receiptText = $receipt | ConvertTo-Json -Depth 6
            Put-GitHubTextFile -Repo $repo -Path "$resultsDir/$agentId/$requestId/agent_receipt.json" -Branch $branch -Message "vps-agent: complete $requestId" -Text $receiptText -Headers $headers

            Add-Content -Path $handledPath -Value $requestId
        }
    }
    catch {
        $errorRecord = [ordered]@{
            agent_id = $agentId
            agent_version = $AgentVersion
            time_utc = [DateTime]::UtcNow.ToString("o")
            error = (Redact-ResultText $_.Exception.Message)
        }
        Write-JsonFile (Join-Path $installRoot "last_error.json") $errorRecord
    }

    Start-Sleep -Seconds $pollSeconds
}
