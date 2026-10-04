param(
    [Parameter(Mandatory=$true)]
    [string]$RequestFile,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [string]$AgentId = $env:KATARINA_AGENT_ID,

    [Parameter(Mandatory=$false)]
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Invoke-Captured {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$StdoutPath,
        [string]$StderrPath,
        [string]$WorkingDirectory = ""
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    if ($psi.PSObject.Properties["ArgumentList"]) {
        foreach ($arg in $ArgumentList) {
            [void]$psi.ArgumentList.Add($arg)
        }
    } else {
        $escaped = @()
        foreach ($arg in $ArgumentList) {
            $escaped += ('"' + ([string]$arg).Replace('"','\"') + '"')
        }
        $psi.Arguments = ($escaped -join " ")
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    $stdout | Set-Content -Path $StdoutPath -Encoding UTF8
    $stderr | Set-Content -Path $StderrPath -Encoding UTF8
    return $p.ExitCode
}

function Resolve-Executable {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (-not $candidate) { continue }
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Resolve-ExistingCandidates {
    param([string[]]$Candidates)

    $found = @()
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        try {
            if ($candidate.IndexOf("*") -ge 0 -or $candidate.IndexOf("?") -ge 0) {
                foreach ($item in @(Get-ChildItem -Path $candidate -ErrorAction SilentlyContinue)) {
                    if ($item -and -not $item.PSIsContainer) {
                        $found += $item.FullName
                    }
                }
            }
            elseif (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $found += (Resolve-Path -LiteralPath $candidate).Path
            }
        } catch {}
    }

    return @($found | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-RelevantRegistryHints {
    $hints = @()
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($root in $roots) {
        try {
            foreach ($item in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
                $name = [string]$item.DisplayName
                if ($name -match "(?i)(MetaTrader|MetaQuotes|MT5|Python|Git)") {
                    $hints += [ordered]@{
                        display_name = $name
                        display_version = [string]$item.DisplayVersion
                        install_location = [string]$item.InstallLocation
                        publisher = [string]$item.Publisher
                    }
                }
            }
        } catch {}
    }

    return @($hints | Select-Object -First 50)
}

function Get-Mt5Discovery {
    $instances = @()
    $origins = @()

    try {
        $origins = @(
            Get-ChildItem -Path "C:\Users\*\AppData\Roaming\MetaQuotes\Terminal\*\origin.txt" -ErrorAction SilentlyContinue
        )
    } catch {}

    foreach ($origin in $origins) {
        try {
            $originText = (Get-Content -LiteralPath $origin.FullName -Raw -ErrorAction Stop).Trim()
            $dataPath = Split-Path -Parent $origin.FullName
            $terminalPath = $null
            $metaEditorPath = $null

            if ($originText) {
                if (Test-Path -LiteralPath $originText -PathType Leaf) {
                    $terminalPath = (Resolve-Path -LiteralPath $originText).Path
                }
                elseif (Test-Path -LiteralPath $originText -PathType Container) {
                    $candidateTerminal = Join-Path $originText "terminal64.exe"
                    if (Test-Path -LiteralPath $candidateTerminal -PathType Leaf) {
                        $terminalPath = (Resolve-Path -LiteralPath $candidateTerminal).Path
                    }
                }

                $installDir = $originText
                if ($terminalPath) { $installDir = Split-Path -Parent $terminalPath }
                elseif ([IO.Path]::GetExtension($originText)) { $installDir = Split-Path -Parent $originText }

                if ($installDir) {
                    $candidateMeta = Join-Path $installDir "metaeditor64.exe"
                    if (Test-Path -LiteralPath $candidateMeta -PathType Leaf) {
                        $metaEditorPath = (Resolve-Path -LiteralPath $candidateMeta).Path
                    }
                }
            }

            $instances += [ordered]@{
                terminal_data_path = $dataPath
                origin = $originText
                terminal = $terminalPath
                metaeditor = $metaEditorPath
                mql5_exists = (Test-Path -LiteralPath (Join-Path $dataPath "MQL5"))
                tester_exists = (Test-Path -LiteralPath (Join-Path $dataPath "Tester"))
            }
        } catch {}
    }

    return @($instances)
}

function Get-ArgValue {
    param($ArgsObject, [string]$Name, $Default = $null)
    if ($null -eq $ArgsObject) { return $Default }
    $prop = $ArgsObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Redact-Text {
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

if (!(Test-Path $RequestFile)) {
    throw "Request file not found: $RequestFile"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$request = Get-Content -Path $RequestFile -Raw | ConvertFrom-Json

$required = @(
    "schema_version",
    "request_id",
    "target_agent",
    "task",
    "created_utc",
    "expires_utc"
)

foreach ($field in $required) {
    if ($null -eq $request.PSObject.Properties[$field]) {
        throw "Request missing required field: $field"
    }
}

if ([int]$request.schema_version -ne 1) {
    throw "Unsupported request schema_version: $($request.schema_version)"
}

if ([string]::IsNullOrWhiteSpace($AgentId)) {
    $AgentId = $env:COMPUTERNAME
}

if ([string]$request.target_agent -ne [string]$AgentId) {
    throw "Request target_agent '$($request.target_agent)' does not match '$AgentId'"
}

$expires = [DateTime]::Parse(
    [string]$request.expires_utc,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::AssumeUniversal
).ToUniversalTime()

if ([DateTime]::UtcNow -gt $expires) {
    throw "Request expired at $($expires.ToString('o'))"
}

$task = ([string]$request.task).ToUpperInvariant()
$allowed = @(
    "HOST_INVENTORY",
    "REPO_STATIC_TESTS",
    "STAGE06_HOST_CHECK",
    "STAGE06_COMPILE_PROOF",
    "STAGE06_RUNTIME_PROBE",
    "STAGE06_CLEARANCE",
    "STAGE07_PYTHON_TESTS",
    "COLLECT_MT5_LOGS"
)

if ($allowed -notcontains $task) {
    throw "Task is not allowlisted: $task"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$started = [DateTime]::UtcNow
$stdoutPath = Join-Path $OutputDir "stdout.txt"
$stderrPath = Join-Path $OutputDir "stderr.txt"
$resultCode = 0
$status = "PASS"
$details = [ordered]@{}

try {
    switch ($task) {
        "HOST_INVENTORY" {
            $os = Get-WmiObject Win32_OperatingSystem
            $cs = Get-WmiObject Win32_ComputerSystem
            $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
            $disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" |
                ForEach-Object {
                    [ordered]@{
                        device = $_.DeviceID
                        size_bytes = [int64]$_.Size
                        free_bytes = [int64]$_.FreeSpace
                    }
                }

            $pythonCandidates = @()
            $pathPython = Resolve-Executable @("python.exe","python")
            if ($pathPython) { $pythonCandidates += $pathPython }
            $pythonCandidates += Resolve-ExistingCandidates @(
                "C:\Python*\python.exe",
                "C:\Program Files\Python*\python.exe",
                "C:\Program Files (x86)\Python*\python.exe",
                "C:\Users\*\AppData\Local\Programs\Python\Python*\python.exe",
                "C:\PythonPortable\python.exe",
                "C:\PortablePython\python.exe",
                "C:\KatarinaVPSAgent\python\python.exe",
                "C:\KatarinaVPSAgent\runtime\python\python.exe"
            )
            $pythonCandidates = @($pythonCandidates | Where-Object { $_ } | Sort-Object -Unique)

            $gitCandidates = @()
            $pathGit = Resolve-Executable @("git.exe","git")
            if ($pathGit) { $gitCandidates += $pathGit }
            $gitCandidates += Resolve-ExistingCandidates @(
                "C:\Program Files\Git\cmd\git.exe",
                "C:\Program Files\Git\bin\git.exe",
                "C:\Program Files (x86)\Git\cmd\git.exe",
                "C:\Program Files (x86)\Git\bin\git.exe",
                "C:\Users\*\AppData\Local\Programs\Git\cmd\git.exe",
                "C:\PortableGit\cmd\git.exe"
            )
            $gitCandidates = @($gitCandidates | Where-Object { $_ } | Sort-Object -Unique)

            $terminalCandidates = @()
            $pathTerminal = Resolve-Executable @(
                (Get-ArgValue $request.args "terminal_path" ""),
                "terminal64.exe"
            )
            if ($pathTerminal) { $terminalCandidates += $pathTerminal }
            $terminalCandidates += Resolve-ExistingCandidates @(
                "C:\Program Files\*\terminal64.exe",
                "C:\Program Files (x86)\*\terminal64.exe",
                "C:\MetaTrader 5\terminal64.exe",
                "C:\MT5\terminal64.exe",
                "C:\Trading\*\terminal64.exe"
            )

            $metaEditorCandidates = @()
            $pathMetaEditor = Resolve-Executable @(
                (Get-ArgValue $request.args "metaeditor_path" ""),
                "metaeditor64.exe"
            )
            if ($pathMetaEditor) { $metaEditorCandidates += $pathMetaEditor }
            $metaEditorCandidates += Resolve-ExistingCandidates @(
                "C:\Program Files\*\metaeditor64.exe",
                "C:\Program Files (x86)\*\metaeditor64.exe",
                "C:\MetaTrader 5\metaeditor64.exe",
                "C:\MT5\metaeditor64.exe",
                "C:\Trading\*\metaeditor64.exe"
            )

            $mt5Instances = Get-Mt5Discovery
            foreach ($instance in $mt5Instances) {
                if ($instance.terminal) { $terminalCandidates += [string]$instance.terminal }
                if ($instance.metaeditor) { $metaEditorCandidates += [string]$instance.metaeditor }
            }

            $terminalCandidates = @($terminalCandidates | Where-Object { $_ } | Sort-Object -Unique)
            $metaEditorCandidates = @($metaEditorCandidates | Where-Object { $_ } | Sort-Object -Unique)

            $commonDataPaths = @()
            try {
                foreach ($common in @(Get-ChildItem -Path "C:\Users\*\AppData\Roaming\MetaQuotes\Terminal\Common" -Directory -ErrorAction SilentlyContinue)) {
                    $commonDataPaths += $common.FullName
                }
            } catch {}
            $commonDataPaths = @($commonDataPaths | Sort-Object -Unique)

            $registryHints = Get-RelevantRegistryHints

            $inventory = [ordered]@{
                schema_version = 2
                discovery_mode = "DEEP_TARGETED"
                agent_id = $AgentId
                computer_name = $env:COMPUTERNAME
                os_caption = $os.Caption
                os_version = $os.Version
                os_architecture = $os.OSArchitecture
                powershell_version = $PSVersionTable.PSVersion.ToString()
                dotnet_clr = [Environment]::Version.ToString()
                cpu = $cpu.Name
                logical_processors = [int]$cs.NumberOfLogicalProcessors
                memory_bytes = [int64]$cs.TotalPhysicalMemory
                disks = $disks
                python = $(if ($pythonCandidates.Count -gt 0) { $pythonCandidates[0] } else { $null })
                python_candidates = $pythonCandidates
                git = $(if ($gitCandidates.Count -gt 0) { $gitCandidates[0] } else { $null })
                git_candidates = $gitCandidates
                metaeditor = $(if ($metaEditorCandidates.Count -gt 0) { $metaEditorCandidates[0] } else { $null })
                metaeditor_candidates = $metaEditorCandidates
                terminal = $(if ($terminalCandidates.Count -gt 0) { $terminalCandidates[0] } else { $null })
                terminal_candidates = $terminalCandidates
                mt5_instances = $mt5Instances
                terminal_common_data_paths = $commonDataPaths
                registry_hints = $registryHints
                generated_utc = [DateTime]::UtcNow.ToString("o")
            }

            Write-JsonFile (Join-Path $OutputDir "host_inventory.json") $inventory
            "HOST_INVENTORY DEEP DISCOVERY PASS" | Set-Content $stdoutPath -Encoding UTF8
            "" | Set-Content $stderrPath -Encoding UTF8
            $details["inventory"] = "host_inventory.json"
            $details["mt5_instances"] = @($mt5Instances).Count
            $details["terminal_candidates"] = @($terminalCandidates).Count
            $details["metaeditor_candidates"] = @($metaEditorCandidates).Count
            $details["python_candidates"] = @($pythonCandidates).Count
            $details["git_candidates"] = @($gitCandidates).Count
        }

        "REPO_STATIC_TESTS" {
            $python = Resolve-Executable @("python.exe","python")
            if (-not $python) { throw "Python executable not found." }

            $resultCode = Invoke-Captured -FilePath $python -ArgumentList @("-m","unittest","discover","-s","tests","-p","test*.py","-v") -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            if ($resultCode -ne 0) { throw "Repository static/unit tests failed." }
        }

        "STAGE07_PYTHON_TESTS" {
            $mode = ([string](Get-ArgValue $request.args "mode" "PYTHON_TESTS")).ToUpperInvariant()

            # Windows Server 2012 R2 rescue path: perform control-plane collapse
            # in this already-running task host. Do NOT spawn a second PowerShell
            # process because the 2 GB VPS can fail that nested host with OOM.
            if ($mode -eq "WORKSPACE_CONTROL_LITE_INSTALL_DIRECT") {
                $installRoot = "C:\\KatarinaVPSAgent"
                $primaryConfig = Join-Path $installRoot "agent.json"
                if (!(Test-Path -LiteralPath $primaryConfig -PathType Leaf)) {
                    throw "Primary agent config missing."
                }

                $cfg = Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                $lite = [ordered]@{
                    schema_version = 2
                    agent_id = [string]$cfg.agent_id
                    repository = [string]$cfg.repository
                    branch = [string]$cfg.branch
                    poll_seconds = 5
                    lane = "primary"
                    state_root = (Join-Path $installRoot "lanes\\primary")
                    token_path = (Join-Path $installRoot "token.bin")
                    requests_dir = "ops/vps/requests/primary"
                    results_dir = "ops/vps/results"
                    compact_results = $true
                    capabilities = @("MUTATING","READONLY","RECOVERY")
                    resource_profile = "LEGACY_LOW_MEMORY_SEQUENTIAL"
                    installed_utc = [DateTime]::UtcNow.ToString("o")
                }
                Write-JsonFile $primaryConfig $lite

                # Disable guard/supervisor first so they cannot resurrect workers.
                $disabled = @(
                    "KatarinaControlSupervisorGuard",
                    "KatarinaControlSupervisor",
                    "KatarinaControlRecovery",
                    "KatarinaControlWorker01",
                    "KatarinaControlWorker02"
                )
                foreach ($taskName in $disabled) {
                    try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
                    try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
                }

                foreach ($taskName in @("KatarinaVPSAgent","KatarinaVPSAgentWatchdog")) {
                    try { & schtasks.exe /Change /TN $taskName /ENABLE | Out-Null } catch {}
                }

                $proof = [ordered]@{
                    schema_version = 1
                    proof_type = "KATARINA_CONTROL_LITE_DIRECT"
                    resource_profile = "LEGACY_LOW_MEMORY_SEQUENTIAL"
                    persistent_lanes = @("primary")
                    watchdog = "KatarinaVPSAgentWatchdog"
                    disabled_tasks = $disabled
                    heavy_job_concurrency = 1
                    nested_powershell = $false
                    primary_restart_deferred = $true
                    installed_utc = [DateTime]::UtcNow.ToString("o")
                    result = "PASS"
                }
                Write-JsonFile (Join-Path $OutputDir "control_lite_direct.json") $proof
                "KATARINA LOW MEMORY DIRECT INSTALL PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = $mode
                $details["resource_profile"] = "LEGACY_LOW_MEMORY_SEQUENTIAL"
                $details["disabled_task_count"] = $disabled.Count
                $details["result"] = "PASS"
                break
            }

            if ($mode -eq "WORKSPACE_CONTROL_BALANCED_INSTALL_DIRECT") {
                $installRoot = "C:\\KatarinaVPSAgent"
                $primaryConfig = Join-Path $installRoot "agent.json"
                $tokenPath = Join-Path $installRoot "token.bin"
                $agentSource = Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgent.ps1"
                $watchdogSource = Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgentWatchdog.ps1"
                $agentPath = Join-Path $installRoot "KatarinaVpsAgent.ps1"
                $watchdogPath = Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1"
                $watchdogConfigPath = Join-Path $installRoot "watchdog_lanes.json"

                foreach ($requiredPath in @($primaryConfig,$tokenPath,$agentSource,$watchdogSource)) {
                    if (!(Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                        throw "Balanced control prerequisite missing: $requiredPath"
                    }
                }

                Copy-Item -LiteralPath $agentSource -Destination $agentPath -Force
                Copy-Item -LiteralPath $watchdogSource -Destination $watchdogPath -Force

                function Get-ControlMemory {
                    $m = [ordered]@{ total_visible_mb = 0; free_physical_mb = 0 }
                    try {
                        $os = Get-WmiObject Win32_OperatingSystem
                        $m.total_visible_mb = [int]([double]$os.TotalVisibleMemorySize / 1024)
                        $m.free_physical_mb = [int]([double]$os.FreePhysicalMemory / 1024)
                    } catch {}
                    return $m
                }

                function Wait-LaneHeartbeat([string]$LaneName,[string]$TaskName,[string]$ConfigPath,[string]$HeartbeatPath,[int]$WaitSeconds=60) {
                    $record = [ordered]@{
                        lane = $LaneName
                        task = $TaskName
                        start_exit_code = $null
                        heartbeat_fresh = $false
                        phase = ""
                        agent_version = ""
                        process_id = $null
                        startup_phase = ""
                        startup_error = ""
                        last_error = ""
                        error = ""
                    }

                    # Explicitly terminate a stale/ghost lane host. Task Scheduler
                    # /End alone did not prove sufficient on Server 2012 R2.
                    try {
                        foreach($proc in @(Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
                            if($proc.CommandLine -and
                               $proc.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                               $proc.CommandLine.IndexOf($ConfigPath,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                try { [void]$proc.Terminate() } catch {}
                            }
                        }
                    } catch {}

                    $laneRoot = Split-Path -Parent $HeartbeatPath
                    $startupPath = Join-Path $laneRoot "startup_state.json"
                    $lastErrorPath = Join-Path $laneRoot "last_error.json"
                    try { Remove-Item -LiteralPath $HeartbeatPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Item -LiteralPath $startupPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Item -LiteralPath $lastErrorPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { & schtasks.exe /End /TN $TaskName | Out-Null } catch {}
                    Start-Sleep -Seconds 2
                    & schtasks.exe /Run /TN $TaskName | Out-Null
                    $record.start_exit_code = [int]$LASTEXITCODE
                    if ($LASTEXITCODE -ne 0) {
                        $record.error = "TASK_START_FAILED"
                        return ([pscustomobject]$record)
                    }

                    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
                    while ([DateTime]::UtcNow -lt $deadline) {
                        if (Test-Path -LiteralPath $HeartbeatPath -PathType Leaf) {
                            try {
                                $hb = Get-Content -LiteralPath $HeartbeatPath -Raw | ConvertFrom-Json
                                $updated = [DateTime]::Parse(
                                    [string]$hb.updated_utc,
                                    [Globalization.CultureInfo]::InvariantCulture,
                                    [Globalization.DateTimeStyles]::AssumeUniversal
                                ).ToUniversalTime()
                                if (([DateTime]::UtcNow - $updated).TotalSeconds -lt 15) {
                                    $record.heartbeat_fresh = $true
                                    $record.phase = [string]$hb.phase
                                    $record.agent_version = [string]$hb.agent_version
                                    try { $record.process_id = [int]$hb.process_id } catch {}
                                    break
                                }
                            } catch {
                                $record.error = "HEARTBEAT_PARSE_ERROR"
                            }
                        }
                        Start-Sleep -Seconds 1
                    }
                    if (-not $record.heartbeat_fresh) {
                        if (Test-Path -LiteralPath $startupPath -PathType Leaf) {
                            try {
                                $startup = Get-Content -LiteralPath $startupPath -Raw | ConvertFrom-Json
                                $record.startup_phase = [string]$startup.phase
                                if($null -ne $startup.PSObject.Properties["error"]) {
                                    $record.startup_error = [string]$startup.error
                                }
                            } catch {}
                        }
                        if (Test-Path -LiteralPath $lastErrorPath -PathType Leaf) {
                            try {
                                $lastErr = Get-Content -LiteralPath $lastErrorPath -Raw | ConvertFrom-Json
                                $record.last_error = [string]$lastErr.error
                            } catch {}
                        }
                        if ([string]::IsNullOrWhiteSpace([string]$record.error)) {
                            $record.error = "HEARTBEAT_TIMEOUT"
                        }
                    }
                    return ([pscustomobject]$record)
                }

                $cfg = Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                $repoName = [string]$cfg.repository
                $branchName = [string]$cfg.branch
                $primaryAgentId = [string]$cfg.agent_id
                if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = "alfaaulia-katarina/Katarina-AI" }
                if ([string]::IsNullOrWhiteSpace($branchName)) { $branchName = "main" }
                if ([string]::IsNullOrWhiteSpace($primaryAgentId)) { $primaryAgentId = "katarina-vps-2012r2-01" }

                $memoryBefore = Get-ControlMemory
                $recoveryMinMb = 320
                $workerMinAfterRecoveryMb = 640

                $common = [ordered]@{
                    schema_version = 2
                    repository = $repoName
                    branch = $branchName
                    results_dir = "ops/vps/results"
                    token_path = $tokenPath
                    compact_results = $true
                    resource_profile = "LEGACY_LOW_MEMORY_BALANCED"
                    installed_utc = [DateTime]::UtcNow.ToString("o")
                }

                $primary = [ordered]@{}
                foreach ($k in $common.Keys) { $primary[$k] = $common[$k] }
                $primary.agent_id = $primaryAgentId
                $primary.lane = "primary"
                $primary.state_root = Join-Path $installRoot "lanes\\primary"
                $primary.capabilities = @("MUTATING","READONLY","RECOVERY")
                $primary.poll_seconds = 5
                $primary.requests_dir = "ops/vps/requests/primary"
                Write-JsonFile $primaryConfig $primary

                $recoveryConfig = Join-Path $installRoot "agent-recovery.json"
                $worker01Config = Join-Path $installRoot "agent-worker01.json"

                $recovery = [ordered]@{}
                foreach ($k in $common.Keys) { $recovery[$k] = $common[$k] }
                $recovery.agent_id = $primaryAgentId + "-recovery"
                $recovery.lane = "recovery"
                $recovery.state_root = Join-Path $installRoot "lanes\\recovery"
                $recovery.capabilities = @("RECOVERY","READONLY")
                $recovery.poll_seconds = 7
                $recovery.requests_dir = "ops/vps/requests/recovery"
                Write-JsonFile $recoveryConfig $recovery

                $worker01 = [ordered]@{}
                foreach ($k in $common.Keys) { $worker01[$k] = $common[$k] }
                $worker01.agent_id = $primaryAgentId + "-worker01"
                $worker01.lane = "worker01"
                $worker01.state_root = Join-Path $installRoot "lanes\\worker01"
                $worker01.capabilities = @("READONLY")
                $worker01.poll_seconds = 10
                $worker01.requests_dir = "ops/vps/requests/worker01"
                Write-JsonFile $worker01Config $worker01

                $laneDefs = @(
                    [pscustomobject]@{ lane="recovery"; task="KatarinaControlRecovery"; config=$recoveryConfig },
                    [pscustomobject]@{ lane="worker01"; task="KatarinaControlWorker01"; config=$worker01Config }
                )
                foreach ($td in $laneDefs) {
                    $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $agentPath + '" -ConfigPath "' + $td.config + '"'
                    & schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN $td.task /TR $cmd | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Failed to register balanced lane task: $($td.task)" }
                    try { & schtasks.exe /Change /TN $td.task /DISABLE | Out-Null } catch {}
                    try { & schtasks.exe /End /TN $td.task | Out-Null } catch {}
                }

                foreach ($taskName in @("KatarinaControlSupervisorGuard","KatarinaControlSupervisor","KatarinaControlWorker02")) {
                    try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
                    try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
                }
                foreach ($taskName in @("KatarinaVPSAgent","KatarinaVPSAgentWatchdog")) {
                    try { & schtasks.exe /Change /TN $taskName /ENABLE | Out-Null } catch {}
                }

                $watchdogCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $watchdogPath + '" -InstallRoot "' + $installRoot + '"'
                & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN "KatarinaVPSAgentWatchdog" /TR $watchdogCmd | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Failed to register balanced watchdog task." }

                $laneChecks = @()
                $recoveryEnabled = $false
                $worker01Enabled = $false

                # Recovery is the first and mandatory secondary lane. Start it alone
                # so a low-memory host never pays the startup cost of two agents at once.
                if ([int]$memoryBefore.free_physical_mb -ge $recoveryMinMb) {
                    try { & schtasks.exe /Change /TN "KatarinaControlRecovery" /ENABLE | Out-Null } catch {}
                    $recoveryCheck = Wait-LaneHeartbeat "recovery" "KatarinaControlRecovery" $recoveryConfig (Join-Path $installRoot "lanes\\recovery\\heartbeat.json") 60
                    $laneChecks += $recoveryCheck
                    $recoveryEnabled = [bool]$recoveryCheck.heartbeat_fresh
                    if (-not $recoveryEnabled) {
                        try { & schtasks.exe /End /TN "KatarinaControlRecovery" | Out-Null } catch {}
                        try { & schtasks.exe /Change /TN "KatarinaControlRecovery" /DISABLE | Out-Null } catch {}
                    }
                } else {
                    $laneChecks += [ordered]@{
                        lane="recovery"; task="KatarinaControlRecovery"; start_exit_code=$null;
                        heartbeat_fresh=$false; phase=""; agent_version=""; process_id=$null;
                        error=("SKIPPED_LOW_MEMORY_" + [string]$memoryBefore.free_physical_mb + "MB")
                    }
                }

                Start-Sleep -Seconds 2
                $memoryAfterRecovery = Get-ControlMemory

                # Worker01 is optional throughput. It only starts after recovery is
                # healthy and enough RAM still remains. Worker02 stays cold reserve.
                if ($recoveryEnabled -and [int]$memoryAfterRecovery.free_physical_mb -ge $workerMinAfterRecoveryMb) {
                    try { & schtasks.exe /Change /TN "KatarinaControlWorker01" /ENABLE | Out-Null } catch {}
                    $workerCheck = Wait-LaneHeartbeat "worker01" "KatarinaControlWorker01" $worker01Config (Join-Path $installRoot "lanes\\worker01\\heartbeat.json") 45
                    $laneChecks += $workerCheck
                    $worker01Enabled = [bool]$workerCheck.heartbeat_fresh
                    if (-not $worker01Enabled) {
                        try { & schtasks.exe /End /TN "KatarinaControlWorker01" | Out-Null } catch {}
                        try { & schtasks.exe /Change /TN "KatarinaControlWorker01" /DISABLE | Out-Null } catch {}
                    }
                } else {
                    $skipReason = $(if(-not $recoveryEnabled){"SKIPPED_RECOVERY_NOT_READY"}else{"SKIPPED_LOW_MEMORY_"+[string]$memoryAfterRecovery.free_physical_mb+"MB"})
                    $laneChecks += [ordered]@{
                        lane="worker01"; task="KatarinaControlWorker01"; start_exit_code=$null;
                        heartbeat_fresh=$false; phase=""; agent_version=""; process_id=$null;
                        error=$skipReason
                    }
                }

                $activeLanes = @("primary")
                if ($recoveryEnabled) { $activeLanes += "recovery" }
                if ($worker01Enabled) { $activeLanes += "worker01" }

                # The balanced profile is opportunistic on this 2 GB host.
                # If the recovery lane cannot remain healthy, atomically fall
                # back to the proven primary-only profile instead of leaving
                # agent.json mislabeled BALANCED and poisoning health checks.
                $requestedProfile = "LEGACY_LOW_MEMORY_BALANCED"
                $effectiveProfile = $(if($recoveryEnabled){"LEGACY_LOW_MEMORY_BALANCED"}else{"LEGACY_LOW_MEMORY_SEQUENTIAL"})
                $fallbackReason = $(if($recoveryEnabled){""}else{"RECOVERY_HEARTBEAT_UNAVAILABLE"})

                if(-not $recoveryEnabled) {
                    $primary.resource_profile = $effectiveProfile
                    Write-JsonFile $primaryConfig $primary

                    foreach($taskName in @("KatarinaControlRecovery","KatarinaControlWorker01","KatarinaControlWorker02","KatarinaControlSupervisor","KatarinaControlSupervisorGuard")) {
                        try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
                        try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
                    }
                    $activeLanes = @("primary")
                    $worker01Enabled = $false
                }

                $watchdogLanes = @(
                    [ordered]@{
                        lane="primary"; task="KatarinaVPSAgent"; config=$primaryConfig;
                        heartbeat=(Join-Path $installRoot "lanes\\primary\\heartbeat.json");
                        fallback=(Join-Path $installRoot "heartbeat.json");
                        stale_seconds=90; busy_stale_seconds=420
                    }
                )
                if ($recoveryEnabled) {
                    $watchdogLanes += [ordered]@{
                        lane="recovery"; task="KatarinaControlRecovery"; config=$recoveryConfig;
                        heartbeat=(Join-Path $installRoot "lanes\\recovery\\heartbeat.json");
                        fallback=""; stale_seconds=90; busy_stale_seconds=420
                    }
                }
                if ($worker01Enabled) {
                    $watchdogLanes += [ordered]@{
                        lane="worker01"; task="KatarinaControlWorker01"; config=$worker01Config;
                        heartbeat=(Join-Path $installRoot "lanes\\worker01\\heartbeat.json");
                        fallback=""; stale_seconds=120; busy_stale_seconds=420
                    }
                }
                Write-JsonFile $watchdogConfigPath ([ordered]@{
                    schema_version=1
                    resource_profile=$effectiveProfile
                    requested_profile=$requestedProfile
                    fallback_reason=$fallbackReason
                    lanes=$watchdogLanes
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                })

                try { & schtasks.exe /Run /TN "KatarinaVPSAgentWatchdog" | Out-Null } catch {}
                $memoryFinal = Get-ControlMemory

                $overall = "PASS"
                $proof = [ordered]@{
                    schema_version=3
                    proof_type="KATARINA_CONTROL_BALANCED_DIRECT"
                    requested_profile=$requestedProfile
                    effective_profile=$effectiveProfile
                    resource_profile=$effectiveProfile
                    fallback_applied=(-not $recoveryEnabled)
                    fallback_reason=$fallbackReason
                    memory=[ordered]@{
                        before=$memoryBefore
                        after_recovery=$memoryAfterRecovery
                        final=$memoryFinal
                        recovery_min_free_mb=$recoveryMinMb
                        worker01_min_free_mb_after_recovery=$workerMinAfterRecoveryMb
                    }
                    persistent_lanes=$activeLanes
                    reserve_lane="worker02"
                    supervisor_persistent=$false
                    watchdog_mode="MULTI_LANE_INDEPENDENT"
                    watchdog_interval_minutes=1
                    parallel_request_capacity=$activeLanes.Count
                    mutation_concurrency=1
                    heavy_execution_concurrency=1
                    queue_isolation=$true
                    recovery_lane_enabled=$recoveryEnabled
                    worker01_enabled=$worker01Enabled
                    lane_checks=$laneChecks
                    primary_restart_deferred=$true
                    installed_utc=[DateTime]::UtcNow.ToString("o")
                    result=$overall
                }
                Write-JsonFile (Join-Path $OutputDir "control_balanced_direct.json") $proof

                "KATARINA ADAPTIVE LOW MEMORY CONTROL PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = $mode
                $details["requested_profile"] = $requestedProfile
                $details["resource_profile"] = $effectiveProfile
                $details["fallback_applied"] = (-not $recoveryEnabled)
                $details["fallback_reason"] = $fallbackReason
                $details["active_lanes"] = $activeLanes.Count
                $details["recovery_lane_enabled"] = $recoveryEnabled
                $details["worker01_enabled"] = $worker01Enabled
                $details["result"] = "PASS"
                break
            }

            if ($mode -eq "WORKSPACE_CONTROL_GUARDIAN_INSTALL_DIRECT") {
                $installRoot="C:\\KatarinaVPSAgent"
                $primaryConfig=Join-Path $installRoot "agent.json"
                $tokenPath=Join-Path $installRoot "token.bin"
                $agentSource=Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgent.ps1"
                $watchdogSource=Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgentWatchdog.ps1"
                $guardianSource=Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaControlGuardian.ps1"
                $agentPath=Join-Path $installRoot "KatarinaVpsAgent.ps1"
                $watchdogPath=Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1"
                $guardianPath=Join-Path $installRoot "KatarinaControlGuardian.ps1"
                $watchdogConfigPath=Join-Path $installRoot "watchdog_lanes.json"

                foreach($required in @($primaryConfig,$tokenPath,$agentSource,$watchdogSource,$guardianSource)) {
                    if(!(Test-Path -LiteralPath $required -PathType Leaf)) {
                        throw "Guardian control prerequisite missing: $required"
                    }
                }

                $memoryBefore=$null
                try {
                    $os=Get-WmiObject Win32_OperatingSystem
                    $memoryBefore=[ordered]@{
                        total_visible_mb=[int]([double]$os.TotalVisibleMemorySize/1024)
                        free_physical_mb=[int]([double]$os.FreePhysicalMemory/1024)
                    }
                } catch {}

                Copy-Item -LiteralPath $agentSource -Destination $agentPath -Force
                Copy-Item -LiteralPath $watchdogSource -Destination $watchdogPath -Force
                Copy-Item -LiteralPath $guardianSource -Destination $guardianPath -Force

                $cfg=Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                $guarded=[ordered]@{
                    schema_version=2
                    agent_id=[string]$cfg.agent_id
                    repository=[string]$cfg.repository
                    branch=[string]$cfg.branch
                    poll_seconds=8
                    lane="primary"
                    github_health_mode="TRANSITIONS_ONLY"
                    github_health_repeat_seconds=21600
                    state_root=(Join-Path $installRoot "lanes\\primary")
                    token_path=$tokenPath
                    requests_dir="ops/vps/requests/primary"
                    results_dir="ops/vps/results"
                    compact_results=$true
                    capabilities=@("MUTATING","READONLY","RECOVERY")
                    resource_profile="LEGACY_LOW_MEMORY_GUARDED"
                    installed_utc=[DateTime]::UtcNow.ToString("o")
                }
                if([string]::IsNullOrWhiteSpace([string]$guarded.agent_id)){$guarded.agent_id="katarina-vps-2012r2-01"}
                if([string]::IsNullOrWhiteSpace([string]$guarded.repository)){$guarded.repository="alfaaulia-katarina/Katarina-AI"}
                if([string]::IsNullOrWhiteSpace([string]$guarded.branch)){$guarded.branch="main"}
                Write-JsonFile $primaryConfig $guarded

                # Full secondary command agents are too expensive for the 2 GB
                # host. The local guardian is the independent recovery lane.
                foreach($taskName in @(
                    "KatarinaControlRecovery",
                    "KatarinaControlWorker01",
                    "KatarinaControlWorker02",
                    "KatarinaControlSupervisor",
                    "KatarinaControlSupervisorGuard"
                )) {
                    try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
                    try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
                }

                $guardianCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$guardianPath+'"'
                & schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN "KatarinaControlGuardian" /TR $guardianCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to register KatarinaControlGuardian."}
                try { & schtasks.exe /Change /TN "KatarinaControlGuardian" /ENABLE | Out-Null } catch {}

                $watchdogCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$watchdogPath+'" -InstallRoot "'+$installRoot+'"'
                & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN "KatarinaVPSAgentWatchdog" /TR $watchdogCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to register fallback watchdog."}
                try { & schtasks.exe /Change /TN "KatarinaVPSAgentWatchdog" /ENABLE | Out-Null } catch {}
                try { & schtasks.exe /Change /TN "KatarinaVPSAgent" /ENABLE | Out-Null } catch {}

                Write-JsonFile $watchdogConfigPath ([ordered]@{
                    schema_version=1
                    resource_profile="LEGACY_LOW_MEMORY_GUARDED"
                    lanes=@(
                        [ordered]@{
                            lane="primary"
                            task="KatarinaVPSAgent"
                            config=$primaryConfig
                            heartbeat=(Join-Path $installRoot "lanes\\primary\\heartbeat.json")
                            fallback=(Join-Path $installRoot "heartbeat.json")
                            stale_seconds=90
                            busy_stale_seconds=420
                        }
                    )
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                })

                # Clear any old guardian instance, then start the lightweight lane.
                try {
                    foreach($proc in @(Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
                        if($proc.CommandLine -and $proc.CommandLine.IndexOf("KatarinaControlGuardian.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            try { [void]$proc.Terminate() } catch {}
                        }
                    }
                } catch {}
                try { & schtasks.exe /End /TN "KatarinaControlGuardian" | Out-Null } catch {}
                Start-Sleep -Seconds 1
                & schtasks.exe /Run /TN "KatarinaControlGuardian" | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to start KatarinaControlGuardian."}

                $guardianHeartbeat=Join-Path $installRoot "guardian\\heartbeat.json"
                $guardianReady=$false
                $guardianState=$null
                $deadline=[DateTime]::UtcNow.AddSeconds(20)
                while([DateTime]::UtcNow -lt $deadline) {
                    if(Test-Path -LiteralPath $guardianHeartbeat -PathType Leaf) {
                        try {
                            $candidate=Get-Content -LiteralPath $guardianHeartbeat -Raw | ConvertFrom-Json
                            $updated=[DateTime]::Parse(
                                [string]$candidate.updated_utc,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::AssumeUniversal
                            ).ToUniversalTime()
                            if(([DateTime]::UtcNow-$updated).TotalSeconds -lt 15) {
                                $guardianReady=$true
                                $guardianState=$candidate
                                break
                            }
                        } catch {}
                    }
                    Start-Sleep -Seconds 1
                }
                if(-not $guardianReady){throw "Guardian lane did not publish a fresh heartbeat."}

                try { & schtasks.exe /Run /TN "KatarinaVPSAgentWatchdog" | Out-Null } catch {}

                # Load the newly installed agent after this request has uploaded its
                # receipt. Guardian + fallback watchdog both protect the transition.
                $restartTask="KatarinaGuardedDeferredRestart"
                $restartScript=Join-Path $installRoot "KatarinaGuardedDeferredRestart.ps1"
                @'
$ErrorActionPreference="Continue"
try { & schtasks.exe /End /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Run /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Delete /F /TN "KatarinaGuardedDeferredRestart" | Out-Null } catch {}
'@ | Set-Content -LiteralPath $restartScript -Encoding ASCII
                $runAt=(Get-Date).AddMinutes(1).ToString("HH:mm")
                $restartCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$restartScript+'"'
                & schtasks.exe /Create /F /SC ONCE /ST $runAt /RU SYSTEM /RL HIGHEST /TN $restartTask /TR $restartCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to schedule guarded primary reload."}

                $memoryAfter=$null
                try {
                    $os=Get-WmiObject Win32_OperatingSystem
                    $memoryAfter=[ordered]@{
                        total_visible_mb=[int]([double]$os.TotalVisibleMemorySize/1024)
                        free_physical_mb=[int]([double]$os.FreePhysicalMemory/1024)
                    }
                } catch {}

                Write-JsonFile (Join-Path $OutputDir "control_guardian_install.json") ([ordered]@{
                    schema_version=1
                    proof_type="KATARINA_LOW_MEMORY_GUARDIAN_INSTALL"
                    resource_profile="LEGACY_LOW_MEMORY_GUARDED"
                    primary_command_lane="KatarinaVPSAgent"
                    recovery_lane="KatarinaControlGuardian"
                    fallback_recovery="KatarinaVPSAgentWatchdog"
                    guardian_version=[string]$guardianState.guardian_version
                    guardian_phase=[string]$guardianState.phase
                    guardian_process_id=$guardianState.process_id
                    guardian_check_seconds=10
                    primary_idle_stale_seconds=90
                    primary_busy_stale_seconds=420
                    missing_heartbeat_grace_seconds=60
                    fallback_watchdog_minutes=1
                    heavy_execution_concurrency=1
                    snapshot_extraction_concurrency=1
                    full_secondary_agents_disabled=$true
                    memory_before=$memoryBefore
                    memory_after=$memoryAfter
                    deferred_primary_reload=$restartTask
                    deferred_primary_reload_time_local=$runAt
                    installed_utc=[DateTime]::UtcNow.ToString("o")
                    result="PASS"
                })
                "KATARINA GUARDED LOW MEMORY CONTROL PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["resource_profile"]="LEGACY_LOW_MEMORY_GUARDED"
                $details["guardian_ready"]=$guardianReady
                $details["result"]="PASS"
                break
            }

            if ($mode -eq "WORKSPACE_CONTROL_GUARDIAN_DIAG_DIRECT") {
                $installRoot="C:\\KatarinaVPSAgent"
                $guardianPath=Join-Path $installRoot "KatarinaControlGuardian.ps1"
                $guardianHeartbeat=Join-Path $installRoot "guardian\\heartbeat.json"
                $guardianState=Join-Path $installRoot "guardian\\state.json"
                $guardianLog=Join-Path $installRoot "guardian\\guardian.log"
                $primaryConfig=Join-Path $installRoot "agent.json"

                $parseOk=$false
                $parseError=""
                if(Test-Path -LiteralPath $guardianPath -PathType Leaf) {
                    try {
                        $text=Get-Content -LiteralPath $guardianPath -Raw
                        [void][scriptblock]::Create($text)
                        $parseOk=$true
                    } catch {
                        $parseError=$_.Exception.Message
                    }
                } else {
                    $parseError="GUARDIAN_SCRIPT_MISSING"
                }

                $guardianProcesses=@()
                try {
                    foreach($proc in @(Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
                        if($proc.CommandLine -and $proc.CommandLine.IndexOf("KatarinaControlGuardian.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $guardianProcesses += [ordered]@{
                                process_id=[int]$proc.ProcessId
                                command_line=[string]$proc.CommandLine
                            }
                        }
                    }
                } catch {}

                $taskQuery=""
                try { $taskQuery=((& schtasks.exe /Query /TN "KatarinaControlGuardian" /FO LIST /V 2>&1) | Out-String) } catch { $taskQuery=$_.Exception.Message }
                $hb=$null
                if(Test-Path -LiteralPath $guardianHeartbeat -PathType Leaf) {
                    try { $hb=Get-Content -LiteralPath $guardianHeartbeat -Raw | ConvertFrom-Json } catch {}
                }
                $state=$null
                if(Test-Path -LiteralPath $guardianState -PathType Leaf) {
                    try { $state=Get-Content -LiteralPath $guardianState -Raw | ConvertFrom-Json } catch {}
                }
                $logTail=@()
                if(Test-Path -LiteralPath $guardianLog -PathType Leaf) {
                    try { $logTail=@(Get-Content -LiteralPath $guardianLog -Tail 30) } catch {}
                }
                $profile=""
                if(Test-Path -LiteralPath $primaryConfig -PathType Leaf) {
                    try {
                        $cfg=Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                        $profile=[string]$cfg.resource_profile
                    } catch {}
                }
                $memory=$null
                try {
                    $os=Get-WmiObject Win32_OperatingSystem
                    $memory=[ordered]@{
                        total_visible_mb=[int]([double]$os.TotalVisibleMemorySize/1024)
                        free_physical_mb=[int]([double]$os.FreePhysicalMemory/1024)
                    }
                } catch {}

                $proof=[ordered]@{
                    schema_version=1
                    proof_type="KATARINA_GUARDIAN_DIAGNOSTIC"
                    resource_profile=$profile
                    guardian_script_exists=(Test-Path -LiteralPath $guardianPath -PathType Leaf)
                    guardian_script_sha256=$(if(Test-Path -LiteralPath $guardianPath -PathType Leaf){(Get-FileHash -LiteralPath $guardianPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null})
                    parse_ok=$parseOk
                    parse_error=$parseError
                    process_count=@($guardianProcesses).Count
                    processes=$guardianProcesses
                    task_query=$taskQuery
                    heartbeat=$hb
                    state=$state
                    log_tail=$logTail
                    memory=$memory
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                    result=$(if($parseOk){"PASS_DIAGNOSTIC"}else{"FAIL_PARSE"})
                }
                Write-JsonFile (Join-Path $OutputDir "guardian_diagnostic.json") $proof
                "KATARINA GUARDIAN DIAGNOSTIC COMPLETE" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["parse_ok"]=$parseOk
                $details["process_count"]=@($guardianProcesses).Count
                $details["result"]=$proof.result
                if(-not $parseOk){throw "Guardian script parse failed; see guardian_diagnostic.json."}
                break
            }

            if ($mode -eq "WORKSPACE_CONTROL_GUARDIAN_SELFTEST_ARM_DIRECT") {
                $installRoot="C:\\KatarinaVPSAgent"
                $primaryConfig=Join-Path $installRoot "agent.json"
                $guardianHeartbeat=Join-Path $installRoot "guardian\\heartbeat.json"
                $guardianState=Join-Path $installRoot "guardian\\state.json"
                $selfTestResult=Join-Path $installRoot "guardian\\selftest_result.json"
                $selfTestScript=Join-Path $installRoot "guardian\\KatarinaGuardianSelfTest.ps1"

                if(!(Test-Path -LiteralPath $primaryConfig -PathType Leaf)){throw "Primary config missing for guardian self-test."}
                $cfg=Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                if(([string]$cfg.resource_profile).ToUpperInvariant() -ne "LEGACY_LOW_MEMORY_GUARDED") {
                    throw "Guardian self-test requires LEGACY_LOW_MEMORY_GUARDED profile."
                }
                if(!(Test-Path -LiteralPath $guardianHeartbeat -PathType Leaf)){throw "Guardian heartbeat missing."}
                $gh=Get-Content -LiteralPath $guardianHeartbeat -Raw | ConvertFrom-Json
                $ghUpdated=[DateTime]::Parse(
                    [string]$gh.updated_utc,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeUniversal
                ).ToUniversalTime()
                if(([DateTime]::UtcNow-$ghUpdated).TotalSeconds -gt 30){throw "Guardian heartbeat is stale."}
                if(([string]$gh.guardian_version) -ne "1.1.0"){throw "Guardian self-test requires guardian 1.1.0."}

                try { Remove-Item -LiteralPath $selfTestResult -Force -ErrorAction SilentlyContinue } catch {}
                @'
$ErrorActionPreference="Continue"
$installRoot="C:\KatarinaVPSAgent"
$primaryConfig=Join-Path $installRoot "agent.json"
$primaryHeartbeat=Join-Path $installRoot "lanes\primary\heartbeat.json"
$guardianState=Join-Path $installRoot "guardian\state.json"
$resultPath=Join-Path $installRoot "guardian\selftest_result.json"

function Write-Result($Value) {
    ConvertTo-Json -InputObject $Value -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
function Get-Primary {
    try {
        return @(
            Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($primaryConfig,[StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        ) | Select-Object -First 1
    } catch { return $null }
}
function Read-Utc($Value) {
    try {
        return [DateTime]::Parse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
    } catch { return $null }
}

Start-Sleep -Seconds 30
$triggerUtc=[DateTime]::UtcNow
$old=Get-Primary
$oldPid=$null
if($null -ne $old){try{$oldPid=[int]$old.ProcessId}catch{}}

Write-Result ([ordered]@{
    schema_version=1
    proof_type="KATARINA_GUARDIAN_FAILOVER_SELFTEST"
    phase="TRIGGERING"
    trigger_utc=$triggerUtc.ToString("o")
    old_primary_pid=$oldPid
    result="RUNNING"
})

if($null -eq $old) {
    Write-Result ([ordered]@{
        schema_version=1; proof_type="KATARINA_GUARDIAN_FAILOVER_SELFTEST";
        trigger_utc=$triggerUtc.ToString("o"); old_primary_pid=$null;
        result="FAIL"; reason="PRIMARY_MISSING_BEFORE_TEST"
    })
    exit 1
}

try { [void]$old.Terminate() } catch {}
try { & schtasks.exe /End /TN "KatarinaVPSAgent" | Out-Null } catch {}

$newPid=$null
$guardianRestartUtc=$null
$guardianReason=""
$guardianStarted=$false
$deadline=[DateTime]::UtcNow.AddSeconds(90)
while([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Seconds 2
    $candidate=Get-Primary
    if($null -ne $candidate) {
        try {
            $candidatePid=[int]$candidate.ProcessId
            if($candidatePid -ne $oldPid) {$newPid=$candidatePid}
        } catch {}
    }

    if(Test-Path -LiteralPath $guardianState -PathType Leaf) {
        try {
            $gs=Get-Content -LiteralPath $guardianState -Raw | ConvertFrom-Json
            $gsUtc=Read-Utc $gs.last_restart_utc
            if($null -ne $gsUtc -and $gsUtc -ge $triggerUtc.AddSeconds(-2)) {
                $guardianRestartUtc=$gsUtc
                $guardianReason=[string]$gs.reason
                $guardianStarted=[bool]$gs.started
            }
        } catch {}
    }

    $heartbeatFresh=$false
    if($null -ne $newPid -and (Test-Path -LiteralPath $primaryHeartbeat -PathType Leaf)) {
        try {
            $hb=Get-Content -LiteralPath $primaryHeartbeat -Raw | ConvertFrom-Json
            $hbUtc=Read-Utc $hb.updated_utc
            $hbPid=[int]$hb.process_id
            if($null -ne $hbUtc -and ([DateTime]::UtcNow-$hbUtc).TotalSeconds -lt 20 -and $hbPid -eq $newPid) {
                $heartbeatFresh=$true
            }
        } catch {}
    }

    if($null -ne $newPid -and $heartbeatFresh -and $null -ne $guardianRestartUtc -and $guardianStarted) {
        $seconds=[math]::Round(([DateTime]::UtcNow-$triggerUtc).TotalSeconds,1)
        Write-Result ([ordered]@{
            schema_version=1
            proof_type="KATARINA_GUARDIAN_FAILOVER_SELFTEST"
            trigger_utc=$triggerUtc.ToString("o")
            old_primary_pid=$oldPid
            new_primary_pid=$newPid
            guardian_last_restart_utc=$guardianRestartUtc.ToString("o")
            guardian_reason=$guardianReason
            guardian_started=$guardianStarted
            recovery_seconds=$seconds
            result="PASS"
        })
        try { & schtasks.exe /Delete /F /TN "KatarinaGuardianSelfTest" | Out-Null } catch {}
        exit 0
    }
}

Write-Result ([ordered]@{
    schema_version=1
    proof_type="KATARINA_GUARDIAN_FAILOVER_SELFTEST"
    trigger_utc=$triggerUtc.ToString("o")
    old_primary_pid=$oldPid
    new_primary_pid=$newPid
    guardian_last_restart_utc=$(if($null -ne $guardianRestartUtc){$guardianRestartUtc.ToString("o")}else{$null})
    guardian_reason=$guardianReason
    guardian_started=$guardianStarted
    result="FAIL"
    reason="RECOVERY_NOT_PROVEN_WITHIN_90_SECONDS"
})
try { & schtasks.exe /Delete /F /TN "KatarinaGuardianSelfTest" | Out-Null } catch {}
exit 1
'@ | Set-Content -LiteralPath $selfTestScript -Encoding ASCII

                $dummyTime=(Get-Date).AddHours(1).ToString("HH:mm")
                $testCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$selfTestScript+'"'
                & schtasks.exe /Create /F /SC ONCE /ST $dummyTime /RU SYSTEM /RL HIGHEST /TN "KatarinaGuardianSelfTest" /TR $testCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to register guardian self-test task."}
                & schtasks.exe /Run /TN "KatarinaGuardianSelfTest" | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to start guardian self-test task."}

                Write-JsonFile (Join-Path $OutputDir "guardian_selftest_arm.json") ([ordered]@{
                    schema_version=1
                    proof_type="KATARINA_GUARDIAN_SELFTEST_ARM"
                    guardian_version=[string]$gh.guardian_version
                    guardian_process_id=$gh.process_id
                    trigger_delay_seconds=30
                    recovery_deadline_seconds=90
                    local_result_path=$selfTestResult
                    armed_utc=[DateTime]::UtcNow.ToString("o")
                    result="PASS_ARMED"
                })
                "KATARINA GUARDIAN SELFTEST ARMED" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["result"]="PASS_ARMED"
                break
            }

            # Stable rescue/update mode is intentionally independent from
            # the adaptive balanced installer above. It is the fail-safe path
            # for the 2 GB Server 2012 R2 host when secondary lanes cannot stay healthy.
            if ($mode -eq "WORKSPACE_CONTROL_STABLE_UPDATE_DIRECT") {
                $installRoot = "C:\\KatarinaVPSAgent"
                $primaryConfig = Join-Path $installRoot "agent.json"
                $agentSource = Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgent.ps1"
                $watchdogSource = Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgentWatchdog.ps1"
                $agentPath = Join-Path $installRoot "KatarinaVpsAgent.ps1"
                $watchdogPath = Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1"
                $tokenPath = Join-Path $installRoot "token.bin"

                foreach($required in @($primaryConfig,$agentSource,$watchdogSource,$tokenPath)) {
                    if(!(Test-Path -LiteralPath $required -PathType Leaf)) {
                        throw "Stable control update prerequisite missing: $required"
                    }
                }

                Copy-Item -LiteralPath $agentSource -Destination $agentPath -Force
                Copy-Item -LiteralPath $watchdogSource -Destination $watchdogPath -Force

                $cfg = Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
                $stable = [ordered]@{
                    schema_version=2
                    agent_id=[string]$cfg.agent_id
                    repository=[string]$cfg.repository
                    branch=[string]$cfg.branch
                    poll_seconds=8
                    lane="primary"
                    github_health_mode="TRANSITIONS_ONLY"
                    github_health_repeat_seconds=21600
                    state_root=(Join-Path $installRoot "lanes\\primary")
                    token_path=$tokenPath
                    requests_dir="ops/vps/requests/primary"
                    results_dir="ops/vps/results"
                    compact_results=$true
                    capabilities=@("MUTATING","READONLY","RECOVERY")
                    resource_profile="LEGACY_LOW_MEMORY_SEQUENTIAL"
                    github_write_profile="SPARSE_TRANSITION_ONLY"
                    installed_utc=[DateTime]::UtcNow.ToString("o")
                }
                Write-JsonFile $primaryConfig $stable

                foreach($taskName in @("KatarinaControlGuardian","KatarinaControlSupervisorGuard","KatarinaControlSupervisor","KatarinaControlRecovery","KatarinaControlWorker01","KatarinaControlWorker02")) {
                    try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
                    try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
                }
                try {
                    foreach($proc in @(Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
                        if($proc.CommandLine -and $proc.CommandLine.IndexOf("KatarinaControlGuardian.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            try { [void]$proc.Terminate() } catch {}
                        }
                    }
                } catch {}
                foreach($taskName in @("KatarinaVPSAgent","KatarinaVPSAgentWatchdog")) {
                    try { & schtasks.exe /Change /TN $taskName /ENABLE | Out-Null } catch {}
                }

                $watchdogCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$watchdogPath+'" -InstallRoot "'+$installRoot+'"'
                & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN "KatarinaVPSAgentWatchdog" /TR $watchdogCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to register stable watchdog task."}

                $restartTask="KatarinaPrimaryDeferredRestart"
                $restartScript=Join-Path $installRoot "KatarinaPrimaryDeferredRestart.ps1"
                @'
$ErrorActionPreference="Continue"
try { & schtasks.exe /End /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Run /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Delete /F /TN "KatarinaPrimaryDeferredRestart" | Out-Null } catch {}
'@ | Set-Content -LiteralPath $restartScript -Encoding ASCII
                $runAt=(Get-Date).AddMinutes(1).ToString("HH:mm")
                $restartCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$restartScript+'"'
                & schtasks.exe /Create /F /SC ONCE /ST $runAt /RU SYSTEM /RL HIGHEST /TN $restartTask /TR $restartCmd | Out-Null
                if($LASTEXITCODE -ne 0){throw "Failed to schedule deferred primary restart."}

                Write-JsonFile (Join-Path $OutputDir "stable_control_update.json") ([ordered]@{
                    schema_version=1
                    proof_type="KATARINA_STABLE_CONTROL_UPDATE_DIRECT"
                    resource_profile="LEGACY_LOW_MEMORY_SEQUENTIAL"
                    installed_agent_sha256=(Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    installed_watchdog_sha256=(Get-FileHash -LiteralPath $watchdogPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    secondary_lanes_disabled=$true
                    guardian_disabled=$true
                    heavy_execution_concurrency=1
                    deferred_restart_task=$restartTask
                    deferred_restart_time_local=$runAt
                    result="PASS"
                })
                "KATARINA STABLE CONTROL UPDATE PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["resource_profile"]="LEGACY_LOW_MEMORY_SEQUENTIAL"
                $details["deferred_restart"]=$true
                $details["result"]="PASS"
                break
            }

            if ($mode.StartsWith("WORKSPACE_")) {
                $workspaceRunner = Join-Path $RepoRoot "scripts\vps\Invoke-KatarinaWorkspaceTask.ps1"
                if (!(Test-Path -LiteralPath $workspaceRunner -PathType Leaf)) { throw "Katarina workspace runner is missing." }
                $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$workspaceRunner,"-RequestFile",$RequestFile,"-OutputDir",$OutputDir,"-RepoRoot",$RepoRoot)
                $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList $args -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
                if ($resultCode -ne 0) { throw "Katarina workspace task failed." }

                $workspaceStatusPath = Join-Path $OutputDir "workspace_status.json"
                if (!(Test-Path -LiteralPath $workspaceStatusPath -PathType Leaf)) {
                    throw "Workspace child task produced no status evidence."
                }
                $workspaceStatus = Get-Content -LiteralPath $workspaceStatusPath -Raw | ConvertFrom-Json
                if ([string]$workspaceStatus.result -ne "PASS") {
                    throw "Workspace child task did not report PASS."
                }

                $details["mode"] = $mode
                $details["workspace_root"] = "C:\KatarinaDev"
                $details["workspace_files"] = [int]$workspaceStatus.file_count
                break
            }
            if ($mode -eq "WORKSPACE_TEST") {
                $workspaceRoot = "C:\KatarinaDev\workspace"
                if (!(Test-Path $workspaceRoot)) { throw "Katarina workspace is not initialized." }

                $python = Resolve-Executable @(
                    "C:\KatarinaDev\runtime\python\python.exe",
                    "python.exe",
                    "python"
                )
                if (-not $python) {
                    $details["mode"] = "WORKSPACE_TEST"
                    $details["python_available"] = $false
                    throw "Workspace Python runtime is not available yet."
                }

                $testOut = Join-Path $OutputDir "workspace_test_stdout.txt"
                $testErr = Join-Path $OutputDir "workspace_test_stderr.txt"
                $resultCode = Invoke-Captured -FilePath $python -ArgumentList @(
                    "-m","unittest",
                    "tests.unit.transport.test_stage07_communication",
                    "tests.unit.transport.test_stage07_stage06_contract",
                    "-v"
                ) -StdoutPath $testOut -StderrPath $testErr -WorkingDirectory $workspaceRoot
                if ($resultCode -ne 0) { throw "Workspace tests failed." }

                $details["mode"] = "WORKSPACE_TEST"
                $details["python_available"] = $true
                $details["result"] = "PASS"
                "KATARINA WORKSPACE TEST PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                break
            }

            if ($mode -eq "WORKSPACE_APPLY") {
                $workspaceRoot = "C:\KatarinaDev\workspace"
                $evidenceRoot = "C:\KatarinaDev\evidence"
                if (!(Test-Path $workspaceRoot)) { throw "Katarina workspace is not initialized." }
                if ($null -eq $request.args.PSObject.Properties["changeset"]) { throw "changeset is required." }

                $changesetJson = $request.args.changeset | ConvertTo-Json -Depth 16
                if ([Text.Encoding]::UTF8.GetByteCount($changesetJson) -gt 262144) {
                    throw "Changeset exceeds 256 KiB command-bus limit."
                }
                $changesetFile = Join-Path $OutputDir "workspace_changeset.json"
                $changesetJson | Set-Content $changesetFile -Encoding UTF8

                $apply = Join-Path $RepoRoot "scripts\vps\Apply-KatarinaWorkspaceChangeset.ps1"
                if (!(Test-Path $apply)) { throw "Workspace changeset engine missing." }

                $applyOut = Join-Path $OutputDir "workspace_apply_stdout.txt"
                $applyErr = Join-Path $OutputDir "workspace_apply_stderr.txt"
                $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList @(
                    "-NoProfile","-ExecutionPolicy","Bypass","-File",$apply,
                    "-ChangesetPath",$changesetFile,
                    "-WorkspaceRoot",$workspaceRoot,
                    "-EvidenceRoot",$evidenceRoot
                ) -StdoutPath $applyOut -StderrPath $applyErr -WorkingDirectory $RepoRoot
                if ($resultCode -ne 0) { throw "Workspace changeset application failed." }

                $details["mode"] = "WORKSPACE_APPLY"
                $details["changeset_id"] = [string]$request.args.changeset.changeset_id
                $details["operation_count"] = @($request.args.changeset.operations).Count
                "KATARINA WORKSPACE APPLY PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                break
            }

            if ($mode -eq "WORKSPACE_INIT" -or $mode -eq "WORKSPACE_STATUS") {
                $workspaceRoot = "C:\KatarinaDev"
                $workspace = Join-Path $workspaceRoot "workspace"
                $metadataDir = Join-Path $workspaceRoot "metadata"
                $evidenceDir = Join-Path $workspaceRoot "evidence"
                $artifactDir = Join-Path $workspaceRoot "artifacts"
                $snapshotDir = Join-Path $workspaceRoot "snapshots"
                $logDir = Join-Path $workspaceRoot "logs"

                foreach ($dir in @($workspaceRoot,$metadataDir,$evidenceDir,$artifactDir,$snapshotDir,$logDir)) {
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                }

                if ($mode -eq "WORKSPACE_INIT") {
                    if (Test-Path $workspace) {
                        $backup = Join-Path $snapshotDir ("pre_init_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
                        Move-Item $workspace $backup -Force
                    }
                    New-Item -ItemType Directory -Force -Path $workspace | Out-Null

                    $excludeTop = @(".git","ops")
                    foreach ($item in Get-ChildItem -Path $RepoRoot -Force) {
                        if ($excludeTop -contains $item.Name) { continue }
                        Copy-Item $item.FullName (Join-Path $workspace $item.Name) -Recurse -Force
                    }

                    $baseline = [ordered]@{
                        schema_version = 1
                        workspace_version = "1.0"
                        source_ref = [string]$request.ref
                        initialized_utc = [DateTime]::UtcNow.ToString("o")
                        computer_name = $env:COMPUTERNAME
                        root = $workspaceRoot
                        development_mode = "VPS_FIRST"
                        github_role = "COMMAND_BUS_AND_CANONICAL_RELEASE"
                    }
                    Write-JsonFile (Join-Path $metadataDir "workspace.json") $baseline
                }

                if (!(Test-Path $workspace)) { throw "Katarina development workspace is not initialized." }

                $files = @(Get-ChildItem -Path $workspace -File -Recurse -ErrorAction Stop)
                $manifest = @()
                foreach ($file in $files) {
                    $relative = $file.FullName.Substring($workspace.Length).TrimStart("\")
                    $manifest += [ordered]@{
                        path = ($relative -replace "\\","/")
                        size = [int64]$file.Length
                        sha256 = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    }
                }
                $manifest = @($manifest | Sort-Object path)
                $manifestPayload = [ordered]@{
                    schema_version = 1
                    generated_utc = [DateTime]::UtcNow.ToString("o")
                    file_count = $manifest.Count
                    files = $manifest
                }
                Write-JsonFile (Join-Path $metadataDir "manifest.json") $manifestPayload

                $statusOut = [ordered]@{
                    schema_version = 1
                    mode = $mode
                    root = $workspaceRoot
                    workspace = $workspace
                    file_count = $manifest.Count
                    metadata_exists = (Test-Path (Join-Path $metadataDir "workspace.json"))
                    result = "PASS"
                }
                Write-JsonFile (Join-Path $OutputDir "workspace_status.json") $statusOut
                "KATARINA WORKSPACE $mode PASS files=$($manifest.Count)" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = $mode
                $details["workspace_root"] = $workspaceRoot
                $details["file_count"] = $manifest.Count
                break
            }

            if ($mode -eq "MT5_SEQUENCE_RUNTIME") {
                $terminalPath = Get-ArgValue $request.args "terminal_path" ""
                $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
                if (-not $terminalPath -or -not $terminalDataPath) { throw "terminal_path and terminal_data_path are required." }

                $scriptPath = Join-Path $terminalDataPath "MQL5\Scripts\KatarinaStage07WireSequenceTest.ex5"
                if (!(Test-Path $scriptPath)) { throw "Stage-07 wire sequence EX5 missing; compile first." }

                $running = @(Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExecutablePath -and [string]::Equals($_.ExecutablePath,$terminalPath,[StringComparison]::OrdinalIgnoreCase) })
                if ($running.Count -gt 0) { throw "Target MT5 terminal is already running; refusing headless runtime probe." }

                # The legacy agent runs as LocalSystem. Never assume the interactive
                # Administrator profile for FILE_COMMON; bind evidence to the same
                # Windows identity that launches terminal64.exe.
                $commonFiles = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
                New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null

                # Force the runtime probe into portable mode so terminal data does not
                # silently resolve to a different per-user roaming terminal instance.
                $terminalHome = Split-Path -Parent $terminalPath
                $portableScriptDir = Join-Path $terminalHome "MQL5\Scripts"
                $portableIncludeDir = Join-Path $terminalHome "MQL5\Include\Katarina"
                New-Item -ItemType Directory -Force -Path $portableScriptDir,$portableIncludeDir | Out-Null
                Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $portableScriptDir "KatarinaStage07WireSequenceTest.ex5") -Force
                $sourceInclude = Join-Path $terminalDataPath "MQL5\Include\Katarina"
                if (Test-Path -LiteralPath $sourceInclude -PathType Container) {
                    Copy-Item -Path (Join-Path $sourceInclude "*") -Destination $portableIncludeDir -Recurse -Force
                }
                $marker = Join-Path $commonFiles "Katarina_Stage07_wire_sequence_phase.txt"
                $evidence = Join-Path $commonFiles "Katarina_Stage07_wire_sequence_result.txt"
                Remove-Item $marker,$evidence -Force -ErrorAction SilentlyContinue

                function Invoke-Stage07SequencePhase {
                    param([int]$Phase)
                    $configPath = Join-Path $OutputDir ("stage07_sequence_phase" + $Phase + ".ini")
                    @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0
[StartUp]
Script=KatarinaStage07WireSequenceTest
Symbol=
Period=H1
ShutdownTerminal=1
"@ | Set-Content $configPath -Encoding ASCII
                    $p = Start-Process -FilePath $terminalPath -ArgumentList @("/portable", "/config:`"$configPath`"") -PassThru
                    if (-not $p.WaitForExit(90000)) {
                        try { $p.Kill() } catch {}
                        throw "Stage-07 wire sequence phase $Phase timed out."
                    }
                    Start-Sleep -Milliseconds 500
                }

                Invoke-Stage07SequencePhase -Phase 1
                if (!(Test-Path $evidence) -or !(Test-Path $marker)) { throw "Stage-07 sequence phase-1 evidence missing." }
                $phase1 = Get-Content $evidence -Raw
                if ($phase1 -notmatch "result=PHASE1_PASS") { throw "Stage-07 sequence phase 1 did not pass." }

                Remove-Item $evidence -Force
                Invoke-Stage07SequencePhase -Phase 2
                if (!(Test-Path $evidence)) { throw "Stage-07 sequence phase-2 evidence missing." }
                $phase2 = Get-Content $evidence -Raw
                $phase2 | Set-Content (Join-Path $OutputDir "stage07_sequence_runtime.txt") -Encoding UTF8
                if ($phase2 -notmatch "result=PASS" -or
                    $phase2 -notmatch "observed_last=2" -or
                    $phase2 -notmatch "allocated_next=3") {
                    throw "Stage-07 wire sequence restart continuity failed."
                }

                $details["mode"] = "MT5_SEQUENCE_RUNTIME"
                $details["runtime_result"] = "PASS_RESTART_CONTINUITY"
                $details["observed_last"] = 2
                $details["allocated_next"] = 3
                break
            }

            if ($mode -eq "MT5_COMPILE") {
                $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
                $metaEditorPath = Get-ArgValue $request.args "metaeditor_path" ""
                if (-not $terminalDataPath) { throw "terminal_data_path is required for Stage-07 MT5 compile." }
                if (-not $metaEditorPath) { throw "metaeditor_path is required for Stage-07 MT5 compile." }

                $includeSource = Join-Path $RepoRoot "mt5\Include\Katarina"
                $includeDest = Join-Path $terminalDataPath "MQL5\Include\Katarina"
                $testSource = Join-Path $RepoRoot "mt5\Tests\KatarinaStage07WireSequenceTest.mq5"
                $testDest = Join-Path $terminalDataPath "MQL5\Scripts\KatarinaStage07WireSequenceTest.mq5"
                $testEx5 = [IO.Path]::ChangeExtension($testDest,".ex5")
                $compileLog = Join-Path $OutputDir "stage07_wire_sequence_compile.log"

                if (!(Test-Path $includeSource)) { throw "Katarina include source missing." }
                if (!(Test-Path $testSource)) { throw "Stage-07 wire sequence test source missing." }
                New-Item -ItemType Directory -Force -Path $includeDest | Out-Null
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $testDest) | Out-Null
                Copy-Item (Join-Path $includeSource "*") $includeDest -Recurse -Force
                Copy-Item $testSource $testDest -Force
                if (Test-Path $testEx5) { Remove-Item $testEx5 -Force }

                $mqlRoot = Join-Path $terminalDataPath "MQL5"
                $compileArgs = @(
                    "/compile:`"$testDest`"",
                    "/inc:`"$mqlRoot`"",
                    "/log:`"$compileLog`""
                )
                Start-Process -FilePath $metaEditorPath -ArgumentList $compileArgs -Wait | Out-Null
                $resultCode = 0
                $logText = ""
                if (Test-Path $compileLog) { $logText = Get-Content $compileLog -Raw }
                if (!(Test-Path $compileLog) -or !(Test-Path $testEx5) -or $logText -notmatch "0 errors, 0 warnings") {
                    if (Test-Path $compileLog) { $logText | Set-Content $stdoutPath -Encoding UTF8 }
                    throw "Stage-07 MT5 wire sequence compile failed."
                }

                $details["mode"] = "MT5_COMPILE"
                $details["ex5_exists"] = $true
                $details["ex5_sha256"] = (Get-FileHash $testEx5 -Algorithm SHA256).Hash
                $details["compile_result"] = "PASS_0_ERRORS_0_WARNINGS"
                break
            }

            $python = Resolve-Executable @("python.exe","python")
            if (-not $python) { throw "Python executable not found." }

            $resultCode = Invoke-Captured -FilePath $python -ArgumentList @("-m","unittest","tests.unit.transport.test_stage07_communication","-v") -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            if ($resultCode -ne 0) { throw "Stage-07 Python tests failed." }
        }

        "STAGE06_HOST_CHECK" {
            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            if (-not $terminalDataPath) {
                throw "terminal_data_path is required for STAGE06_HOST_CHECK."
            }

            $script = Join-Path $RepoRoot "scripts\mt5\check_stage06_host.ps1"
            if (!(Test-Path $script)) { throw "Stage-06 host check script missing." }

            $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script) -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            $hostOut = ""
            if (Test-Path $stdoutPath) { $hostOut += (Get-Content -Path $stdoutPath -Raw) }
            if (Test-Path $stderrPath) { $hostOut += [Environment]::NewLine + (Get-Content -Path $stderrPath -Raw) }

            if ($hostOut -match "(?im)^Class:\s*DEFERRED\s*$" -or $hostOut -match "DEFERRED:") {
                $details["validation_class"] = "DEFERRED"
                throw "Stage-06 host is DEFERRED and is not freeze-qualified."
            }

            if ($resultCode -ne 0) { throw "Stage-06 host check failed." }
            $details["validation_class"] = "SUPPORTED"
        }

        "STAGE06_COMPILE_PROOF" {
            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            $metaEditorPath = Get-ArgValue $request.args "metaeditor_path" ""
            if (-not $terminalDataPath) {
                throw "terminal_data_path is required for STAGE06_COMPILE_PROOF."
            }

            $os = Get-WmiObject Win32_OperatingSystem
            $isDeferred2012 = ([string]$os.Caption -match "Windows Server 2012 R2")

            if ($isDeferred2012) {
                $script = Join-Path $RepoRoot "scripts\mt5\compile_stage06.ps1"
                if (!(Test-Path $script)) { throw "Stage-06 compile script missing." }

                $invoke = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"-TerminalDataPath",$terminalDataPath,"-AllowDeferredHostCompile")
                if ($metaEditorPath) { $invoke += @("-MetaEditorPath",$metaEditorPath) }

                $details["validation_scope"] = "LEGACY_EXPLORATORY_COMPILE_ONLY"
                $details["freeze_qualified"] = $false
            }
            else {
                $script = Join-Path $RepoRoot "scripts\mt5\verify_stage06_modern_windows.ps1"
                if (!(Test-Path $script)) { throw "Stage-06 verifier missing." }

                $invoke = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"-TerminalDataPath",$terminalDataPath)
                if ($metaEditorPath) { $invoke += @("-MetaEditorPath",$metaEditorPath) }

                $details["validation_scope"] = "FULL_HOST_STATIC_COMPILE"
                $details["freeze_qualified"] = $true
            }

            $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList $invoke -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot

            $buildDir = Join-Path $RepoRoot "build\mt5"
            if (Test-Path $buildDir) {
                foreach ($log in @(Get-ChildItem -Path $buildDir -Filter "*.compile.log" -File -ErrorAction SilentlyContinue)) {
                    Copy-Item $log.FullName (Join-Path $OutputDir $log.Name) -Force
                }
            }

            $compileEvidence = Join-Path $RepoRoot "build\mt5\stage06_compile_evidence.json"
            if (!(Test-Path $compileEvidence)) {
                throw "Stage-06 compile evidence was not generated."
            }

            $evidence = Get-Content -Path $compileEvidence -Raw | ConvertFrom-Json
            if ($isDeferred2012) {
                $expected = "PASS_LEGACY_COMPILE_NOT_FREEZE_PROOF"
            }
            else {
                $expected = "PASS_COMPILE_PROOF"
            }

            if ([string]$evidence.result -ne $expected) {
                throw "Unexpected Stage-06 compile evidence result: $($evidence.result)"
            }

            if ($resultCode -ne 0) {
                throw "Stage-06 compile proof process failed."
            }

            Copy-Item $compileEvidence (Join-Path $OutputDir "stage06_compile_evidence.json") -Force
            $details["compile_result"] = [string]$evidence.result
        }

        "STAGE06_RUNTIME_PROBE" {
            $terminalPath = Get-ArgValue $request.args "terminal_path" ""
            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            $terminalCommonDataPath = Get-ArgValue $request.args "terminal_common_data_path" ""
            $mode = ([string](Get-ArgValue $request.args "mode" "SELF_TEST")).ToUpperInvariant()
            $symbol = [string](Get-ArgValue $request.args "symbol" "EURUSD")
            $timeoutSeconds = [int](Get-ArgValue $request.args "timeout_seconds" 120)

            if (-not $terminalPath -or !(Test-Path -LiteralPath $terminalPath -PathType Leaf)) {
                throw "terminal_path is required and must exist for STAGE06_RUNTIME_PROBE."
            }
            if (-not $terminalDataPath -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
                throw "terminal_data_path is required and must exist for STAGE06_RUNTIME_PROBE."
            }
            if (-not $terminalCommonDataPath -or !(Test-Path -LiteralPath $terminalCommonDataPath -PathType Container)) {
                throw "terminal_common_data_path is required and must exist for STAGE06_RUNTIME_PROBE."
            }
            if ($timeoutSeconds -lt 15 -or $timeoutSeconds -gt 300) {
                throw "timeout_seconds must be between 15 and 300."
            }

            $allowedModes = @("SELF_TEST","DISCOVERY","STANDARD_LIKE","CENT_LIKE")
            if ($allowedModes -notcontains $mode) {
                throw "Unsupported Stage-06 runtime probe mode: $mode"
            }

            $terminalResolved = (Resolve-Path -LiteralPath $terminalPath).Path
            $activeSameTerminal = @()
            try {
                $activeSameTerminal = @(
                    Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.ExecutablePath -and
                        ([string]$_.ExecutablePath).ToLowerInvariant() -eq $terminalResolved.ToLowerInvariant()
                    }
                )
            } catch {}

            if ($activeSameTerminal.Count -gt 0) {
                throw "Target MT5 terminal is already running. Refusing headless probe to avoid interfering with the active trading session."
            }

            $scriptsDir = Join-Path $terminalDataPath "MQL5\Scripts"
            $selfTestEx5 = Join-Path $scriptsDir "KatarinaStage06SelfTest.ex5"
            $probeEx5 = Join-Path $scriptsDir "KatarinaStage06AccountProbe.ex5"

            if ($mode -eq "SELF_TEST") {
                if (!(Test-Path -LiteralPath $selfTestEx5 -PathType Leaf)) {
                    throw "Compiled self-test EX5 not found. Run STAGE06_COMPILE_PROOF first."
                }
                $scriptName = "KatarinaStage06SelfTest"
                $evidenceName = "Katarina_Stage06_self_test_result.txt"
                $expectedProofType = "MQL_SELF_TEST"
            }
            else {
                if (!(Test-Path -LiteralPath $probeEx5 -PathType Leaf)) {
                    throw "Compiled account-probe EX5 not found. Run STAGE06_COMPILE_PROOF first."
                }
                $scriptName = "KatarinaStage06AccountProbe"
                $evidenceName = "Katarina_Stage06_account_probe_" + $mode + ".txt"
                $expectedProofType = $(if ($mode -eq "DISCOVERY") { "ACCOUNT_DISCOVERY" } else { "ACCOUNT_PROBE" })
            }

            $commonFiles = Join-Path $terminalCommonDataPath "Files"
            New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null

            $evidencePath = Join-Path $commonFiles $evidenceName
            Remove-Item -LiteralPath $evidencePath -Force -ErrorAction SilentlyContinue

            $controlPath = Join-Path $commonFiles "Katarina_Stage06_probe_class.txt"
            if ($mode -ne "SELF_TEST") {
                $mode | Set-Content -Path $controlPath -Encoding ASCII
            }

            $configPath = Join-Path $OutputDir ("stage06_runtime_" + $mode + ".ini")
            $configLines = @(
                "[Common]",
                "NewsEnable=0",
                "",
                "[Experts]",
                "AllowLiveTrading=0",
                "AllowDllImport=0",
                "Enabled=1",
                "Account=0",
                "Profile=0",
                "",
                "[StartUp]",
                ("Script=" + $scriptName),
                ("Symbol=" + $symbol),
                "Period=M1",
                "ShutdownTerminal=1"
            )
            $configLines | Set-Content -Path $configPath -Encoding ASCII

            $profileRoot = ""
            $appDataRoaming = ""
            $marker = "\AppData\Roaming\MetaQuotes\Terminal\"
            $markerIndex = $terminalDataPath.IndexOf($marker,[StringComparison]::OrdinalIgnoreCase)
            if ($markerIndex -gt 0) {
                $profileRoot = $terminalDataPath.Substring(0,$markerIndex)
                $appDataRoaming = Join-Path $profileRoot "AppData\Roaming"
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $terminalResolved
            $psi.Arguments = '/config:"' + $configPath + '"'
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $false

            if ($profileRoot -and $appDataRoaming) {
                $psi.EnvironmentVariables["USERPROFILE"] = $profileRoot
                $psi.EnvironmentVariables["APPDATA"] = $appDataRoaming
                $psi.EnvironmentVariables["LOCALAPPDATA"] = (Join-Path $profileRoot "AppData\Local")
                $psi.EnvironmentVariables["HOMEDRIVE"] = [IO.Path]::GetPathRoot($profileRoot).TrimEnd("\")
                $psi.EnvironmentVariables["HOMEPATH"] = $profileRoot.Substring([IO.Path]::GetPathRoot($profileRoot).Length - 1)
            }

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $details["launched_pid"] = $proc.Id

            $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
            while ([DateTime]::UtcNow -lt $deadline) {
                if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
                    break
                }
                if ($proc.HasExited) {
                    Start-Sleep -Seconds 2
                    break
                }
                Start-Sleep -Seconds 2
            }

            if (!(Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
                if (-not $proc.HasExited) {
                    try { $proc.Kill() } catch {}
                }

                $recentLogs = @()
                foreach ($root in @((Join-Path $terminalDataPath "Logs"),(Join-Path $terminalDataPath "MQL5\Logs"))) {
                    if (Test-Path $root) {
                        $recentLogs += Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTimeUtc -Descending |
                            Select-Object -First 2
                    }
                }

                $logIndex = 0
                foreach ($log in @($recentLogs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 4)) {
                    $logIndex++
                    $textLog = Get-Content -Path $log.FullName -Tail 400 -ErrorAction SilentlyContinue | Out-String
                    $textLog = Redact-Text $textLog
                    $outName = ("stage06_runtime_log_{0:D2}.txt" -f $logIndex)
                    $textLog | Set-Content -Path (Join-Path $OutputDir $outName) -Encoding UTF8
                }

                throw "Stage-06 runtime evidence was not produced before timeout."
            }

            $evidenceText = Get-Content -LiteralPath $evidencePath -Raw
            $safeEvidence = Redact-Text $evidenceText
            $outputEvidence = Join-Path $OutputDir $evidenceName
            $safeEvidence | Set-Content -Path $outputEvidence -Encoding UTF8

            $parsed = [ordered]@{}
            foreach ($line in Get-Content -LiteralPath $evidencePath) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $eq = $line.IndexOf("=")
                if ($eq -lt 1) { continue }
                $parsed[$line.Substring(0,$eq).Trim()] = $line.Substring($eq+1).Trim()
            }

            if (-not $parsed.Contains("result") -or [string]$parsed["result"] -ne "PASS") {
                throw "Stage-06 runtime evidence result is not PASS."
            }
            if (-not $parsed.Contains("proof_type") -or [string]$parsed["proof_type"] -ne $expectedProofType) {
                throw "Stage-06 runtime evidence proof_type mismatch."
            }
            if ($mode -ne "SELF_TEST") {
                if (-not $parsed.Contains("account_class") -or [string]$parsed["account_class"] -ne $mode) {
                    throw "Stage-06 runtime account_class mismatch."
                }
            }

            $details["runtime_mode"] = $mode
            $details["evidence"] = $evidenceName
            $details["proof_type"] = [string]$parsed["proof_type"]
            if ($parsed.Contains("terminal_build")) {
                $details["terminal_build"] = [string]$parsed["terminal_build"]
            }
            if ($parsed.Contains("account_currency")) {
                $details["account_currency"] = [string]$parsed["account_currency"]
            }
            if ($parsed.Contains("broker_server")) {
                $details["broker_server"] = [string]$parsed["broker_server"]
            }
            if ($parsed.Contains("symbol")) {
                $details["symbol"] = [string]$parsed["symbol"]
            }

            ("STAGE06_RUNTIME_PROBE " + $mode + " PASS") | Set-Content $stdoutPath -Encoding UTF8
            "" | Set-Content $stderrPath -Encoding UTF8
        }

        "STAGE06_CLEARANCE" {
            $mode = ([string](Get-ArgValue $request.args "mode" "FULL")).ToUpperInvariant()

            if ($mode -eq "PREPARE_RUNTIME") {
                $target = "C:\KatarinaStage06Runtime"
                New-Item -ItemType Directory -Force -Path $target | Out-Null

                $sourcePs1 = Join-Path $RepoRoot "scripts\mt5\Run-Stage06RuntimeInteractive.ps1"
                $sourceCmd = Join-Path $RepoRoot "scripts\mt5\FINALIZE_STAGE06_RUNTIME.cmd"
                if (!(Test-Path $sourcePs1) -or !(Test-Path $sourceCmd)) {
                    throw "Stage-06 interactive runtime finalizer source is missing."
                }

                Copy-Item $sourcePs1 (Join-Path $target "Run-Stage06RuntimeInteractive.ps1") -Force
                Copy-Item $sourceCmd (Join-Path $target "FINALIZE_STAGE06_RUNTIME.cmd") -Force

                @"
KATARINA AI - Stage 06 Runtime Finalizer

Run from the interactive Administrator/user desktop:
  FINALIZE_STAGE06_RUNTIME.cmd

Safety:
- AllowLiveTrading=0
- no OrderSend path
- no password is requested or exported
- scripts only read account/symbol facts and write Stage-06 evidence

After PASS, return to ChatGPT and type:
  cek Stage 06 runtime
"@ | Set-Content -Path (Join-Path $target "README.txt") -Encoding UTF8

                ("STAGE06 PREPARE_RUNTIME PASS" + [Environment]::NewLine + "Path: " + $target) | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = "PREPARE_RUNTIME"
                $details["runtime_finalizer_path"] = $target
                break
            }

            if ($mode -eq "INSPECT_RUNTIME") {
                $terminalCommonDataPath = Get-ArgValue $request.args "terminal_common_data_path" ""
                if (-not $terminalCommonDataPath) {
                    throw "terminal_common_data_path is required for INSPECT_RUNTIME."
                }

                $commonFiles = Join-Path $terminalCommonDataPath "Files"
                $runtimeRoot = "C:\KatarinaStage06Runtime"
                $manifest = [ordered]@{
                    schema_version = 1
                    stage = "06"
                    generated_utc = [DateTime]::UtcNow.ToString("o")
                    common_files = @()
                    runtime_runs = @()
                    mt5_instances = @()
                }

                if (Test-Path $commonFiles) {
                    foreach ($f in @(Get-ChildItem -Path $commonFiles -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "Katarina_Stage06_*" } |
                        Sort-Object LastWriteTimeUtc -Descending)) {
                        $item = [ordered]@{
                            name = $f.Name
                            size_bytes = [int64]$f.Length
                            last_write_utc = $f.LastWriteTimeUtc.ToString("o")
                            sha256 = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
                        }
                        if ($f.Extension -eq ".txt" -and $f.Length -lt 65536) {
                            $txt = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
                            $item["content"] = Redact-Text $txt
                        }
                        $manifest.common_files += [pscustomobject]$item
                    }
                }

                try {
                    $activeTerminals = @(
                        Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue
                    )
                } catch {
                    $activeTerminals = @()
                }

                try {
                    foreach ($origin in @(Get-ChildItem -Path "C:\Users\*\AppData\Roaming\MetaQuotes\Terminal\*\origin.txt" -ErrorAction SilentlyContinue)) {
                        try {
                            $home = (Get-Content -LiteralPath $origin.FullName -Raw -ErrorAction Stop).Trim()
                            $data = Split-Path -Parent $origin.FullName
                            $terminal = Join-Path $home "terminal64.exe"
                            $selfTest = Join-Path $data "MQL5\Scripts\KatarinaStage06SelfTest.ex5"
                            $probe = Join-Path $data "MQL5\Scripts\KatarinaStage06AccountProbe.ex5"

                            $isRunning = $false
                            foreach ($p in $activeTerminals) {
                                if ($p.ExecutablePath -and [string]::Equals($p.ExecutablePath,$terminal,[StringComparison]::OrdinalIgnoreCase)) {
                                    $isRunning = $true
                                    break
                                }
                            }

                            $manifest.mt5_instances += [pscustomobject]@{
                                home = $home
                                data = $data
                                terminal_exists = (Test-Path -LiteralPath $terminal -PathType Leaf)
                                self_test_ex5 = (Test-Path -LiteralPath $selfTest -PathType Leaf)
                                account_probe_ex5 = (Test-Path -LiteralPath $probe -PathType Leaf)
                                terminal_running = $isRunning
                            }
                        } catch {}
                    }
                } catch {}

                if (Test-Path $runtimeRoot) {
                    foreach ($dir in @(Get-ChildItem -Path $runtimeRoot -Directory -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 10)) {
                        $entry = [ordered]@{
                            name = $dir.Name
                            last_write_utc = $dir.LastWriteTimeUtc.ToString("o")
                            files = @()
                        }
                        foreach ($f in @(Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue |
                            Sort-Object Name)) {
                            $fileInfo = [ordered]@{
                                name = $f.Name
                                size_bytes = [int64]$f.Length
                                last_write_utc = $f.LastWriteTimeUtc.ToString("o")
                            }
                            if ($f.Length -lt 65536) {
                                try {
                                    $fileInfo["content"] = Redact-Text (Get-Content -Path $f.FullName -Raw -ErrorAction Stop)
                                } catch {}
                            }
                            $entry.files += [pscustomobject]$fileInfo
                        }
                        $manifest.runtime_runs += [pscustomobject]$entry
                    }
                }

                $explicitInstances = @(
                    [pscustomobject]@{
                        name = "MT5_ALFA"
                        terminal = "C:\Program Files\MetaTrader 5 ALFA\terminal64.exe"
                        data = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\2698BCED53B80670A80FF375C9E8D6A1"
                    },
                    [pscustomobject]@{
                        name = "MT5_GENERIC"
                        terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
                        data = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
                    }
                )

                $direct = @()
                foreach ($inst in $explicitInstances) {
                    $isRunning = $false
                    try {
                        foreach ($p in @(Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue)) {
                            if ($p.ExecutablePath -and [string]::Equals($p.ExecutablePath,$inst.terminal,[StringComparison]::OrdinalIgnoreCase)) {
                                $isRunning = $true
                                break
                            }
                        }
                    } catch {}

                    $direct += [pscustomobject]@{
                        name = $inst.name
                        terminal_exists = (Test-Path -LiteralPath $inst.terminal -PathType Leaf)
                        self_test_ex5 = (Test-Path -LiteralPath (Join-Path $inst.data "MQL5\Scripts\KatarinaStage06SelfTest.ex5") -PathType Leaf)
                        account_probe_ex5 = (Test-Path -LiteralPath (Join-Path $inst.data "MQL5\Scripts\KatarinaStage06AccountProbe.ex5") -PathType Leaf)
                        terminal_running = $isRunning
                    }
                }
                $manifest["direct_instances"] = $direct

                Write-JsonFile (Join-Path $OutputDir "stage06_runtime_inspection.json") $manifest
                "STAGE06 INSPECT_RUNTIME PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = "INSPECT_RUNTIME"
                $details["common_files"] = @($manifest.common_files).Count
                $details["runtime_runs"] = @($manifest.runtime_runs).Count
                break
            }

            if ($mode -eq "COLLECT_RUNTIME") {
                $terminalCommonDataPath = Get-ArgValue $request.args "terminal_common_data_path" ""
                if (-not $terminalCommonDataPath) {
                    throw "terminal_common_data_path is required for COLLECT_RUNTIME."
                }

                $sourceDir = Join-Path $terminalCommonDataPath "Files"
                if (!(Test-Path $sourceDir)) {
                    throw "MT5 Common Files directory not found: $sourceDir"
                }

                $requiredRuntime = @(
                    "Katarina_Stage06_self_test_result.txt",
                    "Katarina_Stage06_account_probe_STANDARD_LIKE.txt",
                    "Katarina_Stage06_account_probe_CENT_LIKE.txt"
                )

                function Read-KatEvidenceLocal {
                    param([string]$Path)
                    $values = [ordered]@{}
                    foreach ($line in Get-Content -Path $Path) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        $idx = $line.IndexOf("=")
                        if ($idx -lt 1) { continue }
                        $values[$line.Substring(0,$idx).Trim()] = $line.Substring($idx+1).Trim()
                    }
                    return $values
                }

                $records = @()
                foreach ($name in $requiredRuntime) {
                    $source = Join-Path $sourceDir $name
                    if (!(Test-Path $source)) {
                        throw "Required Stage-06 runtime evidence missing: $name"
                    }

                    $values = Read-KatEvidenceLocal -Path $source
                    foreach ($key in @("stage","design_version","proof_type","terminal_build","result")) {
                        if (-not $values.Contains($key)) {
                            throw "Runtime evidence $name missing field: $key"
                        }
                    }
                    if ($values["stage"] -ne "06") { throw "Runtime evidence stage mismatch: $name" }
                    if ($values["design_version"] -ne "0.5.0") { throw "Runtime evidence design mismatch: $name" }
                    if ($values["result"] -ne "PASS") { throw "Runtime evidence did not pass: $name" }

                    $dest = Join-Path $OutputDir $name
                    Copy-Item $source $dest -Force
                    $info = Get-Item $source

                    $records += [pscustomobject]@{
                        file = $name
                        last_write_utc = $info.LastWriteTimeUtc.ToString("o")
                        sha256 = (Get-FileHash -Path $dest -Algorithm SHA256).Hash
                        values = $values
                    }
                }

                $self = $records | Where-Object { $_.file -eq "Katarina_Stage06_self_test_result.txt" }
                $std = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_STANDARD_LIKE.txt" }
                $cent = $records | Where-Object { $_.file -eq "Katarina_Stage06_account_probe_CENT_LIKE.txt" }

                if ($self.values["proof_type"] -ne "MQL_SELF_TEST") { throw "Invalid MQL self-test proof type." }
                if ($std.values["proof_type"] -ne "ACCOUNT_PROBE" -or $std.values["account_class"] -ne "STANDARD_LIKE") {
                    throw "Invalid STANDARD_LIKE runtime proof."
                }
                if ($cent.values["proof_type"] -ne "ACCOUNT_PROBE" -or $cent.values["account_class"] -ne "CENT_LIKE") {
                    throw "Invalid CENT_LIKE runtime proof."
                }

                $stdIdentity = [string]$std.values["broker_server"] + "|" + [string]$std.values["login_last4"]
                $centIdentity = [string]$cent.values["broker_server"] + "|" + [string]$cent.values["login_last4"]
                if ($stdIdentity -eq $centIdentity) {
                    throw "STANDARD_LIKE and CENT_LIKE evidence use the same account identity."
                }

                $manifest = [ordered]@{
                    schema_version = "1.0"
                    stage = "06"
                    bridge_design_version = "0.5.0"
                    generated_utc = [DateTime]::UtcNow.ToString("o")
                    source_host = $env:COMPUTERNAME
                    records = $records
                    identities_distinct = $true
                    result = "PASS_STAGE06_RUNTIME_PROBES"
                }
                Write-JsonFile (Join-Path $OutputDir "stage06_runtime_probe_manifest.json") $manifest

                "STAGE06 COLLECT_RUNTIME PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = "COLLECT_RUNTIME"
                $details["runtime_result"] = "PASS_STAGE06_RUNTIME_PROBES"
                $details["records"] = 3
                break
            }

            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            $terminalCommonDataPath = Get-ArgValue $request.args "terminal_common_data_path" ""
            $metaEditorPath = Get-ArgValue $request.args "metaeditor_path" ""
            $waitMinutes = [int](Get-ArgValue $request.args "runtime_wait_minutes" 30)

            if (-not $terminalDataPath -or -not $terminalCommonDataPath) {
                throw "terminal_data_path and terminal_common_data_path are required."
            }

            $script = Join-Path $RepoRoot "scripts\mt5\complete_stage06.ps1"
            if (!(Test-Path $script)) { throw "Stage-06 complete runner missing." }

            $invoke = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"-TerminalDataPath",$terminalDataPath,"-TerminalCommonDataPath",$terminalCommonDataPath,"-RuntimeWaitMinutes",$waitMinutes)
            if ($metaEditorPath) { $invoke += @("-MetaEditorPath",$metaEditorPath) }

            $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList $invoke -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            if ($resultCode -ne 0) { throw "Stage-06 clearance failed." }

            foreach ($name in @("stage06_compile_evidence.json","stage06_runtime_evidence.json","stage06_final_clearance.json","STAGE_06_FINAL_AUDIT_CANDIDATE.md")) {
                $source = Join-Path $RepoRoot ("build\mt5\" + $name)
                if (Test-Path $source) {
                    Copy-Item $source (Join-Path $OutputDir $name) -Force
                }
            }
        }

        "COLLECT_MT5_LOGS" {
            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            $maxFiles = [int](Get-ArgValue $request.args "max_files" 8)
            $tailLines = [int](Get-ArgValue $request.args "tail_lines" 500)
            if (-not $terminalDataPath) {
                throw "terminal_data_path is required for COLLECT_MT5_LOGS."
            }

            $roots = @((Join-Path $terminalDataPath "MQL5\Logs"),(Join-Path $terminalDataPath "Logs"),(Join-Path $terminalDataPath "Tester\logs")) | Where-Object { Test-Path $_ }

            $selected = @()
            foreach ($root in $roots) {
                $selected += Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
            }

            $selected = $selected | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $maxFiles
            $manifest = @()
            $index = 0

            foreach ($file in $selected) {
                $index++
                $text = Get-Content -Path $file.FullName -Tail $tailLines -ErrorAction SilentlyContinue | Out-String
                $text = Redact-Text $text
                $name = ("mt5_log_{0:D2}_{1}.txt" -f $index, $file.BaseName)
                $dest = Join-Path $OutputDir $name
                $text | Set-Content -Path $dest -Encoding UTF8
                $manifest += [ordered]@{
                    output_file = $name
                    source_name = $file.Name
                    last_write_utc = $file.LastWriteTimeUtc.ToString("o")
                    source_size_bytes = [int64]$file.Length
                }
            }

            Write-JsonFile (Join-Path $OutputDir "mt5_log_manifest.json") $manifest
            "COLLECT_MT5_LOGS PASS" | Set-Content $stdoutPath -Encoding UTF8
            "" | Set-Content $stderrPath -Encoding UTF8
            $details["files"] = $manifest.Count
        }
    }
}
catch {
    $status = "FAIL"
    if ($resultCode -eq 0) { $resultCode = 1 }
    $message = $_.Exception.Message
    if (!(Test-Path $stderrPath)) {
        $message | Set-Content -Path $stderrPath -Encoding UTF8
    } else {
        Add-Content -Path $stderrPath -Value $message
    }
}

$completed = [DateTime]::UtcNow
$summary = [ordered]@{
    schema_version = 1
    request_id = [string]$request.request_id
    agent_id = $AgentId
    task = $task
    started_utc = $started.ToString("o")
    completed_utc = $completed.ToString("o")
    duration_ms = [int64]($completed - $started).TotalMilliseconds
    status = $status
    exit_code = $resultCode
    details = $details
}

Write-JsonFile (Join-Path $OutputDir "result.json") $summary

if ($status -ne "PASS") { exit $resultCode }
exit 0
