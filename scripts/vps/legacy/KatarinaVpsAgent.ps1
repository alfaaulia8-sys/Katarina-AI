param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "C:\KatarinaVPSAgent\agent.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { }

$AgentVersion = "1.4.2"

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Write-LocalHeartbeat {
    param(
        [string]$Phase,
        [string]$RequestId = ""
    )

    try {
        $payload = [ordered]@{
            schema_version = 1
            agent_version = $AgentVersion
            agent_id = $(if($agentId){$agentId}else{""})
            phase = $Phase
            request_id = $RequestId
            process_id = $PID
            updated_utc = [DateTime]::UtcNow.ToString("o")
        }
        Write-JsonFile $heartbeatPath $payload
    } catch {
        # Heartbeat failure must never stop the agent.
    }
}

function Unprotect-Token {
    param([string]$Path)
    $encrypted = [IO.File]::ReadAllBytes($Path)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
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

function Test-GitHubTransientFailure {
    param($ErrorRecord)

    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response) { return $true }
        $status = [int]$response.StatusCode
        if ($status -eq 408 -or $status -eq 409 -or $status -eq 425 -or $status -eq 429) { return $true }
        if ($status -ge 500 -and $status -le 599) { return $true }
        return $false
    } catch {
        # DNS, TCP, TLS and connection-reset failures normally have no usable HTTP response.
        return $true
    }
}

function Invoke-GitHubJson {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        $Body = $null,
        [int]$MaxAttempts = 6
    )

    $json = $null
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($null -eq $Body) {
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
            }
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
        }
        catch {
            $transient = Test-GitHubTransientFailure $_
            if (-not $transient -or $attempt -ge $MaxAttempts) {
                throw
            }

            # Bounded exponential backoff: 1,2,4,8,16 seconds.
            $delay = [Math]::Min(16,[Math]::Pow(2,$attempt-1))
            Write-LocalHeartbeat -Phase ("GITHUB_RETRY_" + $attempt)
            Start-Sleep -Seconds ([int]$delay)
        }
    }
}

