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

            $python = Resolve-Executable @("python.exe","python")
            $git = Resolve-Executable @("git.exe","git")
            $metaeditor = Resolve-Executable @(
                (Get-ArgValue $request.args "metaeditor_path" ""),
                "metaeditor64.exe"
            )
            $terminal = Resolve-Executable @(
                (Get-ArgValue $request.args "terminal_path" ""),
                "terminal64.exe"
            )

            $inventory = [ordered]@{
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
                python = $python
                git = $git
                metaeditor = $metaeditor
                terminal = $terminal
                generated_utc = [DateTime]::UtcNow.ToString("o")
            }
            Write-JsonFile (Join-Path $OutputDir "host_inventory.json") $inventory
            "HOST_INVENTORY PASS" | Set-Content $stdoutPath -Encoding UTF8
            "" | Set-Content $stderrPath -Encoding UTF8
            $details["inventory"] = "host_inventory.json"
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

            $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"-TerminalDataPath",$terminalDataPath) -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            if ($resultCode -ne 0) { throw "Stage-06 host check failed." }
        }

        "STAGE06_COMPILE_PROOF" {
            $terminalDataPath = Get-ArgValue $request.args "terminal_data_path" ""
            $metaEditorPath = Get-ArgValue $request.args "metaeditor_path" ""
            if (-not $terminalDataPath) {
                throw "terminal_data_path is required for STAGE06_COMPILE_PROOF."
            }

            $script = Join-Path $RepoRoot "scripts\mt5\verify_stage06_modern_windows.ps1"
            if (!(Test-Path $script)) { throw "Stage-06 verifier missing." }

            $invoke = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"-TerminalDataPath",$terminalDataPath)
            if ($metaEditorPath) { $invoke += @("-MetaEditorPath",$metaEditorPath) }

            $resultCode = Invoke-Captured -FilePath "powershell.exe" -ArgumentList $invoke -StdoutPath $stdoutPath -StderrPath $stderrPath -WorkingDirectory $RepoRoot
            if ($resultCode -ne 0) { throw "Stage-06 compile proof failed." }

            $compileEvidence = Join-Path $RepoRoot "build\mt5\stage06_compile_evidence.json"
            if (Test-Path $compileEvidence) {
                Copy-Item $compileEvidence (Join-Path $OutputDir "stage06_compile_evidence.json") -Force
            }
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
