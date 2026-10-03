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

        "STAGE06_CLEARANCE" {
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