function Get-GitHubFile {
    param(
        [string]$Repo,
        [string]$Path,
        [string]$Ref,
        [hashtable]$Headers
    )

    $escaped = ($Path -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $uri = ("https://api.github.com/repos/{0}/contents/{1}?ref={2}" -f $Repo, $escaped, [Uri]::EscapeDataString($Ref))
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

function Publish-AgentHealth {
    param(
        [string]$State,
        [string]$ErrorText = ""
    )

    try {
        $now=[DateTime]::UtcNow
        $shouldPublish=$true
        if($healthStatePath -and (Test-Path -LiteralPath $healthStatePath -PathType Leaf)) {
            try {
                $previous=Get-Content -LiteralPath $healthStatePath -Raw | ConvertFrom-Json
                $last=[DateTime]::Parse(
                    [string]$previous.last_published_utc,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeUniversal
                ).ToUniversalTime()
                if(
                    [string]$previous.state -eq $State -and
                    [int]$previous.process_id -eq $PID -and
                    (($now-$last).TotalSeconds -lt 60)
                ) {
                    $shouldPublish=$false
                }
            } catch {}
        }
        if(-not $shouldPublish){ return }

        $payload = [ordered]@{
            schema_version = 1
            agent_version = $AgentVersion
            agent_id = $agentId
            lane = $lane
            process_id = $PID
            computer_name = $env:COMPUTERNAME
            state = $State
            error = (Redact-ResultText $ErrorText)
            updated_utc = $now.ToString("o")
        } | ConvertTo-Json -Depth 8

        Put-GitHubTextFile `
            -Repo $repo `
            -Path "ops/vps/health/$agentId/status.json" `
            -Branch $branch `
            -Message "vps-agent-health: $agentId $State" `
            -Text $payload `
            -Headers $headers

        if($healthStatePath) {
            Write-JsonFile $healthStatePath ([ordered]@{
                state=$State
                process_id=$PID
                last_published_utc=$now.ToString("o")
            })
        }
    } catch {
        # Telemetry must never stop the polling loop.
    }
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

    $uri = ("https://api.github.com/repos/{0}/zipball/{1}" -f $Repo, [Uri]::EscapeDataString($Ref))
    $downloaded = $false
    for($attempt=1; $attempt -le 6 -and -not $downloaded; $attempt++) {
        try {
            Invoke-WebRequest -Uri $uri -Headers $Headers -OutFile $zip -UseBasicParsing
            $downloaded = $true
        }
        catch {
            if(-not (Test-GitHubTransientFailure $_) -or $attempt -ge 6) { throw }
            Write-LocalHeartbeat -Phase ("SNAPSHOT_RETRY_" + $attempt)
            Start-Sleep -Seconds ([int][Math]::Min(16,[Math]::Pow(2,$attempt-1)))
        }
    }
    if(-not $downloaded -or !(Test-Path -LiteralPath $zip -PathType Leaf)) {
        throw "Repository snapshot download did not complete."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extracted = $false
    for($extractAttempt=1; $extractAttempt -le 5 -and -not $extracted; $extractAttempt++) {
        try {
            if(Test-Path -LiteralPath $extract -PathType Container) {
                Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Force -Path $extract | Out-Null
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
            $extracted = $true
        } catch {
            $message = [string]$_.Exception.Message
            $resourcePressure = (
                $message -match '(?i)not enough storage' -or
                $message -match '(?i)outofmemory' -or
                $message -match '(?i)paging file' -or
                $message -match '(?i)insufficient.*memory'
            )
            if(-not $resourcePressure -or $extractAttempt -ge 5) { throw }

            Write-LocalHeartbeat -Phase ("SNAPSHOT_EXTRACT_PRESSURE_" + $extractAttempt)
            try { [GC]::Collect() } catch {}
            try { [GC]::WaitForPendingFinalizers() } catch {}
            Start-Sleep -Seconds ([int](4 * $extractAttempt))
        }
    }
    if(-not $extracted) { throw "Repository snapshot extraction did not complete." }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

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

function Get-ShortWorkKey {
    param([string]$RequestId)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($RequestId)
        $hash = $sha.ComputeHash($bytes)
        $hex = ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
        return ("r_" + $hex.Substring(0,16))
    }
    finally {
        $sha.Dispose()
    }
}

function Test-HandledRequest {
    param(
        [string]$Path,
        [string]$RequestId
    )

    if (!(Test-Path $Path)) {
        return $false
    }

    foreach ($line in @(Get-Content -Path $Path -ErrorAction SilentlyContinue)) {
        if ([string]$line -eq $RequestId) {
            return $true
        }
    }
    return $false
}

function Validate-RequestEnvelope {
    param(
        $Request,
        [string]$RequestId,
        [string]$AgentId
    )

    $required = @(
        "schema_version",
        "request_id",
        "target_agent",
        "task",
        "created_utc",
        "expires_utc"
    )

    foreach ($field in $required) {
        if ($null -eq $Request.PSObject.Properties[$field]) {
            throw "Request missing required field: $field"
        }
    }

    if ([int]$Request.schema_version -ne 1) {
        throw "Unsupported request schema_version: $($Request.schema_version)"
    }

    if ($RequestId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "Unsafe request filename/id: $RequestId"
    }

    if ([string]$Request.request_id -ne $RequestId) {
        throw "Request id '$($Request.request_id)' does not match filename id '$RequestId'"
    }

    if ([string]$Request.target_agent -ne $AgentId) {
        return $null
    }

    $created = [DateTime]::Parse(
        [string]$Request.created_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()

    $expires = [DateTime]::Parse(
        [string]$Request.expires_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()

    if ($expires -le $created) {
        throw "Request expires_utc must be later than created_utc."
    }

    if ([DateTime]::UtcNow -gt $expires) {
        throw "Request expired at $($expires.ToString('o'))"
    }

    $task = ([string]$Request.task).ToUpperInvariant()
    $allowed = @(
        "HOST_INVENTORY",
        "REPO_STATIC_TESTS",
        "STAGE06_HOST_CHECK",
        "STAGE06_COMPILE_PROOF",
        "STAGE06_CLEARANCE",
        "STAGE07_PYTHON_TESTS",
        "COLLECT_MT5_LOGS"
    )

    if ($allowed -notcontains $task) {
        throw "Task is not allowlisted: $task"
    }

    $ref = "main"
    if ($null -ne $Request.PSObject.Properties["ref"] -and $Request.ref) {
        $ref = [string]$Request.ref
    }

    if (
        $ref.Length -gt 160 -or
        $ref -notmatch '^[A-Za-z0-9._/-]+$' -or
        $ref.StartsWith("/") -or
        $ref.EndsWith("/") -or
        $ref.Contains("..") -or
        $ref.Contains("//")
    ) {
        throw "Unsafe or unsupported Git ref: $ref"
    }

    $executionClass = "MUTATING"
    if($null -ne $Request.PSObject.Properties["execution_class"] -and $Request.execution_class) {
        $executionClass = ([string]$Request.execution_class).ToUpperInvariant()
    }
    if(@("MUTATING","READONLY","RECOVERY") -notcontains $executionClass) {
        throw "Unsupported execution_class: $executionClass"
    }

    return [pscustomobject]@{
        task = $task
        ref = $ref
        execution_class = $executionClass
    }
}

if (!(Test-Path $ConfigPath)) {
    throw "Agent config not found: $ConfigPath"
}

$config = Read-JsonFile $ConfigPath
$installRoot = Split-Path -Parent $ConfigPath

$lane = "primary"
if($null -ne $config.PSObject.Properties["lane"] -and $config.lane) {
    $lane = ([string]$config.lane).ToLowerInvariant()
}

$stateRoot = Join-Path $installRoot ("lanes\" + $lane)
if($null -ne $config.PSObject.Properties["state_root"] -and $config.state_root) {
    $stateRoot = [string]$config.state_root
}

$tokenPath = Join-Path $installRoot "token.bin"
if($null -ne $config.PSObject.Properties["token_path"] -and $config.token_path) {
    $tokenPath = [string]$config.token_path
}

$handledPath = Join-Path $stateRoot "handled.txt"
$workRoot = Join-Path $stateRoot "work"
$startupStatePath = Join-Path $stateRoot "startup_state.json"
$heartbeatPath = Join-Path $stateRoot "heartbeat.json"
$healthStatePath = Join-Path $stateRoot "health_publish_state.json"

$capabilities = @("MUTATING","READONLY","RECOVERY")
if($null -ne $config.PSObject.Properties["capabilities"] -and $config.capabilities) {
    $capabilities = @($config.capabilities | ForEach-Object { ([string]$_).ToUpperInvariant() })
}

if (!(Test-Path $tokenPath)) {
    throw "Encrypted GitHub token not found: $tokenPath"
}

New-Item -ItemType Directory -Force -Path $stateRoot,$workRoot | Out-Null
if (!(Test-Path $handledPath)) {
    New-Item -ItemType File -Force -Path $handledPath | Out-Null
}

# Enforce exactly one agent process per lane on this host.
$mutexLaneName = ($lane -replace '[^A-Za-z0-9_.-]','_')
$instanceMutex = New-Object System.Threading.Mutex($false,("Global\KatarinaVpsAgent_" + $mutexLaneName))
$instanceAcquired = $false
try { $instanceAcquired = $instanceMutex.WaitOne(0,$false) } catch { $instanceAcquired = $false }
if(-not $instanceAcquired) {
    Write-Host "Another Katarina agent instance already owns lane '$lane'. Exiting duplicate process."
    exit 0
}

Write-JsonFile $startupStatePath ([ordered]@{
    phase = "CONFIG_LOADED"
    agent_version = $AgentVersion
    time_utc = [DateTime]::UtcNow.ToString("o")
})

try {
    $token = Unprotect-Token $tokenPath

    Write-JsonFile $startupStatePath ([ordered]@{
        phase = "TOKEN_DECRYPTED"
        agent_version = $AgentVersion
        time_utc = [DateTime]::UtcNow.ToString("o")
    })

    $headers = New-GitHubHeaders $token
    $repo = [string]$config.repository
    $branch = [string]$config.branch
    $agentId = [string]$config.agent_id
    $pollSeconds = [int]$config.poll_seconds
    $requestsDir = "ops/vps/requests/legacy"
    if($null -ne $config.PSObject.Properties["requests_dir"] -and $config.requests_dir) {
        $requestsDir = [string]$config.requests_dir
    }
    $resultsDir = "ops/vps/results"
    if($null -ne $config.PSObject.Properties["results_dir"] -and $config.results_dir) {
        $resultsDir = [string]$config.results_dir
    }
    $compactResults = $false
    if($null -ne $config.PSObject.Properties["compact_results"]) {
        $compactResults = [bool]$config.compact_results
    }

    Write-Host "Katarina VPS Agent $AgentVersion"
    Write-Host "Agent: $agentId"
    Write-Host "Lane:  $lane"
    Write-Host "Repo:  $repo"
    Write-Host "Mode:  outbound HTTPS polling / allowlisted tasks only"

    $probeUri = "https://api.github.com/repos/$repo"
    [void](Invoke-GitHubJson -Method "GET" -Uri $probeUri -Headers $headers)

    Write-JsonFile $startupStatePath ([ordered]@{
        phase = "GITHUB_AUTH_OK"
        agent_version = $AgentVersion
        agent_id = $agentId
        time_utc = [DateTime]::UtcNow.ToString("o")
    })

    Write-LocalHeartbeat -Phase "ONLINE"
    Publish-AgentHealth -State "ONLINE"
}
catch {
    Write-JsonFile $startupStatePath ([ordered]@{
        phase = "STARTUP_FAILED"
        agent_version = $AgentVersion
        time_utc = [DateTime]::UtcNow.ToString("o")
        error = (Redact-ResultText $_.Exception.Message)
    })
    throw
}

while ($true) {
    try {
        Write-LocalHeartbeat -Phase "QUEUE_POLL"
        $listUri = ("https://api.github.com/repos/{0}/contents/{1}?ref={2}" -f $repo, $requestsDir, [Uri]::EscapeDataString($branch))
        Write-JsonFile $startupStatePath ([ordered]@{
            phase = "QUEUE_POLL"
            agent_version = $AgentVersion
            agent_id = $agentId
            queue_path = $requestsDir
            time_utc = [DateTime]::UtcNow.ToString("o")
        })
        $items = Invoke-GitHubJson -Method "GET" -Uri $listUri -Headers $headers

        foreach ($item in @($items | Where-Object { $_.name -like "*.json" } | Sort-Object name)) {
            $requestId = [IO.Path]::GetFileNameWithoutExtension([string]$item.name)

            if (Test-HandledRequest -Path $handledPath -RequestId $requestId) {
                continue
            }

            try {
                $requestText = Get-GitHubFile -Repo $repo -Path ([string]$item.path) -Ref $branch -Headers $headers
                $request = $requestText | ConvertFrom-Json

                $validated = Validate-RequestEnvelope -Request $request -RequestId $requestId -AgentId $agentId
                if ($null -eq $validated) {
                    continue
                }

                $executionClass = [string]$validated.execution_class
                if($capabilities -notcontains $executionClass) {
                    throw "Lane '$lane' does not allow execution_class '$executionClass'."
                }

                $mode = ""
                if($null -ne $request.PSObject.Properties["args"] -and $request.args -and
                   $null -ne $request.args.PSObject.Properties["mode"] -and $request.args.mode) {
                    $mode = ([string]$request.args.mode).ToUpperInvariant()
                }

                $readOnlyModes = @(
                    "WORKSPACE_DEPENDENCY_VERIFY",
                    "WORKSPACE_TEST",
                    "WORKSPACE_CONTROL_STATUS"
                )
                $recoveryModes = @(
                    "WORKSPACE_CONTROL_RESTART_PRIMARY",
                    "WORKSPACE_CONTROL_STATUS"
                )

                if($lane -like "worker*") {
                    if($executionClass -ne "READONLY") {
                        throw "Worker lanes accept READONLY requests only."
                    }
                    if([string]$validated.task -eq "STAGE07_PYTHON_TESTS" -and $readOnlyModes -notcontains $mode) {
                        throw "Worker lane rejected unsafe Stage-07 mode: $mode"
                    }
                }

                if($lane -eq "recovery") {
                    if($executionClass -eq "RECOVERY" -and $recoveryModes -notcontains $mode) {
                        throw "Recovery lane rejected unsupported recovery mode: $mode"
                    }
                    if($executionClass -eq "READONLY" -and [string]$validated.task -eq "STAGE07_PYTHON_TESTS" -and $readOnlyModes -notcontains $mode) {
                        throw "Recovery lane rejected unsafe read-only mode: $mode"
                    }
                }

                $ref = [string]$validated.ref
                Write-LocalHeartbeat -Phase "REQUEST_START" -RequestId $requestId
                $requestWork = Join-Path $workRoot (Get-ShortWorkKey -RequestId $requestId)

                # Snapshot download/extraction is itself memory intensive on the
                # 2 GB Windows Server 2012 R2 host. Serialize this phase across
                # all lanes before the heavier execution lock is considered.
                $snapshotMutex = New-Object System.Threading.Mutex($false,"Global\KatarinaSnapshotExtraction")
                $snapshotAcquired = $false
                $snapshotWaitMs = 0
                while (-not $snapshotAcquired -and $snapshotWaitMs -lt 180000) {
                    try { $snapshotAcquired = $snapshotMutex.WaitOne(1000,$false) } catch { $snapshotAcquired = $false }
                    if (-not $snapshotAcquired) {
                        Write-LocalHeartbeat -Phase "WAITING_SNAPSHOT_LOCK" -RequestId $requestId
                        $snapshotWaitMs += 1000
                    }
                }
                if (-not $snapshotAcquired) {
                    try { $snapshotMutex.Dispose() } catch {}
                    throw "Timed out waiting for the global Katarina snapshot-extraction lock."
                }
                try {
                    Write-LocalHeartbeat -Phase "SNAPSHOT_EXTRACT" -RequestId $requestId
                    $repoRoot = Download-RepoSnapshot -Repo $repo -Ref $ref -Destination $requestWork -Headers $headers
                } finally {
                    try { $snapshotMutex.ReleaseMutex() } catch {}
                    try { $snapshotMutex.Dispose() } catch {}
                }

                $localRequest = Join-Path $requestWork "request.json"
                $requestText | Set-Content -Path $localRequest -Encoding UTF8
                $outputDir = Join-Path $requestWork "output"
                New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

                $runner = Join-Path $repoRoot "scripts\vps\Invoke-KatarinaRemoteTask.ps1"
                if (!(Test-Path $runner)) {
                    throw "Remote task runner missing from requested ref: $ref"
                }

                $exitCode = 0
                $mutationMutex = $null
                $mutationAcquired = $false
                $heavyMutex = $null
                $heavyAcquired = $false
                try {
                    if($executionClass -eq "MUTATING") {
                        $mutationMutex = New-Object System.Threading.Mutex($false,"Global\KatarinaWorkspaceMutation")
                        $lockWaitMs = 0
                        while(-not $mutationAcquired -and $lockWaitMs -lt 180000) {
                            try { $mutationAcquired = $mutationMutex.WaitOne(1000,$false) } catch { $mutationAcquired = $false }
                            if(-not $mutationAcquired) {
                                Write-LocalHeartbeat -Phase "WAITING_MUTATION_LOCK" -RequestId $requestId
                                $lockWaitMs += 1000
                            }
                        }
                        if(-not $mutationAcquired) {
                            throw "Timed out waiting for the global Katarina workspace mutation lock."
                        }
                    }

                    # Keep the control plane parallel while serializing memory-heavy child
                    # execution on the 2 GB legacy VPS. Status/recovery control calls
                    # remain parallel; compile/runtime/test work shares one global slot.
                    $lightControlModes = @(
                        "WORKSPACE_CONTROL_STATUS",
                        "WORKSPACE_CONTROL_RESTART_PRIMARY",
                        "WORKSPACE_CONTROL_LITE_INSTALL_DIRECT",
                        "WORKSPACE_CONTROL_BALANCED_INSTALL_DIRECT",
                        "WORKSPACE_CONTROL_STABLE_UPDATE_DIRECT"
                    )
                    $requiresHeavyLock = $true
                    if ([string]$validated.task -eq "STAGE07_PYTHON_TESTS" -and
                        $lightControlModes -contains $mode) {
                        $requiresHeavyLock = $false
                    }

                    if ($requiresHeavyLock) {
                        $heavyMutex = New-Object System.Threading.Mutex($false,"Global\KatarinaHeavyExecution")
                        $heavyWaitMs = 0
                        while (-not $heavyAcquired -and $heavyWaitMs -lt 300000) {
                            try { $heavyAcquired = $heavyMutex.WaitOne(1000,$false) } catch { $heavyAcquired = $false }
                            if (-not $heavyAcquired) {
                                Write-LocalHeartbeat -Phase "WAITING_HEAVY_LOCK" -RequestId $requestId
                                $heavyWaitMs += 1000
                            }
                        }
                        if (-not $heavyAcquired) {
                            throw "Timed out waiting for the global Katarina heavy-execution lock."
                        }
                    }

                    # Never let one child task freeze the persistent command bus.
                    $runnerArgs = @(
                        "-NoProfile",
                        "-ExecutionPolicy","Bypass",
                        "-File",$runner,
                        "-RequestFile",$localRequest,
                        "-OutputDir",$outputDir,
                        "-AgentId",$agentId,
                        "-RepoRoot",$repoRoot
                    )
                    $child = Start-Process -FilePath "powershell.exe" -ArgumentList $runnerArgs -PassThru -WindowStyle Hidden

                    # Legacy 2 GB host: keep a strict default timeout, but allow
                    # bounded extra time for known heavy Stage-07 jobs that spend
                    # most of their time in MetaEditor/MT5 startup. Heartbeats are
                    # still emitted every five seconds so the watchdog can tell a
                    # slow healthy job from a frozen agent.
                    $timeoutMs = 180000
                    if([string]$validated.task -eq "STAGE07_PYTHON_TESTS") {
                        switch($mode) {
                            "WORKSPACE_MT5_COMPILE"       { $timeoutMs = 360000 }
                            "WORKSPACE_MT5_RUNTIME_SMOKE" { $timeoutMs = 360000 }
                            "WORKSPACE_TEST"              { $timeoutMs = 240000 }
                            "WORKSPACE_DEPENDENCY_VERIFY" { $timeoutMs = 240000 }
                        }
                    }
                    $elapsedMs = 0
                    while (-not $child.HasExited -and $elapsedMs -lt $timeoutMs) {
                        Write-LocalHeartbeat -Phase "TASK_RUNNING" -RequestId $requestId
                        Start-Sleep -Milliseconds 5000
                        $elapsedMs += 5000
                    }
                    if (-not $child.HasExited) {
                        try { $child.Kill() } catch {}
                        throw ("Remote task runner exceeded {0}-second hard timeout and was terminated." -f [int]($timeoutMs/1000))
                    }
                    $exitCode = [int]$child.ExitCode
                    Write-LocalHeartbeat -Phase "TASK_FINISHED" -RequestId $requestId
                } catch {
                    $exitCode = 1
                    (Redact-ResultText $_.Exception.Message) | Set-Content -Path (Join-Path $outputDir "agent_error.txt") -Encoding UTF8
                } finally {
                    if($heavyAcquired -and $null -ne $heavyMutex) {
                        try { $heavyMutex.ReleaseMutex() } catch {}
                    }
                    if($null -ne $heavyMutex) {
                        try { $heavyMutex.Dispose() } catch {}
                    }
                    if($mutationAcquired -and $null -ne $mutationMutex) {
                        try { $mutationMutex.ReleaseMutex() } catch {}
                    }
                    if($null -ne $mutationMutex) {
                        try { $mutationMutex.Dispose() } catch {}
                    }
                }

                $allowedExtensions = @(".json",".txt",".log",".csv",".md")
                $receipt = [ordered]@{
                    schema_version = 1
                    agent_version = $AgentVersion
                    agent_id = $agentId
                    lane = $lane
                    request_id = $requestId
                    task = [string]$validated.task
                    execution_class = $executionClass
                    ref = $ref
                    exit_code = $exitCode
                    completed_utc = [DateTime]::UtcNow.ToString("o")
                }

                if($compactResults) {
                    $bundleFiles=@()
                    $bundleBytes=0
                    foreach ($file in @(Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
                        if ($allowedExtensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
                        if ($file.Length -gt 1048576) { continue }

                        $fileText=Redact-ResultText (Get-Content -Path $file.FullName -Raw)
                        $bytes=[Text.Encoding]::UTF8.GetBytes($fileText)
                        $sha=[System.Security.Cryptography.SHA256]::Create()
                        try {
                            $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
                        } finally { $sha.Dispose() }

                        $includeContent=(($bundleBytes + $bytes.Length) -le 850000)
                        if($includeContent){$bundleBytes += $bytes.Length}
                        $bundleFiles += [ordered]@{
                            name=$file.Name
                            size_bytes=[int64]$bytes.Length
                            sha256=$hash
                            content_included=$includeContent
                            content=$(if($includeContent){$fileText}else{$null})
                        }
                    }

                    $bundle=[ordered]@{
                        schema_version=1
                        receipt=$receipt
                        files=$bundleFiles
                        bundle_content_bytes=$bundleBytes
                    } | ConvertTo-Json -Depth 12
                    Put-GitHubTextFile -Repo $repo -Path "$resultsDir/$agentId/$requestId/bundle.json" -Branch $branch -Message "vps-agent: bundle $agentId $requestId" -Text $bundle -Headers $headers
                } else {
                    foreach ($file in Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue) {
                        if ($allowedExtensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
                        if ($file.Length -gt 1048576) { continue }

                        $text = Get-Content -Path $file.FullName -Raw
                        $text = Redact-ResultText $text
                        $remotePath = "$resultsDir/$agentId/$requestId/$($file.Name)"
                        Put-GitHubTextFile -Repo $repo -Path $remotePath -Branch $branch -Message "vps-agent: $agentId $requestId $($file.Name)" -Text $text -Headers $headers
                    }

                    $receiptText = $receipt | ConvertTo-Json -Depth 6
                    Put-GitHubTextFile -Repo $repo -Path "$resultsDir/$agentId/$requestId/agent_receipt.json" -Branch $branch -Message "vps-agent: complete $requestId" -Text $receiptText -Headers $headers
                }

                Add-Content -Path $handledPath -Value $requestId
                Write-LocalHeartbeat -Phase "REQUEST_COMPLETE" -RequestId $requestId
            }
            catch {
                $errorRecord = [ordered]@{
                    agent_id = $agentId
                    agent_version = $AgentVersion
                    request_id = $requestId
                    time_utc = [DateTime]::UtcNow.ToString("o")
                    error = (Redact-ResultText $_.Exception.Message)
                }
                Write-JsonFile (Join-Path $stateRoot "last_error.json") $errorRecord

                $permanentRequestError = ([string]$errorRecord.error) -match '(?i)(expired|missing required|unsafe request|unsupported request|task is not allowlisted|execution_class|does not allow|rejected unsafe|rejected unsupported)'
                if($permanentRequestError -and -not (Test-HandledRequest -Path $handledPath -RequestId $requestId)) {
                    Add-Content -Path $handledPath -Value $requestId
                }

                Publish-AgentHealth -State "ERROR" -ErrorText ([string]$errorRecord.error)
                continue
            }
        }
    }
    catch {
        $errorRecord = [ordered]@{
            agent_id = $agentId
            agent_version = $AgentVersion
            request_id = $null
            time_utc = [DateTime]::UtcNow.ToString("o")
            error = (Redact-ResultText $_.Exception.Message)
            phase = "QUEUE_POLL"
            queue_path = $requestsDir
            request_uri = $listUri
        }
        Write-JsonFile (Join-Path $stateRoot "last_error.json") $errorRecord
        Publish-AgentHealth -State "ERROR" -ErrorText ([string]$errorRecord.error)
    }

    Write-LocalHeartbeat -Phase "SLEEP"
    Start-Sleep -Seconds $pollSeconds
}
