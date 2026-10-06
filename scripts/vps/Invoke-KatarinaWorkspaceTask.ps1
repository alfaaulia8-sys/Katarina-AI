param(
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$WorkspaceRoot = "C:\KatarinaDev"
$Workspace = Join-Path $WorkspaceRoot "workspace"
$Metadata = Join-Path $WorkspaceRoot "metadata"
$Evidence = Join-Path $WorkspaceRoot "evidence"
$Artifacts = Join-Path $WorkspaceRoot "artifacts"
$Snapshots = Join-Path $WorkspaceRoot "snapshots"
$Logs = Join-Path $WorkspaceRoot "logs"
$Runtime = Join-Path $WorkspaceRoot "runtime"

function Write-Json([string]$Path,$Value) {
    # PowerShell 4 can enumerate OrderedDictionary values when they are sent
    # through the pipeline. -InputObject preserves the evidence object as one
    # JSON document instead of attempting invalid item-by-item conversion.
    ConvertTo-Json -InputObject $Value -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-Exe([string[]]$Candidates) {
    foreach($candidate in $Candidates) {
        if(!$candidate) { continue }
        if(Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
        $cmd=Get-Command $candidate -ErrorAction SilentlyContinue
        if($cmd) { return $cmd.Source }
    }
    return $null
}

function Build-Manifest {
    if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
    $records=@()
    foreach($file in @(Get-ChildItem -LiteralPath $Workspace -File -Recurse -ErrorAction Stop)) {
        $relative=$file.FullName.Substring($Workspace.Length).TrimStart("\")
        $records += [ordered]@{
            path=($relative -replace "\\","/")
            size=[int64]$file.Length
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return @($records | Sort-Object path)
}

$request=Get-Content -LiteralPath $RequestFile -Raw | ConvertFrom-Json
$mode=([string]$request.args.mode).ToUpperInvariant()
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

switch($mode) {
    "WORKSPACE_INIT" {
        foreach($dir in @($WorkspaceRoot,$Metadata,$Evidence,$Artifacts,$Snapshots,$Logs,$Runtime)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        if(Test-Path -LiteralPath $Workspace) {
            $backup=Join-Path $Snapshots ("pre_init_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
            Move-Item -LiteralPath $Workspace -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
        foreach($item in Get-ChildItem -LiteralPath $RepoRoot -Force) {
            if(@(".git","ops") -contains $item.Name) { continue }
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Workspace $item.Name) -Recurse -Force
        }
        Write-Json (Join-Path $Metadata "workspace.json") ([ordered]@{
            schema_version=1
            workspace_version="1.0"
            source_ref=[string]$request.ref
            initialized_utc=[DateTime]::UtcNow.ToString("o")
            computer_name=$env:COMPUTERNAME
            development_mode="VPS_FIRST"
            github_role="COMMAND_BUS_AND_CANONICAL_RELEASE"
        })
    }

    "WORKSPACE_STATUS" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
    }

    "WORKSPACE_APPLY" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        if($null -eq $request.args.PSObject.Properties["changeset"]) { throw "changeset is required." }
        $json=$request.args.changeset | ConvertTo-Json -Depth 16
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) { throw "Changeset exceeds 256 KiB command-bus limit." }
        $file=Join-Path $OutputDir "workspace_changeset.json"
        $json | Set-Content -LiteralPath $file -Encoding UTF8
        $engine=Join-Path $RepoRoot "scripts\vps\Apply-KatarinaWorkspaceChangeset.ps1"
        if(!(Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Workspace changeset engine missing." }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine -ChangesetPath $file -WorkspaceRoot $Workspace -EvidenceRoot $Evidence
        if($LASTEXITCODE -ne 0) { throw "Workspace changeset application failed." }
    }

    "WORKSPACE_BOOTSTRAP_PYTHON" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $bootstrap=Join-Path $RepoRoot "scripts\vps\Bootstrap-KatarinaPortablePython.ps1"
        if(!(Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw "Portable Python bootstrap script missing." }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap -WorkspaceRoot $WorkspaceRoot -OutputDir $OutputDir
        if($LASTEXITCODE -ne 0) { throw "Portable Python bootstrap failed." }

        $bootstrapEvidence=Join-Path $OutputDir "python_bootstrap.json"
        $probeEvidence=Join-Path $OutputDir "python_probe.txt"
        if(!(Test-Path -LiteralPath $bootstrapEvidence -PathType Leaf)) { throw "Portable Python bootstrap evidence is missing." }
        if(!(Test-Path -LiteralPath $probeEvidence -PathType Leaf)) { throw "Portable Python dependency probe evidence is missing." }
        $bootstrapState=Get-Content -LiteralPath $bootstrapEvidence -Raw | ConvertFrom-Json
        if([string]$bootstrapState.result -ne "PASS") { throw "Portable Python bootstrap evidence did not report PASS." }
        $probeText=Get-Content -LiteralPath $probeEvidence -Raw
        foreach($requiredMarker in @("pyzmq=","libzmq=","tornado=")) {
            if($probeText -notmatch [regex]::Escape($requiredMarker)) { throw "Portable Python dependency probe is incomplete: $requiredMarker" }
        }
        # Canonical bootstrap is complete. Stop this switch so legacy duplicate
        # WORKSPACE_BOOTSTRAP_PYTHON cases further below cannot overwrite it.
        break
    }

    "WORKSPACE_CONTROL_DEDUP_LEGACY_AGENTS" {
        $installRoot="C:\KatarinaVPSAgent"
        $primaryConfig=Join-Path $installRoot "agent.json"
        $matches=@()
        try {
            $matches=@(
                Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.CommandLine -and
                    $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $_.CommandLine.IndexOf($primaryConfig,[StringComparison]::OrdinalIgnoreCase) -ge 0
                } |
                Sort-Object CreationDate -Descending
            )
        } catch {}

        $before=@($matches | ForEach-Object {
            [ordered]@{
                process_id=[int]$_.ProcessId
                creation_date=[string]$_.CreationDate
                command_line=[regex]::Replace([string]$_.CommandLine,'(?i)(token|secret|password)=\S+','$1=[REDACTED]')
            }
        })

        $keptPid=$null
        $terminated=@()
        if($matches.Count -gt 0) {
            $keptPid=[int]$matches[0].ProcessId
            foreach($proc in @($matches | Select-Object -Skip 1)) {
                $terminated += [int]$proc.ProcessId
                try { [void]$proc.Terminate() } catch {}
            }
        }

        Start-Sleep -Seconds 2

        $after=@()
        try {
            $after=@(
                Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.CommandLine -and
                    $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $_.CommandLine.IndexOf($primaryConfig,[StringComparison]::OrdinalIgnoreCase) -ge 0
                } |
                ForEach-Object {
                    [ordered]@{
                        process_id=[int]$_.ProcessId
                        creation_date=[string]$_.CreationDate
                    }
                }
            )
        } catch {}

        $ok=($after.Count -le 1)
        Write-Json (Join-Path $OutputDir "control_agent_dedup.json") ([ordered]@{
            schema_version=1
            proof_type="KATARINA_CONTROL_AGENT_DEDUP"
            before=$before
            kept_process_id=$keptPid
            terminated_process_ids=$terminated
            after=$after
            generated_utc=[DateTime]::UtcNow.ToString("o")
            result=$(if($ok){"PASS"}else{"FAIL"})
        })
        if(!$ok){throw "Legacy agent deduplication left more than one primary agent process."}
        break
    }

    "WORKSPACE_CONTROL_PLANE_V2_INSTALL" {
        $installRoot="C:\KatarinaVPSAgent"
        $tokenPath=Join-Path $installRoot "token.bin"
        $primaryConfigPath=Join-Path $installRoot "agent.json"
        $agentSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgent.ps1"
        $watchdogSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgentWatchdog.ps1"
        $supervisorSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaControlSupervisor.ps1"

        foreach($required in @($tokenPath,$primaryConfigPath,$agentSource,$watchdogSource,$supervisorSource)) {
            if(!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Control Plane v2 prerequisite missing: $required" }
        }

        $existing=Get-Content -LiteralPath $primaryConfigPath -Raw | ConvertFrom-Json
        $repoName=[string]$existing.repository
        $branchName=[string]$existing.branch
        $primaryAgentId=[string]$existing.agent_id
        if([string]::IsNullOrWhiteSpace($repoName)){ $repoName="alfaaulia8-sys/Katarina-AI" }
        if([string]::IsNullOrWhiteSpace($branchName)){ $branchName="main" }
        if([string]::IsNullOrWhiteSpace($primaryAgentId)){ $primaryAgentId="katarina-vps-2012r2-01" }

        New-Item -ItemType Directory -Force -Path $installRoot,(Join-Path $installRoot "lanes") | Out-Null
        Copy-Item -LiteralPath $agentSource -Destination (Join-Path $installRoot "KatarinaVpsAgent.ps1") -Force
        Copy-Item -LiteralPath $watchdogSource -Destination (Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1") -Force
        Copy-Item -LiteralPath $supervisorSource -Destination (Join-Path $installRoot "KatarinaControlSupervisor.ps1") -Force

        $common=[ordered]@{
            schema_version=2
            repository=$repoName
            branch=$branchName
            results_dir="ops/vps/results"
            token_path=$tokenPath
            compact_results=$true
            installed_utc=[DateTime]::UtcNow.ToString("o")
        }

        $primary=[ordered]@{}
        foreach($k in $common.Keys){$primary[$k]=$common[$k]}
        $primary.agent_id=$primaryAgentId
        $primary.lane="primary"
        $primary.state_root=Join-Path $installRoot "lanes\primary"
        $primary.capabilities=@("MUTATING","READONLY","RECOVERY")
        $primary.poll_seconds=5
        $primary.requests_dir="ops/vps/requests/primary"
        Write-Json $primaryConfigPath $primary

        $recovery=[ordered]@{}
        foreach($k in $common.Keys){$recovery[$k]=$common[$k]}
        $recovery.agent_id=$primaryAgentId+"-recovery"
        $recovery.lane="recovery"
        $recovery.state_root=Join-Path $installRoot "lanes\recovery"
        $recovery.capabilities=@("RECOVERY","READONLY")
        $recovery.poll_seconds=5
        $recovery.requests_dir="ops/vps/requests/recovery"
        $recoveryConfigPath=Join-Path $installRoot "agent-recovery.json"
        Write-Json $recoveryConfigPath $recovery

        $worker01=[ordered]@{}
        foreach($k in $common.Keys){$worker01[$k]=$common[$k]}
        $worker01.agent_id=$primaryAgentId+"-worker01"
        $worker01.lane="worker01"
        $worker01.state_root=Join-Path $installRoot "lanes\worker01"
        $worker01.capabilities=@("READONLY")
        $worker01.poll_seconds=10
        $worker01.requests_dir="ops/vps/requests/worker01"
        $worker01ConfigPath=Join-Path $installRoot "agent-worker01.json"
        Write-Json $worker01ConfigPath $worker01

        $worker02=[ordered]@{}
        foreach($k in $common.Keys){$worker02[$k]=$common[$k]}
        $worker02.agent_id=$primaryAgentId+"-worker02"
        $worker02.lane="worker02"
        $worker02.state_root=Join-Path $installRoot "lanes\worker02"
        $worker02.capabilities=@("READONLY")
        $worker02.poll_seconds=10
        $worker02.requests_dir="ops/vps/requests/worker02"
        $worker02ConfigPath=Join-Path $installRoot "agent-worker02.json"
        Write-Json $worker02ConfigPath $worker02

        $agentPath=Join-Path $installRoot "KatarinaVpsAgent.ps1"
        $supervisorPath=Join-Path $installRoot "KatarinaControlSupervisor.ps1"
        $watchdogPath=Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1"

        $taskDefs=@(
            [pscustomobject]@{name="KatarinaControlRecovery";config=$recoveryConfigPath},
            [pscustomobject]@{name="KatarinaControlWorker01";config=$worker01ConfigPath},
            [pscustomobject]@{name="KatarinaControlWorker02";config=$worker02ConfigPath}
        )
        foreach($td in $taskDefs) {
            $cmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$agentPath+'" -ConfigPath "'+$td.config+'"'
            & schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN $td.name /TR $cmd | Out-Null
            if($LASTEXITCODE -ne 0){throw "Failed to register lane task: $($td.name)"}
        }

        $supervisorCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$supervisorPath+'" -InstallRoot "'+$installRoot+'"'
        & schtasks.exe /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN "KatarinaControlSupervisor" /TR $supervisorCmd | Out-Null
        if($LASTEXITCODE -ne 0){throw "Failed to register KatarinaControlSupervisor."}
        & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN "KatarinaControlSupervisorGuard" /TR $supervisorCmd | Out-Null
        if($LASTEXITCODE -ne 0){throw "Failed to register KatarinaControlSupervisorGuard."}

        $watchdogCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$watchdogPath+'" -InstallRoot "'+$installRoot+'"'
        & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN "KatarinaVPSAgentWatchdog" /TR $watchdogCmd | Out-Null
        if($LASTEXITCODE -ne 0){throw "Failed to register fallback watchdog."}

        $laneTaskMap=[ordered]@{
            recovery="KatarinaControlRecovery"
            worker01="KatarinaControlWorker01"
            worker02="KatarinaControlWorker02"
        }
        $laneChecks=@()
        foreach($laneName in @("recovery","worker01","worker02")) {
            $taskName=[string]$laneTaskMap[$laneName]
            try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
            Start-Sleep -Milliseconds 500
            & schtasks.exe /Run /TN $taskName | Out-Null
            if($LASTEXITCODE -ne 0){throw "Failed to start Control Plane v2 lane task: $taskName"}

            $hbPath=Join-Path $installRoot ("lanes\"+$laneName+"\heartbeat.json")
            $hb=$null
            $deadline=[DateTime]::UtcNow.AddSeconds(25)
            while([DateTime]::UtcNow -lt $deadline) {
                if(Test-Path -LiteralPath $hbPath -PathType Leaf) {
                    try {
                        $candidate=Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
                        $updated=[DateTime]::Parse(
                            [string]$candidate.updated_utc,
                            [Globalization.CultureInfo]::InvariantCulture,
                            [Globalization.DateTimeStyles]::AssumeUniversal
                        ).ToUniversalTime()
                        $fresh=(([DateTime]::UtcNow-$updated).TotalSeconds -lt 20)
                        if($fresh -and [string]$candidate.agent_version -match "^1\\.4\\.") {
                            $hb=$candidate
                            break
                        }
                    } catch {}
                }
                Start-Sleep -Seconds 1
            }
            $ok=($null -ne $hb)
            $laneChecks += [ordered]@{
                lane=$laneName
                task=$taskName
                heartbeat_path=$hbPath
                heartbeat_present=$ok
                phase=$(if($hb){[string]$hb.phase}else{$null})
                agent_version=$(if($hb){[string]$hb.agent_version}else{$null})
                updated_utc=$(if($hb){[string]$hb.updated_utc}else{$null})
            }
        }

        foreach($task in @("KatarinaControlSupervisor","KatarinaVPSAgentWatchdog")) {
            try { & schtasks.exe /End /TN $task | Out-Null } catch {}
            & schtasks.exe /Run /TN $task | Out-Null
            if($LASTEXITCODE -ne 0){throw "Failed to start Control Plane v2 task: $task"}
        }

        $allReady=(@($laneChecks | Where-Object { -not $_.heartbeat_present }).Count -eq 0)
        Write-Json (Join-Path $OutputDir "control_plane_v2_install.json") ([ordered]@{
            schema_version=1
            proof_type="KATARINA_CONTROL_PLANE_V2_INSTALL"
            primary_agent_id=$primaryAgentId
            lanes=@("primary","recovery","worker01","worker02")
            polling_seconds=[ordered]@{primary=5;recovery=5;worker01=10;worker02=10}
            queue_isolation=$true
            compact_results=$true
            supervisor_check_seconds=5
            supervisor_stale_seconds=35
            fallback_watchdog_minutes=1
            primary_restart_pending=$true
            lane_checks=$laneChecks
            installed_utc=[DateTime]::UtcNow.ToString("o")
            result=$(if($allReady){"PASS"}else{"FAIL"})
        })
        if(!$allReady){throw "One or more secondary Control Plane v2 lanes failed to publish heartbeat."}
        break
    }

    "WORKSPACE_CONTROL_LITE_INSTALL" {
        $installRoot="C:\KatarinaVPSAgent"
        $primaryConfig=Join-Path $installRoot "agent.json"
        $agentSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgent.ps1"
        $watchdogSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgentWatchdog.ps1"
        if(!(Test-Path -LiteralPath $primaryConfig -PathType Leaf)){throw "Primary agent config missing."}
        if(!(Test-Path -LiteralPath $agentSource -PathType Leaf)){throw "Agent source missing."}
        if(!(Test-Path -LiteralPath $watchdogSource -PathType Leaf)){throw "Watchdog source missing."}

        $cfg=Get-Content -LiteralPath $primaryConfig -Raw | ConvertFrom-Json
        $lite=[ordered]@{
            schema_version=2
            agent_id=[string]$cfg.agent_id
            repository=[string]$cfg.repository
            branch=[string]$cfg.branch
            poll_seconds=5
            lane="primary"
            state_root=(Join-Path $installRoot "lanes\primary")
            token_path=(Join-Path $installRoot "token.bin")
            requests_dir="ops/vps/requests/primary"
            results_dir="ops/vps/results"
            compact_results=$true
            capabilities=@("MUTATING","READONLY","RECOVERY")
            resource_profile="LEGACY_LOW_MEMORY_SEQUENTIAL"
            installed_utc=[DateTime]::UtcNow.ToString("o")
        }
        Write-Json $primaryConfig $lite
        Copy-Item -LiteralPath $agentSource -Destination (Join-Path $installRoot "KatarinaVpsAgent.ps1") -Force
        Copy-Item -LiteralPath $watchdogSource -Destination (Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1") -Force

        $disabled=@(
            "KatarinaControlRecovery",
            "KatarinaControlWorker01",
            "KatarinaControlWorker02",
            "KatarinaControlSupervisor",
            "KatarinaControlSupervisorGuard"
        )
        foreach($taskName in $disabled) {
            try { & schtasks.exe /End /TN $taskName | Out-Null } catch {}
            try { & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null } catch {}
        }

        foreach($taskName in @("KatarinaVPSAgent","KatarinaVPSAgentWatchdog")) {
            try { & schtasks.exe /Change /TN $taskName /ENABLE | Out-Null } catch {}
        }

        $memory=$null
        try {
            $os=Get-WmiObject Win32_OperatingSystem
            $memory=[ordered]@{
                total_visible_mb=[math]::Round(([double]$os.TotalVisibleMemorySize/1024),0)
                free_physical_mb=[math]::Round(([double]$os.FreePhysicalMemory/1024),0)
                total_virtual_mb=[math]::Round(([double]$os.TotalVirtualMemorySize/1024),0)
                free_virtual_mb=[math]::Round(([double]$os.FreeVirtualMemory/1024),0)
            }
        } catch {}

        Write-Json (Join-Path $OutputDir "control_lite_install.json") ([ordered]@{
            schema_version=1
            proof_type="KATARINA_CONTROL_LITE_INSTALL"
            resource_profile="LEGACY_LOW_MEMORY_SEQUENTIAL"
            persistent_lanes=@("primary")
            watchdog="KatarinaVPSAgentWatchdog"
            disabled_tasks=$disabled
            heavy_job_concurrency=1
            memory=$memory
            primary_restart_recommended=$true
            installed_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
        break
    }

    "WORKSPACE_CONTROL_RESTART_PRIMARY" {
        $installRoot="C:\KatarinaVPSAgent"
        $primaryConfig=Join-Path $installRoot "agent.json"
        $agentScript=Join-Path $installRoot "KatarinaVpsAgent.ps1"
        if(!(Test-Path -LiteralPath $primaryConfig -PathType Leaf)){throw "Primary agent config missing."}
        if(!(Test-Path -LiteralPath $agentScript -PathType Leaf)){throw "Primary agent script missing."}

        $terminated=@()
        try {
            foreach($proc in @(Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
                if($proc.CommandLine -and
                   $proc.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                   $proc.CommandLine.IndexOf($primaryConfig,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $terminated += [int]$proc.ProcessId
                    try{[void]$proc.Terminate()}catch{}
                }
            }
        } catch {}
        Start-Sleep -Seconds 2

        try{& schtasks.exe /End /TN "KatarinaVPSAgent" | Out-Null}catch{}
        Start-Sleep -Seconds 1
        & schtasks.exe /Run /TN "KatarinaVPSAgent" | Out-Null
        if($LASTEXITCODE -ne 0){throw "Failed to start primary KatarinaVPSAgent task."}

        $hbPath=Join-Path $installRoot "lanes\primary\heartbeat.json"
        $deadline=[DateTime]::UtcNow.AddSeconds(25)
        $hb=$null
        while([DateTime]::UtcNow -lt $deadline) {
            if(Test-Path -LiteralPath $hbPath -PathType Leaf) {
                try{
                    $candidate=Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
                    if([string]$candidate.agent_version -match '^1\.(3|4)\.'){$hb=$candidate;break}
                }catch{}
            }
            Start-Sleep -Seconds 2
        }
        if($null -eq $hb){throw "Primary lane did not return with Control Plane v2 agent within 25 seconds."}

        Write-Json (Join-Path $OutputDir "control_primary_restart.json") ([ordered]@{
            schema_version=1
            proof_type="KATARINA_CONTROL_PRIMARY_RESTART"
            terminated_process_ids=$terminated
            heartbeat_path=$hbPath
            agent_version=[string]$hb.agent_version
            phase=[string]$hb.phase
            updated_utc=[string]$hb.updated_utc
            result="PASS"
        })
        break
    }

    "WORKSPACE_CONTROL_STATUS" {
        $installRoot="C:\KatarinaVPSAgent"
        $defs=@(
            [pscustomobject]@{lane="primary";task="KatarinaVPSAgent";config="agent.json"},
            [pscustomobject]@{lane="recovery";task="KatarinaControlRecovery";config="agent-recovery.json"},
            [pscustomobject]@{lane="worker01";task="KatarinaControlWorker01";config="agent-worker01.json"},
            [pscustomobject]@{lane="worker02";task="KatarinaControlWorker02";config="agent-worker02.json"}
        )
        $resourceProfile=""
        $primaryConfigPath=Join-Path $installRoot "agent.json"
        if(Test-Path -LiteralPath $primaryConfigPath -PathType Leaf) {
            try {
                $primaryCfg=Get-Content -LiteralPath $primaryConfigPath -Raw | ConvertFrom-Json
                if($null -ne $primaryCfg.PSObject.Properties["resource_profile"]) {
                    $resourceProfile=([string]$primaryCfg.resource_profile).ToUpperInvariant()
                }
            } catch {}
        }
        $guardedProfile=($resourceProfile -eq "LEGACY_LOW_MEMORY_GUARDED")
        $expectedLanes=@("primary")
        if($resourceProfile -eq "LEGACY_LOW_MEMORY_BALANCED") {
            $watchdogConfigPath=Join-Path $installRoot "watchdog_lanes.json"
            if(Test-Path -LiteralPath $watchdogConfigPath -PathType Leaf) {
                try {
                    $watchdogCfg=Get-Content -LiteralPath $watchdogConfigPath -Raw | ConvertFrom-Json
                    $configured=@($watchdogCfg.lanes | ForEach-Object { ([string]$_.lane).ToLowerInvariant() } | Where-Object { $_ })
                    if($configured.Count -gt 0) {
                        $expectedLanes=@($configured | Sort-Object -Unique)
                    }
                } catch {}
            }
        } elseif($guardedProfile) {
            $expectedLanes=@("primary")
        } elseif($resourceProfile -ne "LEGACY_LOW_MEMORY_SEQUENTIAL") {
            $expectedLanes=@("primary","recovery","worker01","worker02")
        }
        $primaryOnly=($expectedLanes.Count -eq 1 -and $expectedLanes -contains "primary")

        $records=@()
        $allHealthy=$true
        foreach($d in $defs) {
            $configPath=Join-Path $installRoot $d.config
            $hbPath=Join-Path $installRoot ("lanes\"+$d.lane+"\heartbeat.json")
            $hb=$null
            $age=$null
            if(Test-Path -LiteralPath $hbPath -PathType Leaf) {
                try{
                    $hb=Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
                    $updated=[DateTime]::Parse([string]$hb.updated_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
                    $age=[math]::Round(([DateTime]::UtcNow-$updated).TotalSeconds,1)
                }catch{}
            }

            $processCount=0
            try {
                $processCount=@(
                    Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.CommandLine -and
                        $_.CommandLine.IndexOf("KatarinaVpsAgent.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                        $_.CommandLine.IndexOf($configPath,[StringComparison]::OrdinalIgnoreCase) -ge 0
                    }
                ).Count
            } catch {}

            $expected=($expectedLanes -contains ([string]$d.lane).ToLowerInvariant())
            $healthy=($null -ne $hb -and $null -ne $age -and $age -lt 60 -and $processCount -eq 1)
            $stateOk=$(if($expected){$healthy}else{$processCount -eq 0})
            if(!$stateOk){$allHealthy=$false}
            $records += [ordered]@{
                lane=[string]$d.lane
                task=[string]$d.task
                config=$configPath
                expected=$expected
                process_count=$processCount
                agent_version=$(if($hb){[string]$hb.agent_version}else{$null})
                phase=$(if($hb){[string]$hb.phase}else{$null})
                heartbeat_age_seconds=$age
                healthy=$healthy
                state_ok=$stateOk
            }
        }

        $guardianRecord=$null
        $guardianSelfTest=$null
        if($guardedProfile) {
            $guardianHeartbeatPath=Join-Path $installRoot "guardian\heartbeat.json"
            $guardianHb=$null
            $guardianAge=$null
            if(Test-Path -LiteralPath $guardianHeartbeatPath -PathType Leaf) {
                try {
                    $guardianHb=Get-Content -LiteralPath $guardianHeartbeatPath -Raw | ConvertFrom-Json
                    $guardianUpdated=[DateTime]::Parse(
                        [string]$guardianHb.updated_utc,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::AssumeUniversal
                    ).ToUniversalTime()
                    $guardianAge=[math]::Round(([DateTime]::UtcNow-$guardianUpdated).TotalSeconds,1)
                } catch {}
            }

            $guardianProcessCount=0
            try {
                $guardianProcessCount=@(
                    Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.CommandLine -and
                        $_.CommandLine.IndexOf("KatarinaControlGuardian.ps1",[StringComparison]::OrdinalIgnoreCase) -ge 0
                    }
                ).Count
            } catch {}

            $guardianHealthy=($null -ne $guardianHb -and $null -ne $guardianAge -and $guardianAge -lt 30 -and $guardianProcessCount -eq 1)
            if(-not $guardianHealthy){$allHealthy=$false}
            $guardianRecord=[ordered]@{
                expected=$true
                process_count=$guardianProcessCount
                guardian_version=$(if($guardianHb){[string]$guardianHb.guardian_version}else{$null})
                phase=$(if($guardianHb){[string]$guardianHb.phase}else{$null})
                reason=$(if($guardianHb){[string]$guardianHb.reason}else{$null})
                heartbeat_age_seconds=$guardianAge
                primary_process_id=$(if($guardianHb){$guardianHb.primary_process_id}else{$null})
                primary_agent_version=$(if($guardianHb){[string]$guardianHb.primary_agent_version}else{$null})
                healthy=$guardianHealthy
            }

            $guardianSelfTestPath=Join-Path $installRoot "guardian\selftest_result.json"
            if(Test-Path -LiteralPath $guardianSelfTestPath -PathType Leaf) {
                try { $guardianSelfTest=Get-Content -LiteralPath $guardianSelfTestPath -Raw | ConvertFrom-Json } catch {}
            }
        }

        Write-Json (Join-Path $OutputDir "control_plane_status.json") ([ordered]@{
            schema_version=1
            proof_type="KATARINA_CONTROL_PLANE_STATUS"
            resource_profile=$resourceProfile
            primary_only=$primaryOnly
            expected_lanes=$expectedLanes
            lanes=$records
            guardian=$guardianRecord
            guardian_selftest=$guardianSelfTest
            supervisor_log_exists=(Test-Path -LiteralPath (Join-Path $installRoot "control_supervisor.log") -PathType Leaf)
            generated_utc=[DateTime]::UtcNow.ToString("o")
            result=$(if($allHealthy){"PASS"}else{"FAIL"})
        })
        if(!$allHealthy){throw "Control Plane v2 status is not fully healthy."}
        break
    }

    "WORKSPACE_AGENT_SELF_HEAL_INSTALL" {
        $installRoot="C:\KatarinaVPSAgent"
        $agentTask="KatarinaVPSAgent"
        $watchdogTask="KatarinaVPSAgentWatchdog"
        $agentSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgent.ps1"
        $watchdogSource=Join-Path $RepoRoot "scripts\vps\legacy\KatarinaVpsAgentWatchdog.ps1"
        $configPath=Join-Path $installRoot "agent.json"
        $tokenPath=Join-Path $installRoot "token.bin"

        if(!(Test-Path -LiteralPath $agentSource -PathType Leaf)) { throw "Updated VPS agent source is missing." }
        if(!(Test-Path -LiteralPath $watchdogSource -PathType Leaf)) { throw "VPS watchdog source is missing." }
        if(!(Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Existing VPS agent config is missing." }
        if(!(Test-Path -LiteralPath $tokenPath -PathType Leaf)) { throw "Existing encrypted VPS token is missing." }

        New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
        Copy-Item -LiteralPath $agentSource -Destination (Join-Path $installRoot "KatarinaVpsAgent.ps1") -Force
        Copy-Item -LiteralPath $watchdogSource -Destination (Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1") -Force

        $watchdogCommand='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installRoot "KatarinaVpsAgentWatchdog.ps1") + '" -InstallRoot "' + $installRoot + '"'
        & schtasks.exe /Create /F /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /TN $watchdogTask /TR $watchdogCommand | Out-Null
        if($LASTEXITCODE -ne 0) { throw "Failed to register Katarina VPS watchdog scheduled task." }

        # Do not run the watchdog immediately from the legacy agent. The old
        # parent process is still uploading this task's evidence. The MINUTE
        # schedule activates it on the next tick, after this request completes.
        Write-Json (Join-Path $OutputDir "agent_self_heal_install.json") ([ordered]@{
            schema_version=1
            stage="07"
            proof_type="VPS_AGENT_SELF_HEAL_INSTALL"
            install_root=$installRoot
            agent_task=$agentTask
            watchdog_task=$watchdogTask
            watchdog_interval_minutes=1
            watchdog_activation="NEXT_SCHEDULE_TICK"
            heartbeat_stale_seconds=75
            child_task_hard_timeout_seconds=180
            restart_cooldown_seconds=120
            token_reused=$true
            installed_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
        break
    }

    "WORKSPACE_DEPENDENCY_VERIFY" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }

        $python=Join-Path $Runtime "python\python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Canonical Katarina Python runtime is missing." }

        $verifyScript=Join-Path $OutputDir "dependency_verify.py"
        @'
import datetime
import json
import pathlib
import sys
import zmq
import tornado

python_dir = pathlib.Path(sys.executable).resolve().parent
pth_path = python_dir / "python312._pth"
pth_lines = pth_path.read_text(encoding="ascii").splitlines() if pth_path.exists() else []

payload = {
    "schema_version": 1,
    "stage": "07",
    "proof_type": "VPS_PYTHON_DEPENDENCY_VERIFICATION",
    "python_executable": str(pathlib.Path(sys.executable).resolve()),
    "python_version": sys.version.split()[0],
    "pyzmq_version": zmq.__version__,
    "libzmq_version": zmq.zmq_version(),
    "zmq_module": str(pathlib.Path(zmq.__file__).resolve()),
    "tornado_version": tornado.version,
    "tornado_module": str(pathlib.Path(tornado.__file__).resolve()),
    "sys_path": list(sys.path),
    "python_pth": pth_lines,
    "verified_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "result": "PASS",
}
print(json.dumps(payload, sort_keys=True))
'@ | Set-Content -LiteralPath $verifyScript -Encoding ASCII

        $verifyOut=Join-Path $OutputDir "dependency_verify_stdout.txt"
        $verifyErr=Join-Path $OutputDir "dependency_verify_stderr.txt"
        $proc=Start-Process -FilePath $python -ArgumentList @($verifyScript) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $verifyOut -RedirectStandardError $verifyErr
        if($proc.ExitCode -ne 0) { throw "Katarina dependency verification process failed." }

        $raw=(Get-Content -LiteralPath $verifyOut -Raw).Trim()
        if([string]::IsNullOrWhiteSpace($raw)) { throw "Katarina dependency verification produced no output." }
        $probe=$raw | ConvertFrom-Json

        $expectedPython=(Resolve-Path -LiteralPath $python).Path
        if(![string]::Equals([string]$probe.python_executable,$expectedPython,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Dependency verification used the wrong Python interpreter."
        }

        $runtimePrefix=((Resolve-Path -LiteralPath (Join-Path $Runtime "python")).Path.TrimEnd("\") + "\")
        foreach($modulePath in @([string]$probe.zmq_module,[string]$probe.tornado_module)) {
            if([string]::IsNullOrWhiteSpace($modulePath) -or !$modulePath.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
                throw "Dependency resolved outside Katarina runtime: $modulePath"
            }
        }
        if([string]$probe.pyzmq_version -ne "27.2.0") { throw "Unexpected pyzmq version: $($probe.pyzmq_version)" }
        if([string]$probe.libzmq_version -ne "4.3.5") { throw "Unexpected libzmq version: $($probe.libzmq_version)" }

        $pth=Join-Path (Join-Path $Runtime "python") "python312._pth"
        $pthLines=$(if(Test-Path -LiteralPath $pth -PathType Leaf){@(Get-Content -LiteralPath $pth)}else{@()})
        foreach($requiredPath in @("Lib\site-packages","..\..\workspace","..\..\workspace\src","import site")) {
            if(@($pthLines | Where-Object { ([string]$_).Trim() -ieq $requiredPath }).Count -eq 0) {
                throw "python312._pth missing required entry: $requiredPath"
            }
        }

        # The canonical Python probe already emitted valid UTF-8 JSON.
        # Copy it directly so Windows PowerShell 4 never needs to serialize the
        # dependency evidence object (ConvertTo-Json can fail on this legacy host).
        Copy-Item -LiteralPath $verifyOut -Destination (Join-Path $OutputDir "dependency_verification.json") -Force
        break
    }

    "WORKSPACE_RUNTIME_BOOTSTRAP" {
        foreach($dir in @($WorkspaceRoot,$Runtime,$Metadata,$Logs)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $pythonDir=Join-Path $Runtime "python"
        $packagesDir=Join-Path $Runtime "packages"
        $downloadDir=Join-Path $Runtime "downloads"
        New-Item -ItemType Directory -Force -Path $downloadDir,$packagesDir | Out-Null

        $pythonUrl="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
        $pythonMd5="fe8ef205f2e9c3ba44d0cf9954e1abd3"
        $pythonZip=Join-Path $downloadDir "python-3.12.10-embed-amd64.zip"
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZip -UseBasicParsing
        $actualMd5=(Get-FileHash -LiteralPath $pythonZip -Algorithm MD5).Hash.ToLowerInvariant()
        if($actualMd5 -ne $pythonMd5) { throw "Python embeddable checksum mismatch." }

        if(Test-Path -LiteralPath $pythonDir) { Remove-Item -LiteralPath $pythonDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($pythonZip,$pythonDir)

        $pth=Join-Path $pythonDir "python312._pth"
        if(!(Test-Path -LiteralPath $pth -PathType Leaf)) { throw "Python embedded _pth file missing." }
        @(
            "python312.zip",
            ".",
            $packagesDir,
            $Workspace,
            (Join-Path $Workspace "src"),
            "import site"
        ) | Set-Content -LiteralPath $pth -Encoding ASCII

        $pypi=Invoke-RestMethod -Method Get -Uri "https://pypi.org/pypi/pyzmq/25.1.1/json"
        $wheelName="pyzmq-25.1.1-cp312-cp312-win_amd64.whl"
        $expectedWheelSha256="eadbefd5e92ef8a345f0525b5cfd01cf4e4cc651a2cffb8f23c0dd184975d787"
        $wheelRecord=@($pypi.urls | Where-Object { $_.filename -eq $wheelName }) | Select-Object -First 1
        if($null -eq $wheelRecord) { throw "Pinned pyzmq wheel is missing from PyPI metadata." }
        if(([string]$wheelRecord.digests.sha256).ToLowerInvariant() -ne $expectedWheelSha256) {
            throw "Pinned pyzmq metadata SHA-256 mismatch."
        }
        $wheelUri=[Uri]([string]$wheelRecord.url)
        if($wheelUri.Scheme -ne "https" -or $wheelUri.Host -ne "files.pythonhosted.org") {
            throw "Pinned pyzmq download host is not allowlisted."
        }

        $wheel=Join-Path $downloadDir $wheelName
        Invoke-WebRequest -Uri $wheelUri.AbsoluteUri -OutFile $wheel -UseBasicParsing
        $actualWheelSha256=(Get-FileHash -LiteralPath $wheel -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actualWheelSha256 -ne $expectedWheelSha256) { throw "Downloaded pyzmq wheel SHA-256 mismatch." }

        if(Test-Path -LiteralPath $packagesDir) { Remove-Item -LiteralPath $packagesDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $packagesDir | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($wheel,$packagesDir)

        $pythonExe=Join-Path $pythonDir "python.exe"
        if(!(Test-Path -LiteralPath $pythonExe -PathType Leaf)) { throw "Portable Python executable missing." }

        $probeOut=Join-Path $OutputDir "python_runtime_probe.txt"
        $psi=New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName=$pythonExe
        $psi.Arguments='-c "import sys,zmq; print(sys.version); print(zmq.__version__); print(sys.executable)"'
        $psi.WorkingDirectory=$Workspace
        $psi.UseShellExecute=$false
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $proc=New-Object System.Diagnostics.Process
        $proc.StartInfo=$psi
        [void]$proc.Start()
        $probeStdout=$proc.StandardOutput.ReadToEnd()
        $probeStderr=$proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        ($probeStdout+[Environment]::NewLine+$probeStderr) | Set-Content -LiteralPath $probeOut -Encoding UTF8
        if($proc.ExitCode -ne 0) { throw "Portable Python/pyzmq probe failed." }

        Write-Json (Join-Path $Metadata "runtime.json") ([ordered]@{
            schema_version=1
            python_version="3.12.10"
            python_source=$pythonUrl
            python_md5=$actualMd5
            pyzmq_version="25.1.1"
            pyzmq_sha256=$actualWheelSha256
            installed_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
    }

    "WORKSPACE_MT5_COMPILE" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }

        $terminalDataPath=[string]$request.args.terminal_data_path
        $metaEditorPath=[string]$request.args.metaeditor_path
        if([string]::IsNullOrWhiteSpace($terminalDataPath) -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
            throw "terminal_data_path is required for WORKSPACE_MT5_COMPILE."
        }
        if([string]::IsNullOrWhiteSpace($metaEditorPath) -or !(Test-Path -LiteralPath $metaEditorPath -PathType Leaf)) {
            throw "metaeditor_path is required for WORKSPACE_MT5_COMPILE."
        }

        $includeSource=Join-Path $Workspace "mt5\Include\Katarina"
        $includeDest=Join-Path $terminalDataPath "MQL5\Include\Katarina"
        $expertsSource=Join-Path $Workspace "mt5\Experts"
        $testsSource=Join-Path $Workspace "mt5\Tests"
        $expertsDest=Join-Path $terminalDataPath "MQL5\Experts"
        $scriptsDest=Join-Path $terminalDataPath "MQL5\Scripts"
        $mqlRoot=Join-Path $terminalDataPath "MQL5"

        # Stage the exact ZeroMQ MQL5 dependency pinned by Stage-07 CI.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zmqCommit="f332ee903fb8f27cbf28a8169824b8130e2aaab2"
        $zmqRuntime=Join-Path $Runtime ("mql5-zmq\"+$zmqCommit)
        $zmqMarker=Join-Path $zmqRuntime "Include\Zmq\Zmq.mqh"
        if(!(Test-Path -LiteralPath $zmqMarker -PathType Leaf)) {
            $downloadDir=Join-Path $Runtime "downloads"
            New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
            $archive=Join-Path $downloadDir ("mql5-zmq-"+$zmqCommit+".zip")
            $archiveUrl="https://github.com/coke5151/mql5-zmq/archive/"+$zmqCommit+".zip"
            Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing
            if(!(Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Pinned MQL5 ZeroMQ archive download failed." }

            $extract=Join-Path $Runtime ("mql5-zmq-extract-"+$zmqCommit)
            if(Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $extract | Out-Null
            [IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
            $root=Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
            if($null -eq $root) { throw "Pinned MQL5 ZeroMQ archive extraction failed." }

            if(Test-Path -LiteralPath $zmqRuntime) { Remove-Item -LiteralPath $zmqRuntime -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $zmqRuntime | Out-Null
            Copy-Item -Path (Join-Path $root.FullName "*") -Destination $zmqRuntime -Recurse -Force
            Remove-Item -LiteralPath $extract -Recurse -Force
        }

        $zmqInclude=Join-Path $mqlRoot "Include\Zmq"
        $mqlLangInclude=Join-Path $mqlRoot "Include\Mql\Lang"
        $librariesDest=Join-Path $mqlRoot "Libraries"
        New-Item -ItemType Directory -Force -Path $zmqInclude,$mqlLangInclude,$librariesDest | Out-Null
        Copy-Item -Path (Join-Path $zmqRuntime "Include\Zmq\*.mqh") -Destination $zmqInclude -Force
        Copy-Item -Path (Join-Path $zmqRuntime "Include\Mql\Lang\*.mqh") -Destination $mqlLangInclude -Force
        Copy-Item -LiteralPath (Join-Path $zmqRuntime "Library\libzmq.dll") -Destination $librariesDest -Force
        Copy-Item -LiteralPath (Join-Path $zmqRuntime "Library\libsodium.dll") -Destination $librariesDest -Force

        if(!(Test-Path -LiteralPath (Join-Path $zmqInclude "Zmq.mqh") -PathType Leaf)) { throw "Pinned MQL5 ZeroMQ include staging failed." }
        if(!(Test-Path -LiteralPath $includeSource -PathType Container)) { throw "Workspace Katarina include tree missing." }
        New-Item -ItemType Directory -Force -Path $includeDest,$expertsDest,$scriptsDest | Out-Null
        Copy-Item -Path (Join-Path $includeSource "*") -Destination $includeDest -Recurse -Force

        $targets=@()
        $stage07Ea=Join-Path $expertsSource "KatarinaBridgeStage07EA.mq5"
        if(!(Test-Path -LiteralPath $stage07Ea -PathType Leaf)) { throw "Stage-07 bridge EA source missing." }
        $eaDest=Join-Path $expertsDest "KatarinaBridgeStage07EA.mq5"
        Copy-Item -LiteralPath $stage07Ea -Destination $eaDest -Force
        $targets += [pscustomobject]@{ name="KatarinaBridgeStage07EA"; source=$eaDest; kind="EXPERT" }

        foreach($test in @(Get-ChildItem -LiteralPath $testsSource -Filter "KatarinaStage07*.mq5" -File | Sort-Object Name)) {
            $dest=Join-Path $scriptsDest $test.Name
            Copy-Item -LiteralPath $test.FullName -Destination $dest -Force
            $targets += [pscustomobject]@{ name=$test.BaseName; source=$dest; kind="SCRIPT" }
        }

        $requestedTargetNames=@()
        if($null -ne $request.args.PSObject.Properties["target_names"] -and
           $null -ne $request.args.target_names) {
            foreach($name in @($request.args.target_names)) {
                if(![string]::IsNullOrWhiteSpace([string]$name)) {
                    $requestedTargetNames += [string]$name
                }
            }
        }

        if($requestedTargetNames.Count -gt 0) {
            $allTargets=@($targets)
            $targets=@($allTargets | Where-Object { $requestedTargetNames -contains [string]$_.name })
            if($targets.Count -ne $requestedTargetNames.Count) {
                $resolved=@($targets | ForEach-Object { [string]$_.name })
                $missing=@($requestedTargetNames | Where-Object { $resolved -notcontains $_ })
                throw ("Unknown Stage-07 compile target(s): " + ($missing -join ","))
            }
        } elseif($targets.Count -lt 2) {
            throw "Stage-07 compile target discovery is incomplete."
        }

        if($targets.Count -lt 1) { throw "No Stage-07 compile targets selected." }

        $records=@()
        $failed=$false
        foreach($target in $targets) {
            $ex5=[IO.Path]::ChangeExtension([string]$target.source,".ex5")
            if(Test-Path -LiteralPath $ex5) { Remove-Item -LiteralPath $ex5 -Force }
            $log=Join-Path $OutputDir ([string]$target.name + ".compile.log")
            if(Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

            $compileArgs=@(
                "/compile:`"$([string]$target.source)`"",
                "/inc:`"$mqlRoot`"",
                "/log:`"$log`""
            )
            $proc=Start-Process -FilePath $metaEditorPath -ArgumentList $compileArgs -Wait -PassThru
            $logText=""
            if(Test-Path -LiteralPath $log) { $logText=Get-Content -LiteralPath $log -Raw }
            $pass=(Test-Path -LiteralPath $log -PathType Leaf) -and
                  (Test-Path -LiteralPath $ex5 -PathType Leaf) -and
                  ($logText -match "0 errors, 0 warnings")
            if(!$pass) { $failed=$true }

            $records += [ordered]@{
                target=[string]$target.name
                kind=[string]$target.kind
                process_exit_code=[int]$proc.ExitCode
                compile_result=$(if($pass){"PASS_0_ERRORS_0_WARNINGS"}else{"FAIL"})
                ex5_exists=(Test-Path -LiteralPath $ex5 -PathType Leaf)
                ex5_sha256=$(if(Test-Path -LiteralPath $ex5 -PathType Leaf){(Get-FileHash -LiteralPath $ex5 -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null})
                log_file=[IO.Path]::GetFileName($log)
            }
        }

        $compileEvidence=[ordered]@{
            schema_version=1
            stage="07"
            proof_type="VPS_WORKSPACE_MT5_COMPILE"
            workspace_root=$Workspace
            terminal_data_path=$terminalDataPath
            metaeditor_path=$metaEditorPath
            mql5_zmq_commit=$zmqCommit
            mql5_zmq_root=$zmqRuntime
            target_count=$records.Count
            requested_target_names=$requestedTargetNames
            targets=$records
            generated_utc=[DateTime]::UtcNow.ToString("o")
            result=$(if($failed){"FAIL"}else{"PASS_0_ERRORS_0_WARNINGS"})
        }
        Write-Json (Join-Path $OutputDir "workspace_mt5_compile.json") $compileEvidence
        if($failed) { throw "One or more Stage-07 workspace MT5 targets failed strict compilation." }
    }

    "WORKSPACE_MT5_RUNTIME_SMOKE" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }

        $terminalPath=[string]$request.args.terminal_path
        $terminalDataPath=[string]$request.args.terminal_data_path
        if([string]::IsNullOrWhiteSpace($terminalPath) -or !(Test-Path -LiteralPath $terminalPath -PathType Leaf)) {
            throw "terminal_path is required for WORKSPACE_MT5_RUNTIME_SMOKE."
        }
        if([string]::IsNullOrWhiteSpace($terminalDataPath) -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
            throw "terminal_data_path is required for WORKSPACE_MT5_RUNTIME_SMOKE."
        }

        $terminalResolved=(Resolve-Path -LiteralPath $terminalPath).Path
        $running=@()
        try {
            $running=@(
                Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ExecutablePath -and
                    [string]::Equals([string]$_.ExecutablePath,$terminalResolved,[StringComparison]::OrdinalIgnoreCase)
                }
            )
        } catch {}
        if($running.Count -gt 0) {
            throw "Target MT5 terminal is already running; refusing headless workspace runtime test."
        }

        $markerPath="\AppData\Roaming\MetaQuotes\Terminal\"
        $markerIndex=$terminalDataPath.IndexOf($markerPath,[StringComparison]::OrdinalIgnoreCase)
        if($markerIndex -le 0) { throw "Unable to derive MT5 user profile from terminal_data_path." }
        $profileRoot=$terminalDataPath.Substring(0,$markerIndex)
        $appDataRoaming=Join-Path $profileRoot "AppData\Roaming"
        $localAppData=Join-Path $profileRoot "AppData\Local"
        $driveRoot=[IO.Path]::GetPathRoot($profileRoot)
        $homeDrive=$driveRoot.TrimEnd("\")
        $homePath=$profileRoot.Substring($driveRoot.Length-1)

        $commonFiles=Join-Path $appDataRoaming "MetaQuotes\Terminal\Common\Files"
        New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null

        function Invoke-WorkspaceMt5Script {
            param(
                [string]$ScriptName,
                [string]$ConfigTag,
                [int]$TimeoutSeconds=90
            )
            $config=Join-Path $OutputDir ("mt5_runtime_"+$ConfigTag+".ini")
            @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Script=$ScriptName
Period=H1
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $config -Encoding ASCII

            $launcher=Join-Path $RepoRoot "scripts\vps\Invoke-KatarinaInteractiveMt5.ps1"
            if(!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
                throw "Safe interactive MT5 launcher is missing."
            }

            $expectedUser=Split-Path -Leaf $profileRoot
            $launchEvidence=Join-Path $OutputDir ("interactive_"+$ConfigTag+".json")
            $launchStdout=Join-Path $OutputDir ("interactive_"+$ConfigTag+"_stdout.txt")
            $launchStderr=Join-Path $OutputDir ("interactive_"+$ConfigTag+"_stderr.txt")
            $launcherArgs=@(
                "-NoProfile",
                "-ExecutionPolicy","Bypass",
                "-File",$launcher,
                "-TerminalPath",$terminalResolved,
                "-ConfigPath",$config,
                "-ExpectedUser",$expectedUser,
                "-TimeoutSeconds",$TimeoutSeconds,
                "-OutputPath",$launchEvidence
            )

            & powershell.exe $launcherArgs 1> $launchStdout 2> $launchStderr
            $launcherExit=$LASTEXITCODE
            if($launcherExit -ne 0 -or !(Test-Path -LiteralPath $launchEvidence -PathType Leaf)) {
                $detail=""
                if(Test-Path -LiteralPath $launchStderr) {
                    $detail=Get-Content -LiteralPath $launchStderr -Raw
                }
                throw "Interactive MT5 launch failed for $ScriptName. $detail"
            }

            $launchResult=Get-Content -LiteralPath $launchEvidence -Raw | ConvertFrom-Json
            Start-Sleep -Milliseconds 700
            return [int]$launchResult.terminal_exit_code
        }

        $records=@()

        $simpleTests=@(
            [pscustomobject]@{
                name="KAT1_CODEC"
                script="KatarinaStage07Kat1CodecTest"
                file="Katarina_Stage07_kat1_codec_result.txt"
                required=@("stage=07","vectors=13","failures=0","result=PASS")
            },
            [pscustomobject]@{
                name="NATIVE_ACCOUNT"
                script="KatarinaStage07NativeAccountRecordTest"
                file="Katarina_Stage07_native_account_record_result.txt"
                required=@("stage=07","result=PASS")
            },
            [pscustomobject]@{
                name="NATIVE_STATE"
                script="KatarinaStage07NativeStateRecordsTest"
                file="Katarina_Stage07_native_state_records_result.txt"
                required=@("stage=07","result=PASS")
            }
        )

        foreach($test in $simpleTests) {
            $evidence=Join-Path $commonFiles ([string]$test.file)
            Remove-Item -LiteralPath $evidence -Force -ErrorAction SilentlyContinue
            $exitCode=Invoke-WorkspaceMt5Script -ScriptName ([string]$test.script) -ConfigTag ([string]$test.name)
            if(!(Test-Path -LiteralPath $evidence -PathType Leaf)) {
                throw "Runtime evidence missing for $($test.name)."
            }
            $evidenceText=Get-Content -LiteralPath $evidence -Raw
            foreach($required in @($test.required)) {
                if($evidenceText -notmatch [regex]::Escape([string]$required)) {
                    throw "Runtime evidence for $($test.name) missing required marker: $required"
                }
            }
            $dest=Join-Path $OutputDir ([string]$test.file)
            Copy-Item -LiteralPath $evidence -Destination $dest -Force
            $records += [ordered]@{
                test=[string]$test.name
                script=[string]$test.script
                process_exit_code=$exitCode
                evidence=[string]$test.file
                evidence_sha256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
                result="PASS"
            }
        }

        $sequenceMarker=Join-Path $commonFiles "Katarina_Stage07_wire_sequence_phase.txt"
        $sequenceEvidence=Join-Path $commonFiles "Katarina_Stage07_wire_sequence_result.txt"
        Remove-Item -LiteralPath $sequenceMarker,$sequenceEvidence -Force -ErrorAction SilentlyContinue

        $phase1Exit=Invoke-WorkspaceMt5Script -ScriptName "KatarinaStage07WireSequenceTest" -ConfigTag "WIRE_SEQUENCE_PHASE1"
        if(!(Test-Path -LiteralPath $sequenceEvidence -PathType Leaf) -or
           !(Test-Path -LiteralPath $sequenceMarker -PathType Leaf)) {
            throw "Wire-sequence phase-1 evidence or marker missing."
        }
        $phase1Text=Get-Content -LiteralPath $sequenceEvidence -Raw
        if($phase1Text -notmatch "result=PHASE1_PASS") {
            throw "Wire-sequence phase 1 did not pass."
        }

        Remove-Item -LiteralPath $sequenceEvidence -Force
        $phase2Exit=Invoke-WorkspaceMt5Script -ScriptName "KatarinaStage07WireSequenceTest" -ConfigTag "WIRE_SEQUENCE_PHASE2"
        if(!(Test-Path -LiteralPath $sequenceEvidence -PathType Leaf)) {
            throw "Wire-sequence phase-2 evidence missing."
        }
        $phase2Text=Get-Content -LiteralPath $sequenceEvidence -Raw
        foreach($required in @("result=PASS","observed_last=2","allocated_next=3")) {
            if($phase2Text -notmatch [regex]::Escape($required)) {
                throw "Wire-sequence phase-2 evidence missing marker: $required"
            }
        }
        if(Test-Path -LiteralPath $sequenceMarker) {
            throw "Wire-sequence phase marker was not cleaned after phase 2."
        }

        $sequenceDest=Join-Path $OutputDir "Katarina_Stage07_wire_sequence_result.txt"
        Copy-Item -LiteralPath $sequenceEvidence -Destination $sequenceDest -Force
        $records += [ordered]@{
            test="WIRE_SEQUENCE_RESTART"
            script="KatarinaStage07WireSequenceTest"
            phase1_exit_code=$phase1Exit
            phase2_exit_code=$phase2Exit
            evidence="Katarina_Stage07_wire_sequence_result.txt"
            evidence_sha256=(Get-FileHash -LiteralPath $sequenceDest -Algorithm SHA256).Hash.ToLowerInvariant()
            observed_last=2
            allocated_next=3
            result="PASS"
        }

        Write-Json (Join-Path $OutputDir "workspace_mt5_runtime_smoke.json") ([ordered]@{
            schema_version=1
            stage="07"
            proof_type="VPS_WORKSPACE_MT5_RUNTIME_SMOKE"
            host=(Get-WmiObject Win32_OperatingSystem).Caption
            terminal_path=$terminalResolved
            terminal_data_path=$terminalDataPath
            profile_root=$profileRoot
            symbol_policy="TERMINAL_NATIVE_EMPTY_STARTUP_SYMBOL"
            allow_live_trading=$false
            allow_dll_import=$false
            tests=$records
            generated_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
    }

    "WORKSPACE_ZMQ_RUNTIME" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }

        $terminalPath=[string]$request.args.terminal_path
        $terminalDataPath=[string]$request.args.terminal_data_path
        if([string]::IsNullOrWhiteSpace($terminalPath) -or !(Test-Path -LiteralPath $terminalPath -PathType Leaf)) {
            throw "terminal_path is required for WORKSPACE_ZMQ_RUNTIME."
        }
        if([string]::IsNullOrWhiteSpace($terminalDataPath) -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
            throw "terminal_data_path is required for WORKSPACE_ZMQ_RUNTIME."
        }

        $terminalResolved=(Resolve-Path -LiteralPath $terminalPath).Path
        $running=@()
        try {
            $running=@(
                Get-WmiObject Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ExecutablePath -and
                    [string]::Equals([string]$_.ExecutablePath,$terminalResolved,[StringComparison]::OrdinalIgnoreCase)
                }
            )
        } catch {}
        if($running.Count -gt 0) {
            throw "Target MT5 terminal is already running; refusing ZeroMQ runtime test."
        }

        $profileMarker="\AppData\Roaming\MetaQuotes\Terminal\"
        $profileIndex=$terminalDataPath.IndexOf($profileMarker,[StringComparison]::OrdinalIgnoreCase)
        if($profileIndex -le 0) { throw "Unable to derive MT5 user profile from terminal_data_path." }
        $profileRoot=$terminalDataPath.Substring(0,$profileIndex)
        $expectedUser=Split-Path -Leaf $profileRoot
        $appDataRoaming=Join-Path $profileRoot "AppData\Roaming"
        $commonFiles=Join-Path $appDataRoaming "MetaQuotes\Terminal\Common\Files"
        New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null

        $python=Resolve-Exe @((Join-Path $Runtime "python\python.exe"))
        if(!$python) { throw "Portable Python runtime is not available." }

        $mqlLibraries=Join-Path $terminalDataPath "MQL5\Libraries"
        foreach($dllName in @("libzmq.dll","libsodium.dll")) {
            if(!(Test-Path -LiteralPath (Join-Path $mqlLibraries $dllName) -PathType Leaf)) {
                throw "MT5 ZeroMQ DLL missing: $dllName. Run WORKSPACE_MT5_COMPILE first."
            }
        }

        $pythonScript=Join-Path $OutputDir "workspace_zmq_router.py"
        $ready=Join-Path $OutputDir "workspace_zmq_ready.txt"
        $pythonResult=Join-Path $OutputDir "workspace_zmq_python_result.json"
        $pythonStdout=Join-Path $OutputDir "workspace_zmq_python_stdout.txt"
        $pythonStderr=Join-Path $OutputDir "workspace_zmq_python_stderr.txt"
        Remove-Item -LiteralPath $ready,$pythonResult,$pythonStdout,$pythonStderr -Force -ErrorAction SilentlyContinue

        $pythonCode=@'
import json
import pathlib
import time
import zmq

endpoint = "tcp://127.0.0.1:5567"
ready = pathlib.Path(r"__READY__")
result = pathlib.Path(r"__RESULT__")

ctx = zmq.Context.instance()
sock = ctx.socket(zmq.ROUTER)
sock.linger = 0
sock.bind(endpoint)
ready.write_text(endpoint, encoding="utf-8")

poller = zmq.Poller()
poller.register(sock, zmq.POLLIN)
deadline = time.monotonic() + 20.0
payload = None
route = None
ack = None

try:
    while time.monotonic() < deadline:
        events = dict(poller.poll(100))
        if sock not in events:
            continue
        parts = sock.recv_multipart()
        if len(parts) != 2:
            raise RuntimeError(f"expected ROUTER identity+payload, got {len(parts)} parts")
        route, payload = parts
        if payload[:4] != b"KAT1":
            raise RuntimeError("raw payload does not start with KAT1 magic")
        if len(payload) != 104:
            raise RuntimeError(f"unexpected KAT1 payload size: {len(payload)}")

        sock.send_multipart([route, payload])

        ack_deadline = time.monotonic() + 8.0
        while time.monotonic() < ack_deadline:
            ack_events = dict(poller.poll(100))
            if sock not in ack_events:
                continue
            ack_parts = sock.recv_multipart()
            if len(ack_parts) != 2:
                raise RuntimeError(f"expected ACK identity+payload, got {len(ack_parts)} parts")
            ack_route, ack = ack_parts
            if ack_route != route:
                raise RuntimeError("MT5 ACK route identity changed")
            if ack != payload:
                raise RuntimeError("MT5 ACK payload differs from echoed KAT1 frame")
            break

        if ack is None:
            raise RuntimeError("timed out waiting for MT5 echo ACK")
        break

    if payload is None:
        raise RuntimeError("timed out waiting for MT5 DEALER KAT1 frame")

    result.write_text(json.dumps({
        "result": "PASS",
        "endpoint": endpoint,
        "payload_bytes": len(payload),
        "ack_bytes": len(ack),
        "magic": payload[:4].decode("ascii"),
        "route_bytes": len(route),
        "pyzmq": zmq.__version__,
        "libzmq": zmq.zmq_version(),
    }, indent=2), encoding="utf-8")
finally:
    sock.close(0)
'@
        $pythonCode=$pythonCode.Replace("__READY__",$ready.Replace("\","\\")).Replace("__RESULT__",$pythonResult.Replace("\","\\"))
        $pythonCode | Set-Content -LiteralPath $pythonScript -Encoding UTF8

        $peer=Start-Process -FilePath $python -ArgumentList @($pythonScript) -PassThru -NoNewWindow -RedirectStandardOutput $pythonStdout -RedirectStandardError $pythonStderr
        $readyDeadline=[DateTime]::UtcNow.AddSeconds(10)
        while([DateTime]::UtcNow -lt $readyDeadline -and !(Test-Path -LiteralPath $ready -PathType Leaf)) {
            if($peer.HasExited) {
                $detail=""
                if(Test-Path -LiteralPath $pythonStderr) { $detail=Get-Content -LiteralPath $pythonStderr -Raw }
                throw "Python ZeroMQ ROUTER exited before ready. $detail"
            }
            Start-Sleep -Milliseconds 100
        }
        if(!(Test-Path -LiteralPath $ready -PathType Leaf)) {
            try { $peer.Kill() } catch {}
            throw "Python ZeroMQ ROUTER did not become ready."
        }

        $mt5Evidence=Join-Path $commonFiles "Katarina_Stage07_zmq_capability_result.txt"
        Remove-Item -LiteralPath $mt5Evidence -Force -ErrorAction SilentlyContinue

        $config=Join-Path $OutputDir "mt5_runtime_ZMQ_CAPABILITY.ini"
        @"
[Experts]
AllowLiveTrading=0
AllowDllImport=1
Enabled=1
Account=0
Profile=0

[StartUp]
Script=KatarinaStage07ZmqCapability
Period=H1
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $config -Encoding ASCII

        $launcher=Join-Path $RepoRoot "scripts\vps\Invoke-KatarinaInteractiveMt5.ps1"
        if(!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
            try { $peer.Kill() } catch {}
            throw "Safe interactive MT5 launcher is missing."
        }
        $launchEvidence=Join-Path $OutputDir "interactive_ZMQ_CAPABILITY.json"
        $launchStdout=Join-Path $OutputDir "interactive_ZMQ_CAPABILITY_stdout.txt"
        $launchStderr=Join-Path $OutputDir "interactive_ZMQ_CAPABILITY_stderr.txt"
        $launcherArgs=@(
            "-NoProfile",
            "-ExecutionPolicy","Bypass",
            "-File",$launcher,
            "-TerminalPath",$terminalResolved,
            "-ConfigPath",$config,
            "-ExpectedUser",$expectedUser,
            "-TimeoutSeconds",30,
            "-OutputPath",$launchEvidence
        )
        & powershell.exe $launcherArgs 1> $launchStdout 2> $launchStderr
        $launcherExit=$LASTEXITCODE
        if($launcherExit -ne 0) {
            try { $peer.Kill() } catch {}
            $detail=""
            if(Test-Path -LiteralPath $launchStderr) { $detail=Get-Content -LiteralPath $launchStderr -Raw }
            throw "Interactive MT5 ZeroMQ launch failed. $detail"
        }

        if(!$peer.WaitForExit(15000)) {
            try { $peer.Kill() } catch {}
            throw "Python ZeroMQ ROUTER did not terminate after MT5 roundtrip."
        }
        if($peer.ExitCode -ne 0) {
            $detail=""
            if(Test-Path -LiteralPath $pythonStderr) { $detail=Get-Content -LiteralPath $pythonStderr -Raw }
            throw "Python ZeroMQ ROUTER failed. $detail"
        }

        if(!(Test-Path -LiteralPath $mt5Evidence -PathType Leaf)) {
            throw "MT5 ZeroMQ capability evidence missing."
        }
        if(!(Test-Path -LiteralPath $pythonResult -PathType Leaf)) {
            throw "Python ZeroMQ capability evidence missing."
        }

        $mqlText=Get-Content -LiteralPath $mt5Evidence -Raw
        foreach($required in @(
            "stage=07",
            "proof_type=MQL5_ZEROMQ_CAPABILITY",
            "dlls_allowed=1",
            "raw_kat1_bytes=104",
            "result=PASS"
        )) {
            if($mqlText -notmatch [regex]::Escape($required)) {
                throw "MT5 ZeroMQ evidence missing marker: $required"
            }
        }

        $py=Get-Content -LiteralPath $pythonResult -Raw | ConvertFrom-Json
        if([string]$py.result -ne "PASS" -or
           [int]$py.payload_bytes -ne 104 -or
           [int]$py.ack_bytes -ne 104 -or
           [string]$py.magic -ne "KAT1") {
            throw "Python ZeroMQ evidence is invalid."
        }

        $mqlDest=Join-Path $OutputDir "Katarina_Stage07_zmq_capability_result.txt"
        Copy-Item -LiteralPath $mt5Evidence -Destination $mqlDest -Force
        $launchResult=Get-Content -LiteralPath $launchEvidence -Raw | ConvertFrom-Json

        Write-Json (Join-Path $OutputDir "workspace_zmq_runtime.json") ([ordered]@{
            schema_version=1
            stage="07"
            proof_type="VPS_WORKSPACE_ZEROMQ_RUNTIME"
            host=(Get-WmiObject Win32_OperatingSystem).Caption
            topology="PYTHON_ROUTER_MT5_DEALER"
            endpoint=[string]$py.endpoint
            python_executable=$python
            pyzmq=[string]$py.pyzmq
            python_libzmq=[string]$py.libzmq
            mql_zmq_dependency_commit="f332ee903fb8f27cbf28a8169824b8130e2aaab2"
            terminal=$terminalResolved
            session_id=[int]$launchResult.session_id
            session_user=[string]$launchResult.session_user
            symbol_policy="TERMINAL_NATIVE_SYMBOL_FIELD_OMITTED"
            allow_live_trading=$false
            allow_dll_import=$true
            raw_kat1_bytes=104
            echo_ack="PASS"
            mt5_evidence_sha256=(Get-FileHash -LiteralPath $mqlDest -Algorithm SHA256).Hash.ToLowerInvariant()
            python_evidence_sha256=(Get-FileHash -LiteralPath $pythonResult -Algorithm SHA256).Hash.ToLowerInvariant()
            result="PASS"
        })
    }

    "WORKSPACE_PYTHON_BOOTSTRAP" {
        foreach($dir in @($WorkspaceRoot,$Runtime)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $pythonRoot=Join-Path $Runtime "python"
        $zip=Join-Path $Runtime "python-3.12.10-embed-amd64.zip"
        $url="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"

        if(!(Test-Path -LiteralPath $zip -PathType Leaf)) {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        }
        $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if((Get-Item -LiteralPath $zip).Length -ne 8211403) {
            throw "Unexpected Python 3.8.10 embedded package size."
        }

        if(Test-Path -LiteralPath $pythonRoot) { Remove-Item -LiteralPath $pythonRoot -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $pythonRoot | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$pythonRoot)

        $pth=Join-Path $pythonRoot "python312._pth"
        if(Test-Path -LiteralPath $pth) {
            $lines=@(Get-Content -LiteralPath $pth)
            $lines=@($lines | ForEach-Object {
                if($_ -eq "#import site") { "import site" } else { $_ }
            })
            if($lines -notcontains "..\..\workspace") { $lines += "..\..\workspace" }
            $lines | Set-Content -LiteralPath $pth -Encoding ASCII
        }

        $python=Join-Path $pythonRoot "python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Embedded Python executable missing." }
        $version=& $python -c "import sys,ssl; print(sys.version); print(sys.executable); print(ssl.OPENSSL_VERSION)" 2>&1 | Out-String
        if($LASTEXITCODE -ne 0) { throw "Embedded Python smoke test failed: $version" }

        Write-Json (Join-Path $Metadata "python_runtime.json") ([ordered]@{
            schema_version=1
            version="3.12.10"
            architecture="amd64"
            source_url=$url
            package_size=8211403
            sha256=$zipHash
            executable=$python
            smoke_test=$version.Trim()
            verified_utc=[DateTime]::UtcNow.ToString("o")
        })
    }

    "WORKSPACE_INSTALL_PYTHON" {
        $installer=Join-Path $RepoRoot "scripts\vps\Install-KatarinaPortablePython.ps1"
        if(!(Test-Path -LiteralPath $installer -PathType Leaf)){throw "Portable Python installer missing."}
        $runtimeEvidence=Join-Path $OutputDir "python_runtime.json"
        $raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
        if($LASTEXITCODE -ne 0){throw "Portable Python installation failed."}
        ($raw -join [Environment]::NewLine) | Set-Content -LiteralPath $runtimeEvidence -Encoding UTF8
        $probe=Get-Content -LiteralPath $runtimeEvidence -Raw | ConvertFrom-Json
        if([string]$probe.result -ne "PASS"){throw "Portable Python smoke test did not pass."}
    }

    "WORKSPACE_BOOTSTRAP_PYTHON" {
        foreach($dir in @($WorkspaceRoot,$Runtime,$Evidence,$Logs)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $uri="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
        $zip=Join-Path $Runtime "python-3.12.10-embed-amd64.zip"
        $pythonDir=Join-Path $Runtime "python"
        if(Test-Path -LiteralPath $pythonDir) {
            $old=Join-Path $Snapshots ("python_prebootstrap_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
            New-Item -ItemType Directory -Force -Path $Snapshots | Out-Null
            Move-Item -LiteralPath $pythonDir -Destination $old -Force
        }
        Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing
        $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$pythonDir)
        $python=Join-Path $pythonDir "python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Embedded Python extraction did not produce python.exe." }

        $version=& $python -c "import sys,platform; print(sys.version.split()[0]); print(platform.architecture()[0]); print(sys.executable)"
        if($LASTEXITCODE -ne 0) { throw "Embedded Python self-test failed." }
        $lines=@($version)
        if($lines.Count -lt 2 -or $lines[0] -ne "3.12.10" -or $lines[1] -ne "64bit") {
            throw "Unexpected embedded Python identity: $($lines -join ' | ')"
        }
        Write-Json (Join-Path $Evidence "python_runtime.json") ([ordered]@{
            schema_version=1
            source_url=$uri
            archive_sha256=$sha
            version=$lines[0]
            architecture=$lines[1]
            executable=$lines[2]
            verified_utc=[DateTime]::UtcNow.ToString("o")
            result="PASS"
        })
    }

    "WORKSPACE_RUNTIME_INSTALL" {
        foreach($dir in @($WorkspaceRoot,$Runtime,$Logs)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $pythonRoot=Join-Path $Runtime "python"
        $zip=Join-Path $Runtime "python-3.12.10-embed-amd64.zip"
        $url="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
        $expectedMd5="fe8ef205f2e9c3ba44d0cf9954e1abd3"

        if(Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        $actualMd5=(Get-FileHash -LiteralPath $zip -Algorithm MD5).Hash.ToLowerInvariant()
        if($actualMd5 -ne $expectedMd5) {
            Remove-Item -LiteralPath $zip -Force
            throw "Pinned Python runtime checksum mismatch."
        }

        if(Test-Path -LiteralPath $pythonRoot) {
            $backup=Join-Path $Snapshots ("python_preinstall_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
            Move-Item -LiteralPath $pythonRoot -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force -Path $pythonRoot | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$pythonRoot)

        $pth=Join-Path $pythonRoot "python312._pth"
        if(Test-Path -LiteralPath $pth) {
            $pthText=Get-Content -LiteralPath $pth -Raw
            if($pthText -notmatch "(?m)^\.\.\\\.\.\\workspace\s*$") {
                $pthText=$pthText.TrimEnd()+"`r`n..\..\workspace`r`n"
                Set-Content -LiteralPath $pth -Value $pthText -Encoding ASCII
            }
        }

        $python=Join-Path $pythonRoot "python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Embedded Python executable missing after extraction." }
        $version=& $python -c "import sys; print(sys.version)"
        if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($version | Out-String))) {
            throw "Embedded Python failed startup validation."
        }
        Write-Json (Join-Path $Metadata "python_runtime.json") ([ordered]@{
            schema_version=1
            version="3.12.10"
            distribution="CPYTHON_EMBED_AMD64"
            source_url=$url
            official_md5=$expectedMd5
            installed_utc=[DateTime]::UtcNow.ToString("o")
            executable=$python
            startup_validation="PASS"
        })
    }

    "WORKSPACE_BOOTSTRAP_PYTHON" {
        foreach($dir in @($WorkspaceRoot,$Runtime,$Logs)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $pythonDir=Join-Path $Runtime "python"
        $zip=Join-Path $Runtime "python-3.12.10-embed-amd64.zip"
        $url="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"

        if(Test-Path -LiteralPath $pythonDir) { Remove-Item -LiteralPath $pythonDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null

        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$pythonDir)

        $python=Join-Path $pythonDir "python.exe"
        if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Embedded Python extraction did not produce python.exe." }

        $version=& $python -c "import sys,platform; print(sys.version); print(platform.platform())" 2>&1 | Out-String
        if($LASTEXITCODE -ne 0) { throw "Embedded Python smoke test failed: $version" }
        $stdlib=& $python -c "import json,unittest,hashlib,asyncio; print('STDLIB_OK')" 2>&1 | Out-String
        if($LASTEXITCODE -ne 0 -or $stdlib -notmatch "STDLIB_OK") { throw "Embedded Python stdlib smoke test failed." }

        Write-Json (Join-Path $Metadata "python_runtime.json") ([ordered]@{
            schema_version=1
            distribution="CPYTHON_EMBEDDABLE"
            version="3.12.10"
            architecture="amd64"
            source_url=$url
            archive_sha256=$zipHash
            executable=$python
            smoke_test="PASS"
            version_output=$version.Trim()
            installed_utc=[DateTime]::UtcNow.ToString("o")
        })
    }

    "WORKSPACE_TEST" {
        if(!(Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace is not initialized." }
        $python=Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python")
        if(!$python) { throw "Workspace Python runtime is not available yet." }

        $runner=Join-Path $OutputDir "workspace_test_runner.py"
        $workspacePy=$Workspace.Replace("\","\\")
        @"
import pathlib
import sys
import unittest

root = pathlib.Path(r"$workspacePy")
sys.path.insert(0, str(root))
sys.path.insert(0, str(root / "src"))

names = [
    "tests.unit.transport.test_stage07_communication",
    "tests.unit.transport.test_stage07_stage06_contract",
]
suite = unittest.defaultTestLoader.loadTestsFromNames(names)
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
"@ | Set-Content -LiteralPath $runner -Encoding ASCII

        $stdout=Join-Path $OutputDir "workspace_test_stdout.txt"
        $stderr=Join-Path $OutputDir "workspace_test_stderr.txt"
        $p=Start-Process -FilePath $python -ArgumentList @($runner) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if($p.ExitCode -ne 0) { throw "Workspace tests failed." }
    }

    default { throw "Unsupported workspace mode: $mode" }
}

$manifest=Build-Manifest
Write-Json (Join-Path $Metadata "manifest.json") ([ordered]@{
    schema_version=1
    generated_utc=[DateTime]::UtcNow.ToString("o")
    file_count=$manifest.Count
    files=$manifest
})
Write-Json (Join-Path $OutputDir "workspace_status.json") ([ordered]@{
    schema_version=1
    mode=$mode
    root=$WorkspaceRoot
    workspace=$Workspace
    file_count=$manifest.Count
    python_runtime=(Resolve-Exe @((Join-Path $Runtime "python\python.exe"),"python.exe","python"))
    result="PASS"
})
