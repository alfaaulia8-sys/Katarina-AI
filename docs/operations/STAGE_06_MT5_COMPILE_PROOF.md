# Stage 06 — MetaEditor Compile / Runtime Proof

**Status:** REQUIRED BEFORE STAGE 06 FREEZE

## Purpose

Stage 06 is intentionally not frozen from static review alone.

The MT5 bridge must be compiled by the actual MetaEditor/MQL5 compiler and the read-only self-tests must run inside MT5 before Stage 07 is allowed to depend on it.

## Prepared Script

Repository helper:

`scripts/mt5/compile_stage06.ps1`

The script:

1. copies all Katarina include files into the selected MT5 data folder;
2. copies KatarinaBridgeEA.mq5 into MQL5/Experts;
3. copies the two Stage-06 test scripts into MQL5/Scripts;
4. invokes MetaEditor;
5. stores compile logs under build/mt5;
6. fails unless each log reports zero errors.

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

All three must compile with zero errors:

- KatarinaBridgeEA.mq5
- KatarinaStage06SelfTest.mq5
- KatarinaStage06AccountProbe.mq5

Warnings should also be reviewed; Stage 06 should not be frozen with unexplained safety-relevant warnings.

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
