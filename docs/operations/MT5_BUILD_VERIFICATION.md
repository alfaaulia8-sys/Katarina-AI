# MT5 build verification

Run `scripts/mt5/Test-KatarinaBuild.ps1` with `-MetaEditorPath`, `-DependencyInclude` (containing Zmq, Mql and Arrays), and `-OutputRoot`. It compiles all repository EAs and test scripts in a fresh directory and writes `build-evidence.json` with source, include and EX5 hashes. Existing terminal programs are not replaced. Compiler processes have a bounded timeout. All targets must have zero errors/warnings and fresh nonempty artifacts.

Verified on 2026-10-10: all 17 targets compiled with MetaEditor 5.0.0.6230; the Stage06 MQL self-test ran in MT5 and returned PASS, zero failures. Python suite: 456 tests, no failures, three local PowerShell-dependent skips. This Windows Server 2012 R2 result remains exploratory compatibility evidence.

The isolated real-tick tester attempt failed before testing because its account was unspecified (exit -1000012353). Sign into a demo account in the dedicated tester installation before rerunning `scripts/stage35/Run-KatarinaStage35Tester.ps1 -Portable`. A missing report is a failure, never a successful backtest.

Build and self-test results do not validate the AI strategy. The current Stage07 bridge still has inactive market/trade publication methods, and end-to-end AI signal execution and out-of-sample strategy validation remain incomplete. Live execution is not enabled by these tools.
