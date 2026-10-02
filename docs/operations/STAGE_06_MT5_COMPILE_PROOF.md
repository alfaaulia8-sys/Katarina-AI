# Stage 06 — MetaEditor Compile / Runtime Proof

**Status:** REQUIRED BEFORE STAGE 06 FREEZE

## Purpose

Stage 06 is intentionally not frozen from static review alone.

Current validation baseline is modern 64-bit Windows. Windows Server 2012 R2 is explicitly deferred and does not block Stage 06.

See:

- `docs/operations/STAGE_06_WINDOWS_COMPATIBILITY.md`

Preferred proof hosts:

- Windows Server 2022 x64;
- Windows 11 x64.

Compatibility-validation hosts:

- Windows Server 2019 x64;
- Windows Server 2016 x64;
- Windows 10 x64.

Stage 06 is intentionally not frozen from static review alone.

The MT5 bridge must be compiled by the actual MetaEditor/MQL5 compiler and the read-only self-tests must run inside MT5 before Stage 07 is allowed to depend on it.

## Prepared Script

Repository helper:

`scripts/mt5/compile_stage06.ps1`

The script:

1. validates the Windows host against the Stage-06 compatibility baseline;
2. rejects Windows Server 2012 R2 for the current freeze proof because that host is deliberately deferred;
3. copies all Katarina include files into the selected MT5 data folder;
4. copies KatarinaBridgeEA.mq5 into MQL5/Experts;
5. copies the two Stage-06 test scripts into MQL5/Scripts;
6. deletes stale EX5 artifacts before compiling;
7. invokes MetaEditor with an explicit MQL5 include root;
8. reads MetaEditor logs explicitly as UTF-16LE;
9. parses the final error/warning summary;
10. requires zero errors and zero warnings;
11. requires each EX5 artifact to exist and be non-empty;
12. records SHA-256 hashes for source and EX5 artifacts;
13. writes machine-readable evidence to `build/mt5/stage06_compile_evidence.json`.

## Windows Example

Open MT5:

~~~text
File
→ Open Data Folder
~~~

Copy that path.

Then from PowerShell in the Katarina repository:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\compile_stage06.ps1 `
  -TerminalDataPath "C:\Users\...\AppData\Roaming\MetaQuotes\Terminal\...\"
~~~

If MetaEditor is installed under a broker-specific path:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\compile_stage06.ps1 `
  -TerminalDataPath "C:\...\TerminalData" `
  -MetaEditorPath "C:\Program Files\Broker MT5\metaeditor64.exe"
~~~

## Required Compile Result

All three must satisfy the strict Stage-06 freeze policy:

~~~text
0 errors
0 warnings
EX5 exists
EX5 size > 0
SHA-256 recorded
~~~

Targets:

- KatarinaBridgeEA.mq5
- KatarinaStage06SelfTest.mq5
- KatarinaStage06AccountProbe.mq5

A stale EX5 cannot make the proof pass because the script removes prior artifacts before compile.

## Runtime Self-Test

Inside MT5 Navigator → Scripts, run:

`KatarinaStage06SelfTest`

Expected final journal line:

~~~text
Katarina Stage 06 static MQL self-tests PASSED
~~~

The test verifies local fail-closed bridge state, queue overflow behavior, FIFO queue order, execution-disabled preflight, and mandatory native SL.

## Read-Only Account Probe

Run:

`KatarinaStage06AccountProbe`

It performs no trading.

It checks:

- native account facts;
- native SymbolSpec facts;
- complete position/order snapshot;
- terminal/account health;
- broker trading-session state.

Expected final line when all required local reads succeed:

~~~text
Katarina Stage 06 account probe PASSED
~~~

The output must be retained for at least:

- one standard-like account;
- one cent-like account;

before later production compatibility claims.

This does not replace Stage 36/38 demo/live certification.

## Python Static Check

From repository root:

~~~powershell
set PYTHONPATH=src
python -m unittest tests.static.test_stage06_mt5_bridge -v
~~~

or PowerShell:

~~~powershell
$env:PYTHONPATH="src"
python -m unittest tests.static.test_stage06_mt5_bridge -v
~~~

## Freeze Evidence

Before Stage 06 freeze, record:

- MetaEditor build number;
- EA compile result;
- self-test compile result;
- account-probe compile result;
- self-test runtime result;
- account-probe result;
- standard/cent account class used;
- any warnings/corrections.

No broker credentials or personally identifying account data should be committed to the repository.


## Modern Windows Host Check

Before compile, you can run:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\check_stage06_host.ps1
~~~

Current classifications:

~~~text
Windows 11 x64          PREFERRED
Windows Server 2022     PREFERRED
Windows Server 2019     COMPATIBILITY
Windows Server 2016     COMPATIBILITY
Windows 10 x64          COMPATIBILITY
Windows Server 2012 R2  DEFERRED
32-bit Windows          UNSUPPORTED
~~~

Windows Server 2012 R2 will be revisited only after the modern-Windows project path is complete and stable.

## Compile Evidence JSON

Successful compile writes:

`build/mt5/stage06_compile_evidence.json`

Evidence includes:

- normalized Windows host;
- OS version and architecture;
- PowerShell version;
- MetaEditor file/product version;
- source SHA-256 hashes;
- compile error/warning counts;
- EX5 path/size/SHA-256;
- strict policy flags;
- final `PASS_COMPILE_PROOF` result.

This gives the final Stage-06 audit a traceable link between source, compiler host and compiled artifact.


## Recommended Entry Point

For a complete automated host-side Stage-06 check, prefer:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\verify_stage06_modern_windows.ps1 `
  -TerminalDataPath "<MT5 DATA FOLDER>" `
  -MetaEditorPath "<METAEDITOR64.EXE>"
~~~

The lower-level `compile_stage06.ps1` remains available when only compiler proof is needed.
