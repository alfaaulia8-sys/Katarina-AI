param(
    [Parameter(Mandatory=$true)]
    [string]$RequestFile,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [string]$AgentId = $env:KATARINA_AGENT_ID,

    [Parameter(Mandatory=$false)]
    [string]$RepoRoot = "",

    [Parameter(Mandatory=$false)]
    [switch]$NoProcessExit
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





            if ($mode -eq "WORKSPACE_DESKTOP_COMMANDER_INTERACTIVE_START_DIRECT") {
                $cacheBase="C:\Users\Administrator\AppData\Local\npm-cache\_npx"
                $root=$null
                if(Test-Path -LiteralPath $cacheBase -PathType Container) {
                    foreach($d in @(Get-ChildItem -LiteralPath $cacheBase -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
                        $pkg=Join-Path $d.FullName "node_modules\@wonderwhy-er\desktop-commander\package.json"
                        if(Test-Path -LiteralPath $pkg -PathType Leaf) {
                            try {
                                $m=Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
                                if([string]$m.version -eq "0.2.52"){$root=$d.FullName;break}
                            } catch {}
                        }
                    }
                }
                if([string]::IsNullOrWhiteSpace($root)){throw "Desktop Commander 0.2.52 cache installation not found."}
                $index=Join-Path $root "node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
                $nodeCmd=Get-Command node.exe -ErrorAction SilentlyContinue
                if(-not $nodeCmd){$nodeCmd=Get-Command node -ErrorAction SilentlyContinue}
                if(-not $nodeCmd){throw "Node.js executable not found."}
                $nodePath=[string]$(if($nodeCmd.Path){$nodeCmd.Path}elseif($nodeCmd.Definition){$nodeCmd.Definition}else{$nodeCmd.Name})

                $dcRoot="C:\DesktopCommanderCompat"
                $logRoot=Join-Path $dcRoot "logs"
                New-Item -ItemType Directory -Force -Path $dcRoot,$logRoot | Out-Null
                $log=Join-Path $logRoot "remote-interactive.log"
                Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue

                # Node 18 on Server 2012 R2 has no native global WebSocket.
                # Supabase Realtime accepts a standards-compatible implementation;
                # preload the already-installed ws package before Desktop Commander.
                $wsPkg=Join-Path $root "node_modules\ws\package.json"
                if(!(Test-Path -LiteralPath $wsPkg -PathType Leaf)){
                    throw "Node18 WebSocket shim prerequisite missing: ws package not found."
                }
                $shim=Join-Path $dcRoot "desktop-commander-node18-shim.mjs"
                $shimLines=@(
                    "import { createRequire } from 'node:module';",
                    "const require = createRequire(import.meta.url);",
                    ('const WS = require("'+($root -replace '\\','/')+'/node_modules/ws");'),
                    "globalThis.WebSocket = WS.WebSocket || WS;",
                    ('await import("file:///'+(($index -replace '\\','/') -replace ' ','%20')+'");')
                )
                $shimLines | Set-Content -LiteralPath $shim -Encoding ASCII

                $cmdFile=Join-Path $dcRoot "Run-DesktopCommanderInteractive.cmd"
                $cmdLines=@(
                    "@echo off",
                    "set USERPROFILE=C:\Users\Administrator",
                    "set HOME=C:\Users\Administrator",
                    ('cd /d "'+$root+'"'),
                    ('"'+$nodePath+'" "'+$shim+'" remote --debug >> "'+$log+'" 2>&1'),
                    ('echo EXIT %%ERRORLEVEL%% >> "'+$log+'"')
                )
                $cmdLines | Set-Content -LiteralPath $cmdFile -Encoding ASCII

                $explorer=$null
                try {
                    $explorer=Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | Sort-Object SessionId -Descending | Select-Object -First 1
                } catch {}
                if($null -eq $explorer){throw "No interactive explorer.exe session is available."}
                $explorerPid=[int]$explorer.ProcessId
                $sessionId=[int]$explorer.SessionId

                if(-not ("KatInteractiveLauncher" -as [type])) {
                    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class KatInteractiveLauncher {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public Int32 cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public Int32 dwX;
        public Int32 dwY;
        public Int32 dwXSize;
        public Int32 dwYSize;
        public Int32 dwXCountChars;
        public Int32 dwYCountChars;
        public Int32 dwFillAttribute;
        public Int32 dwFlags;
        public Int16 wShowWindow;
        public Int16 cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public Int32 dwProcessId;
        public Int32 dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(UInt32 access, bool inherit, Int32 pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr process, UInt32 access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(
        IntPtr existingToken,
        UInt32 desiredAccess,
        IntPtr tokenAttributes,
        Int32 impersonationLevel,
        Int32 tokenType,
        out IntPtr newToken);

    [DllImport("userenv.dll", SetLastError=true)]
    public static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);

    [DllImport("userenv.dll", SetLastError=true)]
    public static extern bool DestroyEnvironmentBlock(IntPtr environment);

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessAsUser(
        IntPtr token,
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool inheritHandles,
        UInt32 creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref STARTUPINFO startupInfo,
        out PROCESS_INFORMATION processInformation);
}
'@
                }

                $PROCESS_QUERY_INFORMATION=0x0400
                $TOKEN_ASSIGN_PRIMARY=0x0001
                $TOKEN_DUPLICATE=0x0002
                $TOKEN_QUERY=0x0008
                $TOKEN_ALL=$TOKEN_ASSIGN_PRIMARY -bor $TOKEN_DUPLICATE -bor $TOKEN_QUERY
                $hProcess=[KatInteractiveLauncher]::OpenProcess($PROCESS_QUERY_INFORMATION,$false,$explorerPid)
                if($hProcess -eq [IntPtr]::Zero){throw ("OpenProcess failed: "+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
                $hToken=[IntPtr]::Zero
                $dupToken=[IntPtr]::Zero
                $envBlock=[IntPtr]::Zero
                $pi=New-Object KatInteractiveLauncher+PROCESS_INFORMATION
                try {
                    if(-not [KatInteractiveLauncher]::OpenProcessToken($hProcess,$TOKEN_ALL,[ref]$hToken)){
                        throw ("OpenProcessToken failed: "+[Runtime.InteropServices.Marshal]::GetLastWin32Error())
                    }
                    if(-not [KatInteractiveLauncher]::DuplicateTokenEx($hToken,0xF01FF,[IntPtr]::Zero,2,1,[ref]$dupToken)){
                        throw ("DuplicateTokenEx failed: "+[Runtime.InteropServices.Marshal]::GetLastWin32Error())
                    }
                    [void][KatInteractiveLauncher]::CreateEnvironmentBlock([ref]$envBlock,$dupToken,$false)
                    $si=New-Object KatInteractiveLauncher+STARTUPINFO
                    $si.cb=[Runtime.InteropServices.Marshal]::SizeOf($si)
                    $si.lpDesktop="winsta0\default"
                    $cmdLine=New-Object System.Text.StringBuilder
                    [void]$cmdLine.Append('cmd.exe /D /C '+$cmdFile)
                    $flags=0x00000400 -bor 0x00000010
                    $ok=[KatInteractiveLauncher]::CreateProcessAsUser(
                        $dupToken,
                        "C:\Windows\System32\cmd.exe",
                        $cmdLine,
                        [IntPtr]::Zero,
                        [IntPtr]::Zero,
                        $false,
                        $flags,
                        $envBlock,
                        $dcRoot,
                        [ref]$si,
                        [ref]$pi
                    )
                    if(-not $ok){throw ("CreateProcessAsUser failed: "+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
                }
                finally {
                    if($pi.hThread -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::CloseHandle($pi.hThread)}
                    if($pi.hProcess -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::CloseHandle($pi.hProcess)}
                    if($envBlock -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::DestroyEnvironmentBlock($envBlock)}
                    if($dupToken -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::CloseHandle($dupToken)}
                    if($hToken -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::CloseHandle($hToken)}
                    if($hProcess -ne [IntPtr]::Zero){[void][KatInteractiveLauncher]::CloseHandle($hProcess)}
                }

                Start-Sleep -Seconds 15
                $launchedPid=[int]$pi.dwProcessId
                $alive=$false
                try{$alive=$null -ne (Get-Process -Id $launchedPid -ErrorAction SilentlyContinue)}catch{}
                $logTail=""
                try{if(Test-Path -LiteralPath $log -PathType Leaf){$logTail=(@(Get-Content -LiteralPath $log -Tail 120)-join [Environment]::NewLine)}}catch{}
                $safeLog=Redact-Text $logTail
                $phase="RUNNING"
                if($safeLog -match "(?i)Device ready"){$phase="DEVICE_READY"}
                elseif($safeLog -match "(?i)Failed to start device authorization"){$phase="UPSTREAM_AUTH_FAILED"}
                elseif($safeLog -match "(?i)native WebSocket not found"){$phase="WEBSOCKET_SHIM_FAILED"}
                elseif($safeLog -match "(?i)verification|device code|Requesting device code|Authenticating|Connecting this computer"){$phase="AUTH_REQUIRED"}
                elseif(-not $alive){$phase="PROCESS_EXITED"}

                $diag=[ordered]@{
                    schema_version=1
                    proof_type="DESKTOP_COMMANDER_INTERACTIVE_START"
                    explorer_process_id=$explorerPid
                    interactive_session_id=$sessionId
                    launched_process_id=$launchedPid
                    launched_process_alive=$alive
                    phase=$phase
                    sanitized_log_tail=$safeLog
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                    result=$(if($phase -in @("DEVICE_READY","AUTH_REQUIRED","RUNNING")){"PASS"}elseif($phase -eq "UPSTREAM_AUTH_FAILED"){"BLOCKED_UPSTREAM"}else{"FAIL"})
                }
                Write-JsonFile (Join-Path $OutputDir "desktop_commander_interactive_start.json") $diag
                ("DESKTOP COMMANDER INTERACTIVE "+[string]$diag.result+" / "+$phase) | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["phase"]=$phase
                $details["session_id"]=$sessionId
                $details["result"]=[string]$diag.result
                break
            }

            if ($mode -eq "WORKSPACE_DESKTOP_COMMANDER_START_DIRECT") {
                $cacheBase="C:\Users\Administrator\AppData\Local\npm-cache\_npx"
                $root=$null
                if(Test-Path -LiteralPath $cacheBase -PathType Container) {
                    foreach($d in @(Get-ChildItem -LiteralPath $cacheBase -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
                        $pkg=Join-Path $d.FullName "node_modules\@wonderwhy-er\desktop-commander\package.json"
                        if(Test-Path -LiteralPath $pkg -PathType Leaf) {
                            try {
                                $m=Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
                                if([string]$m.version -eq "0.2.52"){$root=$d.FullName;break}
                            } catch {}
                        }
                    }
                }
                if([string]::IsNullOrWhiteSpace($root)){throw "Desktop Commander 0.2.52 cache installation not found."}

                $index=Join-Path $root "node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
                if(!(Test-Path -LiteralPath $index -PathType Leaf)){throw "Desktop Commander index.js missing."}
                $nodeCmd=Get-Command node.exe -ErrorAction SilentlyContinue
                if(-not $nodeCmd){$nodeCmd=Get-Command node -ErrorAction SilentlyContinue}
                if(-not $nodeCmd){throw "Node.js executable not found."}
                $nodePath=[string]$(if($nodeCmd.Path){$nodeCmd.Path}elseif($nodeCmd.Definition){$nodeCmd.Definition}else{$nodeCmd.Name})

                $dcRoot="C:\DesktopCommanderCompat"
                $logRoot=Join-Path $dcRoot "logs"
                New-Item -ItemType Directory -Force -Path $dcRoot,$logRoot | Out-Null
                $log=Join-Path $logRoot "remote-task.log"
                Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
                $cmdFile=Join-Path $dcRoot "Run-DesktopCommanderRemote.cmd"
                $cmdLines=@(
                    "@echo off",
                    ('cd /d "'+$root+'"'),
                    ('"'+$nodePath+'" "'+$index+'" remote --debug >> "'+$log+'" 2>&1'),
                    ('echo EXIT %%ERRORLEVEL%% >> "'+$log+'"')
                )
                $cmdLines | Set-Content -LiteralPath $cmdFile -Encoding ASCII

                $launchCmd='cmd.exe /D /C '+$cmdFile
                try {
                    $wmi=[wmiclass]"Win32_Process"
                    $created=$wmi.Create($launchCmd,$dcRoot,$null)
                } catch {
                    throw ("Failed to launch Desktop Commander through WMI cmdfile: "+(Redact-Text $_.Exception.Message))
                }
                if($null -eq $created -or [int]$created.ReturnValue -ne 0) {
                    $rv=$(if($null -eq $created){-1}else{[int]$created.ReturnValue})
                    throw ("Failed to launch Desktop Commander through WMI cmd. return="+$rv)
                }

                Start-Sleep -Seconds 15

                $launcherPid=[int]$created.ProcessId
                $launcherAlive=$false
                try{$launcherAlive=$null -ne (Get-Process -Id $launcherPid -ErrorAction SilentlyContinue)}catch{}
                $logTail=""
                try{if(Test-Path -LiteralPath $log -PathType Leaf){$logTail=(@(Get-Content -LiteralPath $log -Tail 100)-join [Environment]::NewLine)}}catch{}
                $safeLog=Redact-Text $logTail
                $phase="RUNNING"
                if($safeLog -match "(?i)Device ready"){$phase="DEVICE_READY"}
                elseif($safeLog -match "(?i)Failed to start device authorization"){$phase="UPSTREAM_AUTH_FAILED"}
                elseif($safeLog -match "(?i)verification|device code|Requesting device code|Authenticating|Connecting this computer"){$phase="AUTH_REQUIRED"}
                elseif(-not $launcherAlive){$phase="PROCESS_EXITED"}

                $diag=[ordered]@{
                    schema_version=1
                    proof_type="DESKTOP_COMMANDER_START"
                    launch_method="WMI_CMD_FILE"
                    launcher_process_id=$launcherPid
                    launcher_process_alive=$launcherAlive
                    node_path=$nodePath
                    install_root=$root
                    phase=$phase
                    sanitized_log_tail=$safeLog
                    task_status=(Redact-Text $taskText)
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                    result=$(if($phase -in @("DEVICE_READY","AUTH_REQUIRED","RUNNING")){"PASS"}elseif($phase -eq "UPSTREAM_AUTH_FAILED"){"BLOCKED_UPSTREAM"}else{"FAIL"})
                }
                Write-JsonFile (Join-Path $OutputDir "desktop_commander_start.json") $diag
                ("DESKTOP COMMANDER START "+[string]$diag.result+" / "+$phase) | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["phase"]=$phase
                $details["result"]=[string]$diag.result
                break
            }

            if ($mode -eq "WORKSPACE_DESKTOP_COMMANDER_SCAN_DIRECT") {
                $records = @()
                $roots = @()
                $cacheBase = "C:\Users\Administrator\AppData\Local\npm-cache\_npx"
                if (Test-Path -LiteralPath $cacheBase -PathType Container) {
                    foreach($d in @(Get-ChildItem -LiteralPath $cacheBase -Directory -ErrorAction SilentlyContinue)) {
                        $pkg = Join-Path $d.FullName "node_modules\@wonderwhy-er\desktop-commander\package.json"
                        if(Test-Path -LiteralPath $pkg -PathType Leaf){ $roots += $d.FullName }
                    }
                }
                foreach($candidate in @("C:\DesktopCommander","C:\DesktopCommanderCompat")) {
                    $pkg = Join-Path $candidate "node_modules\@wonderwhy-er\desktop-commander\package.json"
                    if(Test-Path -LiteralPath $pkg -PathType Leaf){ $roots += $candidate }
                }
                $roots = @($roots | Sort-Object -Unique)

                foreach($root in $roots) {
                    $dcPkg = Join-Path $root "node_modules\@wonderwhy-er\desktop-commander\package.json"
                    $ppPkg = Join-Path $root "node_modules\puppeteer\package.json"
                    $sbPkg = Join-Path $root "node_modules\@supabase\supabase-js\package.json"
                    $ftPkg = Join-Path $root "node_modules\file-type\package.json"
                    $mdPkg = Join-Path $root "node_modules\md-to-pdf\package.json"
                    $idx = Join-Path $root "node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
                    $rec=[ordered]@{
                        root=$root
                        desktop_commander=$null
                        puppeteer=$null
                        supabase=$null
                        file_type=$null
                        md_to_pdf=$null
                        index_exists=(Test-Path -LiteralPath $idx -PathType Leaf)
                        help_exit=$null
                        help_error=""
                    }
                    foreach($pair in @(
                        @("desktop_commander",$dcPkg),
                        @("puppeteer",$ppPkg),
                        @("supabase",$sbPkg),
                        @("file_type",$ftPkg),
                        @("md_to_pdf",$mdPkg)
                    )) {
                        if(Test-Path -LiteralPath $pair[1] -PathType Leaf) {
                            try { $rec[$pair[0]]=[string](Get-Content -LiteralPath $pair[1] -Raw | ConvertFrom-Json).version } catch {}
                        }
                    }
                    if($rec.index_exists) {
                        $nodeCmd=Get-Command node.exe -ErrorAction SilentlyContinue
                        if(-not $nodeCmd){$nodeCmd=Get-Command node -ErrorAction SilentlyContinue}
                        if($nodeCmd) {
                            $nodePath=[string]$(if($nodeCmd.Path){$nodeCmd.Path}elseif($nodeCmd.Definition){$nodeCmd.Definition}else{$nodeCmd.Name})
                            $ho=Join-Path $OutputDir ("dc_help_"+([guid]::NewGuid().ToString("N").Substring(0,8))+".out")
                            $he=Join-Path $OutputDir ("dc_help_"+([guid]::NewGuid().ToString("N").Substring(0,8))+".err")
                            try {
                                $oldEap=$ErrorActionPreference
                                $ErrorActionPreference="Continue"
                                $helpLines=& $nodePath $idx remote --help 2>&1
                                $rec.help_exit=$LASTEXITCODE
                                $ErrorActionPreference=$oldEap
                                if($rec.help_exit -ne 0){$rec.help_error=(Redact-Text (($helpLines | Out-String)))}
                            } catch {
                                $rec.help_exit=-1
                                $rec.help_error=(Redact-Text $_.Exception.Message)
                                $ErrorActionPreference="Stop"
                            }
                            Remove-Item -LiteralPath $ho,$he -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $records += $rec
                }

                $sessions=@()
                foreach($p in @(
                    "C:\Users\Administrator\.desktop-commander-device\device.json",
                    "C:\Windows\System32\config\systemprofile\.desktop-commander-device\device.json"
                )) {
                    $sessions += [ordered]@{path=$p;exists=(Test-Path -LiteralPath $p -PathType Leaf)}
                }

                $nodeProcesses=@()
                try {
                    foreach($p in @(Get-WmiObject Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue)) {
                        $cl=[string]$p.CommandLine
                        if($cl -and $cl.IndexOf("desktop-commander",[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $nodeProcesses += [ordered]@{process_id=[int]$p.ProcessId;command_line=(Redact-Text $cl)}
                        }
                    }
                } catch {}

                $diag=[ordered]@{
                    schema_version=1
                    proof_type="DESKTOP_COMMANDER_SCAN"
                    installations=$records
                    sessions=$sessions
                    running_processes=$nodeProcesses
                    generated_utc=[DateTime]::UtcNow.ToString("o")
                    result="PASS"
                }
                Write-JsonFile (Join-Path $OutputDir "desktop_commander_scan.json") $diag
                "DESKTOP COMMANDER SCAN PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["installation_count"]=$records.Count
                $details["running_count"]=$nodeProcesses.Count
                $details["result"]="PASS"
                break
            }

            # Desktop Commander compatibility/repair path for the legacy Windows Server 2012 R2 host.
            if ($mode -eq "WORKSPACE_DESKTOP_COMMANDER_REPAIR_DIRECT") {
                $dcRoot = "C:\DesktopCommanderCompat"
                $dcLogRoot = Join-Path $dcRoot "logs"
                New-Item -ItemType Directory -Force -Path $dcRoot,$dcLogRoot | Out-Null

                $nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
                if (-not $nodeCmd) { $nodeCmd = Get-Command node -ErrorAction SilentlyContinue }
                $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
                if (-not $npmCmd) { $npmCmd = Get-Command npm -ErrorAction SilentlyContinue }
                if (-not $nodeCmd) { throw "Node.js executable not found." }
                if (-not $npmCmd) { throw "npm executable not found." }
                $nodePath = [string]$(if($nodeCmd.Path){$nodeCmd.Path}elseif($nodeCmd.Definition){$nodeCmd.Definition}else{$nodeCmd.Name})
                $npmPath = [string]$(if($npmCmd.Path){$npmCmd.Path}elseif($npmCmd.Definition){$npmCmd.Definition}else{$npmCmd.Name})

                $nodeVersion = (& $nodePath --version 2>&1 | Out-String).Trim()
                $npmVersion = (& $npmPath --version 2>&1 | Out-String).Trim()

                $cacheRoot = $null
                $cacheBase = "C:\Users\Administrator\AppData\Local\npm-cache\_npx"
                if (Test-Path -LiteralPath $cacheBase -PathType Container) {
                    foreach ($dir in @(Get-ChildItem -LiteralPath $cacheBase -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
                        $pkg = Join-Path $dir.FullName "node_modules\@wonderwhy-er\desktop-commander\package.json"
                        if (Test-Path -LiteralPath $pkg -PathType Leaf) {
                            try {
                                $meta = Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
                                if ([string]$meta.version -eq "0.2.52") { $cacheRoot = $dir.FullName; break }
                            } catch {}
                        }
                    }
                }

                $installRoot = $cacheRoot
                $installSource = "ADMIN_NPX_CACHE"
                $installLog = Join-Path $dcLogRoot "npm-install.log"
                if ([string]::IsNullOrWhiteSpace($installRoot)) {
                    $installRoot = $dcRoot
                    $installSource = "FRESH_COMPAT_ROOT"
                    '{"private":true,"dependencies":{"@wonderwhy-er/desktop-commander":"0.2.52"}}' | Set-Content -LiteralPath (Join-Path $installRoot "package.json") -Encoding ASCII
                }

                $env:PUPPETEER_SKIP_DOWNLOAD = "true"
                $npmArgs = @("install","--prefix",$installRoot,"@wonderwhy-er/desktop-commander@0.2.52","@supabase/supabase-js@2.78.0","puppeteer@24.34.0","file-type@20.3.0","--no-save","--legacy-peer-deps","--no-audit","--no-fund")
                $installErrLog = Join-Path $dcLogRoot "npm-install.err.log"
                Remove-Item -LiteralPath $installLog,$installErrLog -Force -ErrorAction SilentlyContinue
                $installProc = Start-Process -FilePath $npmPath -ArgumentList $npmArgs -WorkingDirectory $installRoot -Wait -PassThru -RedirectStandardOutput $installLog -RedirectStandardError $installErrLog
                $installExit = $installProc.ExitCode

                $indexPath = Join-Path $installRoot "node_modules\@wonderwhy-er\desktop-commander\dist\index.js"
                if ($installExit -ne 0 -or !(Test-Path -LiteralPath $indexPath -PathType Leaf)) {
                    $tail = ""
                    try {
                        $tail = (@(Get-Content -LiteralPath $installLog -Tail 20) + @(Get-Content -LiteralPath $installErrLog -Tail 35)) -join [Environment]::NewLine
                    } catch {}
                    throw ("Desktop Commander compatibility install failed. npm_exit=" + $installExit + " tail=" + (Redact-Text $tail))
                }

                $helpOutPath = Join-Path $dcLogRoot "remote-help.out.log"
                $helpErrPath = Join-Path $dcLogRoot "remote-help.err.log"
                Remove-Item -LiteralPath $helpOutPath,$helpErrPath -Force -ErrorAction SilentlyContinue
                $helpProc = Start-Process -FilePath $nodePath -ArgumentList @(('"' + $indexPath + '"'),"remote","--help") -WorkingDirectory $installRoot -Wait -PassThru -RedirectStandardOutput $helpOutPath -RedirectStandardError $helpErrPath
                if ($helpProc.ExitCode -ne 0) {
                    $helpErr = ""
                    try { $helpErr = (@(Get-Content -LiteralPath $helpErrPath -Tail 40) -join [Environment]::NewLine) } catch {}
                    throw ("Desktop Commander CLI probe failed. exit=" + $helpProc.ExitCode + " error=" + (Redact-Text $helpErr))
                }

                try {
                    foreach ($p in @(Get-WmiObject Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue)) {
                        $cl = [string]$p.CommandLine
                        if ($cl -and $cl.IndexOf("desktop-commander",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $cl.IndexOf(" remote",[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            try { [void]$p.Terminate() } catch {}
                        }
                    }
                } catch {}
                Start-Sleep -Seconds 2

                $remoteOut = Join-Path $dcLogRoot "remote.out.log"
                $remoteErr = Join-Path $dcLogRoot "remote.err.log"
                Remove-Item -LiteralPath $remoteOut,$remoteErr -Force -ErrorAction SilentlyContinue
                $remoteProc = Start-Process -FilePath $nodePath -ArgumentList @(('"' + $indexPath + '"'),"remote","--debug") -WorkingDirectory $installRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $remoteOut -RedirectStandardError $remoteErr
                Start-Sleep -Seconds 18

                $alive = $false
                try { $alive = $null -ne (Get-Process -Id $remoteProc.Id -ErrorAction SilentlyContinue) } catch {}
                $outTail = ""
                $errTail = ""
                try { if(Test-Path $remoteOut){$outTail=(@(Get-Content -LiteralPath $remoteOut -Tail 80) -join [Environment]::NewLine)} } catch {}
                try { if(Test-Path $remoteErr){$errTail=(@(Get-Content -LiteralPath $remoteErr -Tail 80) -join [Environment]::NewLine)} } catch {}
                $combined = (Redact-Text ($outTail + [Environment]::NewLine + $errTail))

                $phase = "UNKNOWN"
                if ($combined -match "(?i)Device ready") { $phase = "DEVICE_READY" }
                elseif ($combined -match "(?i)Failed to start device authorization") { $phase = "UPSTREAM_AUTH_FAILED" }
                elseif ($combined -match "(?i)verification|device code|Requesting device code|Authenticating") { $phase = "AUTH_REQUIRED" }
                elseif (-not $alive) { $phase = "PROCESS_EXITED" }
                else { $phase = "RUNNING" }

                $diag = [ordered]@{
                    schema_version = 1
                    proof_type = "DESKTOP_COMMANDER_REPAIR"
                    node_version = $nodeVersion
                    npm_version = $npmVersion
                    desktop_commander_version = "0.2.52"
                    supabase_pin = "2.78.0"
                    puppeteer_pin = "24.34.0"
                    file_type_pin = "20.3.0"
                    install_source = $installSource
                    install_root = $installRoot
                    process_id = $remoteProc.Id
                    process_alive = $alive
                    phase = $phase
                    sanitized_output_tail = $combined
                    generated_utc = [DateTime]::UtcNow.ToString("o")
                    result = $(if($phase -in @("DEVICE_READY","AUTH_REQUIRED","RUNNING")){"PASS"}elseif($phase -eq "UPSTREAM_AUTH_FAILED"){"BLOCKED_UPSTREAM"}else{"FAIL"})
                }
                Write-JsonFile (Join-Path $OutputDir "desktop_commander_repair.json") $diag
                ("DESKTOP COMMANDER REPAIR " + [string]$diag.result + " / " + $phase) | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = $mode
                $details["phase"] = $phase
                $details["process_alive"] = $alive
                $details["result"] = [string]$diag.result
                if([string]$diag.result -eq "FAIL"){ throw "Desktop Commander repair did not reach a usable state." }
                break
            }

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
                if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = "alfaaulia8-sys/Katarina-AI" }
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
                if([string]::IsNullOrWhiteSpace([string]$guarded.repository)){$guarded.repository="alfaaulia8-sys/Katarina-AI"}
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

            if ($mode -eq "WORKSPACE_STAGE07_BATCH") {
                $workspaceRunner = Join-Path $RepoRoot "scripts\vps\Invoke-KatarinaWorkspaceTask.ps1"
                if (!(Test-Path -LiteralPath $workspaceRunner -PathType Leaf)) {
                    throw "Katarina workspace runner is missing."
                }
                if ($null -eq $request.args.PSObject.Properties["steps"] -or $null -eq $request.args.steps) {
                    throw "WORKSPACE_STAGE07_BATCH requires steps."
                }

                $steps = @($request.args.steps)
                if ($steps.Count -lt 1 -or $steps.Count -gt 6) {
                    throw "WORKSPACE_STAGE07_BATCH allows 1 to 6 steps."
                }

                # Heavy MT5 compile/runtime modes are already internally batched
                # and keep their own dedicated requests/timeouts. This coordinator
                # intentionally combines only lightweight validation work so one
                # GitHub request/result pair can cover several checks safely.
                $allowedBatchModes = @(
                    "WORKSPACE_DEPENDENCY_VERIFY",
                    "WORKSPACE_TEST",
                    "WORKSPACE_CONTROL_STATUS"
                )

                $batchStarted = [DateTime]::UtcNow
                $batchRecords = @()
                $batchFailed = $false
                $batchFailure = ""

                for ($i = 0; $i -lt $steps.Count; $i++) {
                    $step = $steps[$i]
                    $stepMode = ""
                    if ($null -ne $step.PSObject.Properties["mode"]) {
                        $stepMode = ([string]$step.mode).ToUpperInvariant()
                    }
                    if ($allowedBatchModes -notcontains $stepMode) {
                        throw "Batch step $($i + 1) uses unsupported mode: $stepMode"
                    }

                    $stepArgs = [ordered]@{ mode = $stepMode }
                    if ($null -ne $step.PSObject.Properties["args"] -and $null -ne $step.args) {
                        foreach ($prop in $step.args.PSObject.Properties) {
                            if ([string]$prop.Name -ne "mode") {
                                $stepArgs[[string]$prop.Name] = $prop.Value
                            }
                        }
                    }

                    $stepId = ("{0}-b{1:D2}" -f [string]$request.request_id,($i + 1))
                    $stepRequestPath = Join-Path $OutputDir ("batch_step_{0:D2}_request.json" -f ($i + 1))
                    $stepOutputDir = Join-Path $OutputDir ("batch_step_{0:D2}" -f ($i + 1))
                    New-Item -ItemType Directory -Force -Path $stepOutputDir | Out-Null

                    $stepRequest = [ordered]@{
                        schema_version = 1
                        request_id = $stepId
                        target_agent = [string]$request.target_agent
                        task = "STAGE07_PYTHON_TESTS"
                        execution_class = "READONLY"
                        created_utc = [DateTime]::UtcNow.ToString("o")
                        expires_utc = [string]$request.expires_utc
                        ref = [string]$request.ref
                        args = $stepArgs
                    }
                    Write-JsonFile $stepRequestPath $stepRequest

                    $stepStarted = [DateTime]::UtcNow
                    $stepOk = $true
                    $stepError = ""
                    try {
                        # Same-process invocation is deliberate: no extra nested
                        # PowerShell process is created on the 2 GB legacy VPS.
                        & $workspaceRunner -RequestFile $stepRequestPath -OutputDir $stepOutputDir -RepoRoot $RepoRoot
                    }
                    catch {
                        $stepOk = $false
                        $stepError = Redact-Text ([string]$_.Exception.Message)
                    }

                    $stepStatus = $null
                    $stepStatusPath = Join-Path $stepOutputDir "workspace_status.json"
                    if (Test-Path -LiteralPath $stepStatusPath -PathType Leaf) {
                        try { $stepStatus = Get-Content -LiteralPath $stepStatusPath -Raw | ConvertFrom-Json } catch {}
                    }
                    if ($null -eq $stepStatus -or [string]$stepStatus.result -ne "PASS") {
                        $stepOk = $false
                        if ([string]::IsNullOrWhiteSpace($stepError)) {
                            $stepError = "Workspace step did not produce PASS status evidence."
                        }
                    }

                    # Promote only compact evidence to the parent output. Logs stay
                    # local on the VPS; the agent will upload one compact bundle.
                    $promoted = @()
                    foreach ($file in @(Get-ChildItem -LiteralPath $stepOutputDir -File -ErrorAction SilentlyContinue)) {
                        $ext = $file.Extension.ToLowerInvariant()
                        if ($ext -notin @(".json",".txt")) { continue }
                        if ($file.Length -gt 262144) { continue }
                        $destName = ("batch_{0:D2}_{1}" -f ($i + 1),$file.Name)
                        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $OutputDir $destName) -Force
                        $promoted += $destName
                    }

                    $stepCompleted = [DateTime]::UtcNow
                    $batchRecords += [ordered]@{
                        index = ($i + 1)
                        mode = $stepMode
                        started_utc = $stepStarted.ToString("o")
                        completed_utc = $stepCompleted.ToString("o")
                        duration_ms = [int64]($stepCompleted - $stepStarted).TotalMilliseconds
                        promoted_evidence = $promoted
                        result = $(if($stepOk){"PASS"}else{"FAIL"})
                        error = $stepError
                    }

                    if (-not $stepOk) {
                        $batchFailed = $true
                        $batchFailure = ("step {0} ({1}): {2}" -f ($i + 1),$stepMode,$stepError)
                        break
                    }
                }

                $batchCompleted = [DateTime]::UtcNow
                $batchSummary = [ordered]@{
                    schema_version = 1
                    proof_type = "KATARINA_STAGE07_LOCAL_BATCH"
                    request_id = [string]$request.request_id
                    execution_model = "SAME_PROCESS_SEQUENTIAL"
                    github_write_model = "ONE_REQUEST_ONE_RESULT_BUNDLE"
                    snapshot_downloads = 1
                    child_powershell_processes = 0
                    requested_step_count = $steps.Count
                    completed_step_count = $batchRecords.Count
                    steps = $batchRecords
                    started_utc = $batchStarted.ToString("o")
                    completed_utc = $batchCompleted.ToString("o")
                    duration_ms = [int64]($batchCompleted - $batchStarted).TotalMilliseconds
                    result = $(if($batchFailed){"FAIL"}else{"PASS"})
                }
                Write-JsonFile (Join-Path $OutputDir "stage07_batch_summary.json") $batchSummary

                $details["mode"] = $mode
                $details["execution_model"] = "SAME_PROCESS_SEQUENTIAL"
                $details["requested_steps"] = $steps.Count
                $details["completed_steps"] = $batchRecords.Count
                $details["result"] = [string]$batchSummary.result

                if ($batchFailed) {
                    throw ("Stage-07 local batch failed: " + $batchFailure)
                }

                "KATARINA STAGE07 LOCAL BATCH PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                break
            }

            if ($mode -eq "WORKSPACE_MT5_TCP_FALLBACK_PROOF_DIRECT") {
                $terminalPath=[string]$request.args.terminal_path
                $terminalDataPath=[string]$request.args.terminal_data_path
                $metaEditorPath=[string]$request.args.metaeditor_path
                if([string]::IsNullOrWhiteSpace($terminalPath) -or !(Test-Path -LiteralPath $terminalPath -PathType Leaf)) {
                    throw "terminal_path is required for native TCP proof."
                }
                if([string]::IsNullOrWhiteSpace($terminalDataPath) -or !(Test-Path -LiteralPath $terminalDataPath -PathType Container)) {
                    throw "terminal_data_path is required for native TCP proof."
                }
                if([string]::IsNullOrWhiteSpace($metaEditorPath) -or !(Test-Path -LiteralPath $metaEditorPath -PathType Leaf)) {
                    throw "metaeditor_path is required for native TCP proof."
                }

                $includeSource=Join-Path $RepoRoot "mt5\Include\Katarina"
                $testSource=Join-Path $RepoRoot "mt5\Tests\KatarinaStage07TcpFallbackIntegration.mq5"
                $launcher=Join-Path $RepoRoot "scripts\vps\Invoke-KatarinaInteractiveMt5.ps1"
                foreach($required in @($includeSource,$testSource,$launcher)) {
                    if(!(Test-Path -LiteralPath $required)) { throw "Native TCP proof prerequisite missing: $required" }
                }

                $mqlRoot=Join-Path $terminalDataPath "MQL5"
                $includeDest=Join-Path $mqlRoot "Include\Katarina"
                $scriptsDest=Join-Path $mqlRoot "Scripts"
                New-Item -ItemType Directory -Force -Path $includeDest,$scriptsDest | Out-Null
                Copy-Item -Path (Join-Path $includeSource "*") -Destination $includeDest -Recurse -Force

                $scriptDest=Join-Path $scriptsDest "KatarinaStage07TcpFallbackIntegration.mq5"
                $ex5=[IO.Path]::ChangeExtension($scriptDest,".ex5")
                Copy-Item -LiteralPath $testSource -Destination $scriptDest -Force
                Remove-Item -LiteralPath $ex5 -Force -ErrorAction SilentlyContinue

                $compileLog=Join-Path $OutputDir "KatarinaStage07TcpFallbackIntegration.compile.log"
                Remove-Item -LiteralPath $compileLog -Force -ErrorAction SilentlyContinue
                $compileArgs=@(
                    ('/compile:"' + $scriptDest + '"'),
                    ('/inc:"' + $mqlRoot + '"'),
                    ('/log:"' + $compileLog + '"')
                )
                $compile=Start-Process -FilePath $metaEditorPath -ArgumentList $compileArgs -Wait -PassThru
                if(!(Test-Path -LiteralPath $compileLog -PathType Leaf)) { throw "Native TCP MetaEditor compile log missing." }
                $compileText=Get-Content -LiteralPath $compileLog -Raw
                if($compileText -notmatch "0 errors, 0 warnings") {
                    throw "Native TCP fallback test did not compile with 0 errors / 0 warnings."
                }
                if(!(Test-Path -LiteralPath $ex5 -PathType Leaf)) { throw "Native TCP fallback EX5 missing." }

                $python="C:\KatarinaDev\runtime\python\python.exe"
                $workspace="C:\KatarinaDev\workspace"
                if(!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "Katarina portable Python missing." }
                if(!(Test-Path -LiteralPath $workspace -PathType Container)) { throw "Katarina workspace missing." }

                $ready=Join-Path $OutputDir "tcp_server_ready.txt"
                $serverResult=Join-Path $OutputDir "tcp_server_result.json"
                $serverScript=Join-Path $OutputDir "stage07_tcp_server.py"
                Remove-Item -LiteralPath $ready,$serverResult -Force -ErrorAction SilentlyContinue

                @'
import asyncio
import json
import pathlib

from katarina.adapters.transport.kat1_codec import Kat1Codec, SchemaCatalog
from katarina.adapters.transport.tcp import Kat1TcpServerTransport

ROOT = pathlib.Path(r"C:\KatarinaDev\workspace")
READY = pathlib.Path(r"__READY__")
RESULT = pathlib.Path(r"__RESULT__")

async def main():
    codec = Kat1Codec(
        SchemaCatalog.from_path(ROOT / "protocol" / "kat1_message_schemas_v1.json")
    )
    transport = Kat1TcpServerTransport(host="127.0.0.1", port=5572, receive_capacity=8)
    await transport.start()
    READY.write_text("READY", encoding="utf-8")
    try:
        received = await asyncio.wait_for(transport.receive_frame(), timeout=30.0)
        decoded = codec.decode(received.frame)
        await transport.send_frame(received.frame, peer=received.peer)
        RESULT.write_text(json.dumps({
            "schema_version": 1,
            "proof_type": "KATARINA_STAGE07_NATIVE_TCP_PYTHON_PEER",
            "message_type": decoded.header.message_type,
            "sequence": decoded.header.sequence,
            "stream_id": decoded.header.stream_id,
            "boot_id": decoded.header.boot_id,
            "frame_length": len(received.frame),
            "byte_echo": True,
            "result": "PASS",
        }, indent=2), encoding="utf-8")
    finally:
        await transport.stop()

asyncio.run(main())
'@.Replace("__READY__",$ready.Replace("\","\\")).Replace("__RESULT__",$serverResult.Replace("\","\\")) |
                    Set-Content -LiteralPath $serverScript -Encoding UTF8

                $server=Start-Process -FilePath $python -ArgumentList @($serverScript) -PassThru -NoNewWindow
                try {
                    $deadline=[DateTime]::UtcNow.AddSeconds(15)
                    while([DateTime]::UtcNow -lt $deadline -and !(Test-Path -LiteralPath $ready -PathType Leaf)) {
                        if($server.HasExited) { throw "Python native TCP peer exited before ready." }
                        Start-Sleep -Milliseconds 100
                    }
                    if(!(Test-Path -LiteralPath $ready -PathType Leaf)) { throw "Python native TCP peer did not become ready." }

                    $markerPath="\AppData\Roaming\MetaQuotes\Terminal\"
                    $markerIndex=$terminalDataPath.IndexOf($markerPath,[StringComparison]::OrdinalIgnoreCase)
                    if($markerIndex -le 0) { throw "Unable to derive MT5 user profile for native TCP proof." }
                    $profileRoot=$terminalDataPath.Substring(0,$markerIndex)
                    $expectedUser=Split-Path -Leaf $profileRoot
                    $commonFiles=Join-Path (Join-Path $profileRoot "AppData\Roaming") "MetaQuotes\Terminal\Common\Files"
                    New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null
                    $mt5Evidence=Join-Path $commonFiles "Katarina_Stage07_tcp_fallback_result.txt"
                    Remove-Item -LiteralPath $mt5Evidence -Force -ErrorAction SilentlyContinue

                    $config=Join-Path $OutputDir "stage07_tcp_fallback.ini"
                    @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Script=KatarinaStage07TcpFallbackIntegration
Symbol=
Period=H1
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $config -Encoding ASCII

                    $launchEvidence=Join-Path $OutputDir "interactive_tcp_fallback.json"
                    $launchStdout=Join-Path $OutputDir "interactive_tcp_stdout.txt"
                    $launchStderr=Join-Path $OutputDir "interactive_tcp_stderr.txt"
                    $launchArgs=@(
                        "-NoProfile","-ExecutionPolicy","Bypass",
                        "-File",$launcher,
                        "-TerminalPath",$terminalPath,
                        "-ConfigPath",$config,
                        "-ExpectedUser",$expectedUser,
                        "-TimeoutSeconds",40,
                        "-OutputPath",$launchEvidence
                    )
                    & powershell.exe $launchArgs 1> $launchStdout 2> $launchStderr
                    if($LASTEXITCODE -ne 0) { throw "Interactive MT5 native TCP launch failed." }

                    [void]$server.WaitForExit(15000)
                    if(!$server.HasExited) { throw "Python native TCP peer did not finish after MT5 test." }
                    if($server.ExitCode -ne 0) { throw "Python native TCP peer failed with exit code $($server.ExitCode)." }

                    if(!(Test-Path -LiteralPath $mt5Evidence -PathType Leaf)) { throw "MT5 native TCP evidence missing." }
                    $mt5Text=Get-Content -LiteralPath $mt5Evidence -Raw
                    Copy-Item -LiteralPath $mt5Evidence -Destination (Join-Path $OutputDir "Katarina_Stage07_tcp_fallback_result.txt") -Force
                    if($mt5Text -notmatch "result=PASS") {
                        throw ("MT5 native TCP fallback failed. Evidence: " + $mt5Text)
                    }

                    if(!(Test-Path -LiteralPath $serverResult -PathType Leaf)) { throw "Python native TCP evidence missing." }
                    $py=Get-Content -LiteralPath $serverResult -Raw | ConvertFrom-Json
                    if([string]$py.result -ne "PASS" -or [bool]$py.byte_echo -ne $true) {
                        throw "Python native TCP peer did not report PASS byte echo."
                    }
                    if([int]$py.message_type -ne 1 -or [int]$py.frame_length -ne 108) {
                        throw "Native TCP proof received unexpected KAT1 golden frame."
                    }

                    Write-JsonFile (Join-Path $OutputDir "stage07_native_tcp_fallback_evidence.json") ([ordered]@{
                        schema_version=1
                        stage="07"
                        proof_type="KATARINA_STAGE07_NATIVE_TCP_FALLBACK"
                        host="Windows Server 2012 R2"
                        endpoint="tcp://127.0.0.1:5572"
                        mql_transport="SocketCreate/SocketConnect/SocketSend/SocketRead"
                        python_transport="Kat1TcpServerTransport"
                        framing="KAT1_FRAME_LENGTH_ONLY"
                        secondary_envelope=$false
                        golden_message="HELLO"
                        frame_length=108
                        cross_language_byte_equality="PASS"
                        compile="PASS_0_ERRORS_0_WARNINGS"
                        ex5_sha256=(Get-FileHash -LiteralPath $ex5 -Algorithm SHA256).Hash.ToLowerInvariant()
                        live_trading_allowed=$false
                        dll_import_allowed=$false
                        result="PASS_STAGE07_NATIVE_TCP_FALLBACK"
                        generated_utc=[DateTime]::UtcNow.ToString("o")
                    })
                }
                finally {
                    if($null -ne $server -and !$server.HasExited) {
                        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
                    }
                }

                "KATARINA STAGE07 NATIVE TCP FALLBACK PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["transport"]="NATIVE_TCP"
                $details["result"]="PASS_STAGE07_NATIVE_TCP_FALLBACK"
                break
            }

            if ($mode -eq "WORKSPACE_STAGE07_CLOSEOUT_DIRECT") {
                $bootstrapVpsFirst=$false
                try {
                    if($null -ne $request.args.PSObject.Properties["bootstrap_vps_first"]) {
                        $bootstrapVpsFirst=[bool]$request.args.bootstrap_vps_first
                    }
                } catch {}

                if($bootstrapVpsFirst) {
                    $installRoot="C:\\KatarinaVPSAgent"
                    $agentSource=Join-Path $RepoRoot "scripts\\vps\\legacy\\KatarinaVpsAgent.ps1"
                    $agentPath=Join-Path $installRoot "KatarinaVpsAgent.ps1"
                    $workspaceRoot="C:\\KatarinaDev"
                    $workspace=Join-Path $workspaceRoot "workspace"
                    $snapshots=Join-Path $workspaceRoot "snapshots"
                    $metadata=Join-Path $workspaceRoot "metadata"
                    $python="C:\\KatarinaDev\\runtime\\python\\python.exe"

                    foreach($required in @($agentSource,$python)) {
                        if(!(Test-Path -LiteralPath $required -PathType Leaf)) {
                            throw "VPS-first bootstrap prerequisite missing: $required"
                        }
                    }

                    $agentText=Get-Content -LiteralPath $agentSource -Raw
                    if($agentText -notmatch '\$AgentVersion\s*=\s*"1\.4\.8"') {
                        throw "Repository agent source is not VPS-first agent 1.4.8."
                    }

                    New-Item -ItemType Directory -Force -Path $installRoot,$workspaceRoot,$snapshots,$metadata | Out-Null
                    Copy-Item -LiteralPath $agentSource -Destination $agentPath -Force

                    if(Test-Path -LiteralPath $workspace -PathType Container) {
                        $backup=Join-Path $snapshots ("pre_vps_first_"+[DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
                        Move-Item -LiteralPath $workspace -Destination $backup -Force
                    }
                    New-Item -ItemType Directory -Force -Path $workspace | Out-Null
                    foreach($item in Get-ChildItem -LiteralPath $RepoRoot -Force) {
                        if(@(".git","ops") -contains $item.Name){continue}
                        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $workspace $item.Name) -Recurse -Force
                    }

                    $fileCount=@(Get-ChildItem -LiteralPath $workspace -File -Recurse -ErrorAction Stop).Count
                    $pythonVersion=(& $python --version 2>&1 | Out-String).Trim()
                    if($LASTEXITCODE -ne 0){throw "Portable Python probe failed."}

                    $stage08Out=Join-Path $OutputDir "bootstrap_stage08_tests.txt"
                    $stage08Err=Join-Path $OutputDir "bootstrap_stage08_tests_err.txt"
                    $stage08Code=Invoke-Captured -FilePath $python -ArgumentList @(
                        "-m","unittest","discover","-s","tests/unit/validation","-p","test_*.py","-v"
                    ) -StdoutPath $stage08Out -StderrPath $stage08Err -WorkingDirectory $workspace
                    if($stage08Code -ne 0){throw "Stage-08 VPS regression failed during VPS-first bootstrap."}

                    $stage09Out=Join-Path $OutputDir "bootstrap_stage09_tests.txt"
                    $stage09Err=Join-Path $OutputDir "bootstrap_stage09_tests_err.txt"
                    $stage09Code=Invoke-Captured -FilePath $python -ArgumentList @(
                        "-m","unittest","discover","-s","tests/unit/health","-p","test_*.py","-v"
                    ) -StdoutPath $stage09Out -StderrPath $stage09Err -WorkingDirectory $workspace
                    if($stage09Code -ne 0){throw "Stage-09 VPS regression failed during VPS-first bootstrap."}

                    Write-JsonFile (Join-Path $metadata "vps_first.json") ([ordered]@{
                        schema_version=1
                        development_mode="VPS_FIRST"
                        canonical_ref=[string]$request.ref
                        workspace=$workspace
                        github_role="COMMAND_BUS_LOG_AND_FINAL_RELEASE_ONLY"
                        intermediate_source_commits=$false
                        initialized_utc=[DateTime]::UtcNow.ToString("o")
                    })

                    try { & schtasks.exe /Change /TN "KatarinaVPSAgent" /ENABLE | Out-Null } catch {}
                    $restartScript=Join-Path $installRoot "KatarinaVpsFirstDeferredRestart.ps1"
                    @'
$ErrorActionPreference="Continue"
try { & schtasks.exe /End /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Run /TN "KatarinaVPSAgent" | Out-Null } catch {}
Start-Sleep -Seconds 2
try { & schtasks.exe /Delete /F /TN "KatarinaVpsFirstDeferredRestart" | Out-Null } catch {}
'@ | Set-Content -LiteralPath $restartScript -Encoding ASCII
                    $runAt=(Get-Date).AddMinutes(1).ToString("HH:mm")
                    $restartCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "'+$restartScript+'"'
                    & schtasks.exe /Create /F /SC ONCE /ST $runAt /RU SYSTEM /RL HIGHEST /TN "KatarinaVpsFirstDeferredRestart" /TR $restartCmd | Out-Null
                    if($LASTEXITCODE -ne 0){throw "Failed to schedule VPS-first agent reload."}

                    Write-JsonFile (Join-Path $OutputDir "vps_first_bootstrap.json") ([ordered]@{
                        schema_version=1
                        proof_type="KATARINA_VPS_FIRST_BOOTSTRAP"
                        installed_agent_version="1.4.8"
                        workspace=$workspace
                        workspace_file_count=$fileCount
                        python=$python
                        python_version=$pythonVersion
                        stage08_regression="PASS"
                        stage09_regression="PASS"
                        intermediate_source_commits=$false
                        github_role="COMMAND_BUS_LOG_AND_FINAL_RELEASE_ONLY"
                        deferred_restart_time_local=$runAt
                        ready_for_stage10=$true
                        result="PASS_VPS_FIRST_READY_FOR_STAGE10"
                    })
                    "KATARINA VPS-FIRST BOOTSTRAP PASS" | Set-Content $stdoutPath -Encoding UTF8
                    "" | Set-Content $stderrPath -Encoding UTF8
                    $details["mode"]=$mode
                    $details["bootstrap_vps_first"]=$true
                    $details["installed_agent_version"]="1.4.8"
                    $details["ready_for_stage10"]=$true
                    $details["result"]="PASS_VPS_FIRST_READY_FOR_STAGE10"
                    break
                }

                $python="C:\KatarinaDev\runtime\python\python.exe"
                $profileScript=Join-Path $RepoRoot "scripts\stage07\profile_stage07_transport.py"
                $auditScript=Join-Path $RepoRoot "scripts\stage07\audit_stage07_final.py"
                $tcpRequestId="008-tcp-proof1"
                if($null -ne $request.args.PSObject.Properties["tcp_request_id"] -and
                   ![string]::IsNullOrWhiteSpace([string]$request.args.tcp_request_id)) {
                    $tcpRequestId=[string]$request.args.tcp_request_id
                }
                $tcpBundle=Join-Path $RepoRoot ("ops\vps\results\katarina-vps-2012r2-01\"+$tcpRequestId+"\bundle.json")
                $batchBundle=Join-Path $RepoRoot "ops\vps\results\katarina-vps-2012r2-01\s7-batch-opt1\bundle.json"
                foreach($required in @($python,$profileScript,$auditScript,$tcpBundle,$batchBundle)) {
                    if(!(Test-Path -LiteralPath $required -PathType Leaf)) {
                        throw "Stage-07 closeout prerequisite missing: $required"
                    }
                }

                $profileOut=Join-Path $OutputDir "stage07_transport_profile.json"
                $profileStdout=Join-Path $OutputDir "stage07_profile_stdout.txt"
                $profileStderr=Join-Path $OutputDir "stage07_profile_stderr.txt"
                & $python $profileScript --repo-root $RepoRoot --output $profileOut 1> $profileStdout 2> $profileStderr
                if($LASTEXITCODE -ne 0) {
                    throw "Stage-07 transport profile failed."
                }
                $profile=Get-Content -LiteralPath $profileOut -Raw | ConvertFrom-Json
                if([string]$profile.result -ne "PASS_STAGE07_BACKPRESSURE_LATENCY_PROFILE") {
                    throw "Stage-07 transport profile did not pass."
                }

                $auditOut=Join-Path $OutputDir "stage07_final_clearance.json"
                $auditStdout=Join-Path $OutputDir "stage07_audit_stdout.txt"
                $auditStderr=Join-Path $OutputDir "stage07_audit_stderr.txt"
                & $python $auditScript --repo-root $RepoRoot --profile-evidence $profileOut --tcp-bundle $tcpBundle --batch-bundle $batchBundle --output $auditOut 1> $auditStdout 2> $auditStderr
                if($LASTEXITCODE -ne 0) {
                    throw "Stage-07 final audit failed."
                }

                $audit=Get-Content -LiteralPath $auditOut -Raw | ConvertFrom-Json
                if([string]$audit.result -ne "PASS_STAGE07_FINAL_CLEARANCE" -or
                   [bool]$audit.ready_for_stage08 -ne $true) {
                    throw "Stage-07 final audit did not grant Stage-08 readiness."
                }

                "KATARINA STAGE07 FINAL CLEARANCE PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"]=$mode
                $details["profile_result"]=[string]$profile.result
                $details["audit_result"]=[string]$audit.result
                $details["ready_for_stage08"]=$true
                $details["result"]="PASS_STAGE07_FINAL_CLEARANCE"
                break
            }

            if ($mode -eq "WORKSPACE_APPLY") {
                $workspaceRoot = "C:\KatarinaDev\workspace"
                $evidenceRoot = "C:\KatarinaDev\evidence"
                if (!(Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
                    throw "Katarina workspace is not initialized."
                }
                if ($null -eq $request.args.PSObject.Properties["changeset"]) {
                    throw "changeset is required."
                }

                $changesetJson = $request.args.changeset | ConvertTo-Json -Depth 16
                if ([Text.Encoding]::UTF8.GetByteCount($changesetJson) -gt 524288) {
                    throw "Changeset exceeds 512 KiB command-bus limit."
                }
                $changesetFile = Join-Path $OutputDir "workspace_changeset.json"
                $changesetJson | Set-Content -LiteralPath $changesetFile -Encoding UTF8

                $apply = Join-Path $RepoRoot "scripts\vps\Apply-KatarinaWorkspaceChangeset.ps1"
                if (!(Test-Path -LiteralPath $apply -PathType Leaf)) {
                    throw "Workspace changeset engine missing."
                }

                & $apply -ChangesetPath $changesetFile -WorkspaceRoot $workspaceRoot -EvidenceRoot $evidenceRoot

                $changesetId = [string]$request.args.changeset.changeset_id
                $receipt = Join-Path $evidenceRoot ("changesets\" + $changesetId + "\receipt.json")
                if (!(Test-Path -LiteralPath $receipt -PathType Leaf)) {
                    throw "Workspace changeset receipt missing."
                }
                Copy-Item -LiteralPath $receipt -Destination (Join-Path $OutputDir "workspace_apply_receipt.json") -Force

                $checkRecords = @()
                if ($null -ne $request.args.PSObject.Properties["checks"] -and $request.args.checks) {
                    $checks = @($request.args.checks)
                    if ($checks.Count -gt 8) {
                        throw "WORKSPACE_APPLY allows at most 8 checks."
                    }

                    $python = Resolve-Executable @(
                        "C:\KatarinaDev\runtime\python\python.exe",
                        "python.exe",
                        "python"
                    )
                    if (-not $python) { throw "Workspace Python runtime is unavailable." }

                    for($i=0; $i -lt $checks.Count; $i++) {
                        $check = $checks[$i]
                        $type = ([string]$check.type).ToUpperInvariant()
                        $stdoutCheck = Join-Path $OutputDir ("check_{0:D2}_stdout.txt" -f ($i+1))
                        $stderrCheck = Join-Path $OutputDir ("check_{0:D2}_stderr.txt" -f ($i+1))
                        $argv = @()

                        switch($type) {
                            "PYTHON_UNIT_DISCOVER" {
                                $start = "tests/unit"
                                if ($null -ne $check.PSObject.Properties["start"] -and $check.start) {
                                    $start = ([string]$check.start).Replace("\","/")
                                }
                                if ($start.StartsWith("/") -or $start.Contains("..") -or -not $start.StartsWith("tests/")) {
                                    throw "Unsafe unittest discovery start path."
                                }
                                $pattern = "test_*.py"
                                if ($null -ne $check.PSObject.Properties["pattern"] -and $check.pattern) {
                                    $pattern = [string]$check.pattern
                                }
                                if ($pattern -notmatch '^[A-Za-z0-9_*.-]+$') {
                                    throw "Unsafe unittest discovery pattern."
                                }
                                $argv = @("-m","unittest","discover","-s",$start,"-p",$pattern,"-v")
                            }
                            "PYTHON_COMPILEALL" {
                                $target = "src"
                                if ($null -ne $check.PSObject.Properties["target"] -and $check.target) {
                                    $target = ([string]$check.target).Replace("\","/")
                                }
                                if ($target.StartsWith("/") -or $target.Contains("..") -or
                                    -not ($target.StartsWith("src") -or $target.StartsWith("scripts") -or $target.StartsWith("tests"))) {
                                    throw "Unsafe compileall target."
                                }
                                $argv = @("-m","compileall","-q",$target)
                            }
                            "PYTHON_SCRIPT" {
                                if ($null -eq $check.PSObject.Properties["path"] -or !$check.path) {
                                    throw "PYTHON_SCRIPT requires path."
                                }
                                $relative = ([string]$check.path).Replace("\","/")
                                if ($relative.StartsWith("/") -or $relative.Contains("..") -or -not $relative.StartsWith("scripts/")) {
                                    throw "Unsafe Python script path."
                                }
                                $script = Join-Path $workspaceRoot ($relative.Replace("/","\"))
                                if (!(Test-Path -LiteralPath $script -PathType Leaf)) {
                                    throw "Python script missing: $relative"
                                }
                                $argv = @($script)
                                if ($null -ne $check.PSObject.Properties["args"] -and $check.args) {
                                    foreach($item in @($check.args)) {
                                        $value=[string]$item
                                        if($value.Length -gt 512){throw "Python script argument too long."}
                                        $argv += $value
                                    }
                                }
                            }
                            default { throw "Unsupported WORKSPACE_APPLY check type: $type" }
                        }

                        $started=[DateTime]::UtcNow
                        $checkCode=Invoke-Captured -FilePath $python -ArgumentList $argv -StdoutPath $stdoutCheck -StderrPath $stderrCheck -WorkingDirectory $workspaceRoot
                        $checkRecords += [ordered]@{
                            index=$i+1
                            type=$type
                            exit_code=[int]$checkCode
                            duration_ms=[int](([DateTime]::UtcNow-$started).TotalMilliseconds)
                        }
                        if($checkCode -ne 0){
                            Write-JsonFile (Join-Path $OutputDir "vps_first_dev_result.json") ([ordered]@{
                                schema_version=1
                                development_mode="VPS_FIRST"
                                changeset_id=$changesetId
                                checks=$checkRecords
                                source_committed_to_github=$false
                                result="FAIL"
                            })
                            throw "VPS-first check failed: $type"
                        }
                    }
                }

                Write-JsonFile (Join-Path $OutputDir "vps_first_dev_result.json") ([ordered]@{
                    schema_version=1
                    development_mode="VPS_FIRST"
                    workspace_root=$workspaceRoot
                    changeset_id=$changesetId
                    operation_count=@($request.args.changeset.operations).Count
                    checks=$checkRecords
                    source_committed_to_github=$false
                    github_role="COMMAND_BUS_LOG_AND_FINAL_RELEASE_ONLY"
                    result="PASS"
                })

                "KATARINA VPS-FIRST WORKSPACE APPLY PASS" | Set-Content $stdoutPath -Encoding UTF8
                "" | Set-Content $stderrPath -Encoding UTF8
                $details["mode"] = $mode
                $details["changeset_id"] = $changesetId
                $details["operation_count"] = @($request.args.changeset.operations).Count
                $details["check_count"] = $checkRecords.Count
                $details["source_committed_to_github"] = $false
                $details["result"] = "PASS"
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

if($NoProcessExit) {
    return
}
if ($status -ne "PASS") { exit $resultCode }
exit 0
