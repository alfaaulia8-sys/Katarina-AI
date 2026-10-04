param(
    [Parameter(Mandatory=$true)][string]$TerminalPath,
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$ExpectedUser,
    [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 90,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $TerminalPath -PathType Leaf)) {
    throw "MT5 terminal not found: $TerminalPath"
}
if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "MT5 startup config not found: $ConfigPath"
}
if ($TimeoutSeconds -lt 5 -or $TimeoutSeconds -gt 300) {
    throw "TimeoutSeconds must be between 5 and 300."
}

$source=@'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class KatarinaInteractiveProcess
{
    private enum WTS_CONNECTSTATE_CLASS
    {
        WTSActive = 0,
        WTSConnected = 1,
        WTSConnectQuery = 2,
        WTSShadow = 3,
        WTSDisconnected = 4,
        WTSIdle = 5,
        WTSListen = 6,
        WTSReset = 7,
        WTSDown = 8,
        WTSInit = 9
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WTS_SESSION_INFO
    {
        public Int32 SessionID;
        public IntPtr pWinStationName;
        public WTS_CONNECTSTATE_CLASS State;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
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
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public Int32 dwProcessId;
        public Int32 dwThreadId;
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSEnumerateSessions(
        IntPtr hServer, Int32 Reserved, Int32 Version,
        out IntPtr ppSessionInfo, out Int32 pCount);

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSQueryUserToken(UInt32 sessionId, out IntPtr Token);

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool CreateEnvironmentBlock(
        out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessAsUser(
        IntPtr hToken,
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        UInt32 dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern UInt32 WaitForSingleObject(
        IntPtr hHandle, UInt32 dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(
        IntPtr hProcess, out UInt32 lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(
        IntPtr hProcess, UInt32 uExitCode);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr hObject);

    private const UInt32 CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    private const UInt32 CREATE_NEW_CONSOLE = 0x00000010;
    private const UInt32 WAIT_TIMEOUT = 0x00000102;

    public static int Run(
        string application,
        string arguments,
        string workingDirectory,
        string expectedUserLeaf,
        int timeoutMilliseconds,
        out int sessionId,
        out string userName)
    {
        sessionId = -1;
        userName = "";
        IntPtr sessionBuffer = IntPtr.Zero;
        Int32 count = 0;

        if (!WTSEnumerateSessions(
                IntPtr.Zero, 0, 1, out sessionBuffer, out count))
            throw new InvalidOperationException(
                "WTSEnumerateSessions failed: " +
                Marshal.GetLastWin32Error());

        try
        {
            int size = Marshal.SizeOf(typeof(WTS_SESSION_INFO));

            for (int i = 0; i < count; i++)
            {
                IntPtr current = new IntPtr(
                    sessionBuffer.ToInt64() + (long)(i * size));
                WTS_SESSION_INFO info =
                    (WTS_SESSION_INFO)Marshal.PtrToStructure(
                        current, typeof(WTS_SESSION_INFO));

                if (info.State != WTS_CONNECTSTATE_CLASS.WTSActive &&
                    info.State != WTS_CONNECTSTATE_CLASS.WTSConnected &&
                    info.State != WTS_CONNECTSTATE_CLASS.WTSDisconnected)
                    continue;

                IntPtr token = IntPtr.Zero;
                if (!WTSQueryUserToken((UInt32)info.SessionID, out token))
                    continue;

                try
                {
                    string identity = new WindowsIdentity(token).Name;
                    string leaf = identity;
                    int slash = identity.LastIndexOf('\\');
                    if (slash >= 0 && slash + 1 < identity.Length)
                        leaf = identity.Substring(slash + 1);

                    if (!String.Equals(
                            leaf,
                            expectedUserLeaf,
                            StringComparison.OrdinalIgnoreCase))
                        continue;

                    IntPtr environment = IntPtr.Zero;
                    if (!CreateEnvironmentBlock(
                            out environment, token, false))
                        throw new InvalidOperationException(
                            "CreateEnvironmentBlock failed: " +
                            Marshal.GetLastWin32Error());

                    try
                    {
                        STARTUPINFO si = new STARTUPINFO();
                        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
                        si.lpDesktop = "winsta0\\default";
                        PROCESS_INFORMATION pi =
                            new PROCESS_INFORMATION();

                        StringBuilder command = new StringBuilder();
                        command.Append('"')
                               .Append(application)
                               .Append('"');
                        if (!String.IsNullOrEmpty(arguments))
                            command.Append(' ').Append(arguments);

                        bool created = CreateProcessAsUser(
                            token,
                            application,
                            command,
                            IntPtr.Zero,
                            IntPtr.Zero,
                            false,
                            CREATE_UNICODE_ENVIRONMENT |
                                CREATE_NEW_CONSOLE,
                            environment,
                            workingDirectory,
                            ref si,
                            out pi);

                        if (!created)
                            throw new InvalidOperationException(
                                "CreateProcessAsUser failed: " +
                                Marshal.GetLastWin32Error());

                        try
                        {
                            sessionId = info.SessionID;
                            userName = identity;

                            UInt32 wait = WaitForSingleObject(
                                pi.hProcess,
                                (UInt32)timeoutMilliseconds);

                            if (wait == WAIT_TIMEOUT)
                            {
                                TerminateProcess(pi.hProcess, 124);
                                throw new TimeoutException(
                                    "Interactive MT5 process timed out.");
                            }

                            UInt32 code = 0;
                            if (!GetExitCodeProcess(
                                    pi.hProcess, out code))
                                throw new InvalidOperationException(
                                    "GetExitCodeProcess failed: " +
                                    Marshal.GetLastWin32Error());

                            return unchecked((int)code);
                        }
                        finally
                        {
                            if (pi.hThread != IntPtr.Zero)
                                CloseHandle(pi.hThread);
                            if (pi.hProcess != IntPtr.Zero)
                                CloseHandle(pi.hProcess);
                        }
                    }
                    finally
                    {
                        if (environment != IntPtr.Zero)
                            DestroyEnvironmentBlock(environment);
                    }
                }
                finally
                {
                    CloseHandle(token);
                }
            }
        }
        finally
        {
            if (sessionBuffer != IntPtr.Zero)
                WTSFreeMemory(sessionBuffer);
        }

        throw new InvalidOperationException(
            "No logged-in Windows session matched user: " +
            expectedUserLeaf);
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

$terminalResolved=(Resolve-Path -LiteralPath $TerminalPath).Path
$configResolved=(Resolve-Path -LiteralPath $ConfigPath).Path
$sessionId=-1
$sessionUser=""

$exitCode=[KatarinaInteractiveProcess]::Run(
    $terminalResolved,
    ('/config:"'+$configResolved+'"'),
    (Split-Path -Parent $terminalResolved),
    $ExpectedUser,
    ($TimeoutSeconds*1000),
    [ref]$sessionId,
    [ref]$sessionUser
)

[ordered]@{
    schema_version=1
    terminal=$terminalResolved
    config=$configResolved
    expected_user=$ExpectedUser
    session_id=$sessionId
    session_user=$sessionUser
    terminal_exit_code=$exitCode
    result="PASS"
} | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8

exit 0
