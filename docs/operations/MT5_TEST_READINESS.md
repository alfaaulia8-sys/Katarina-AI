# MT5 test readiness

Status on 2026-10-10: local regressions pass; actual MT5 compilation and real-tick strategy validation remain unverified for this change. Live trading is not enabled.

## Completed

- Baseline `af874fa`: 453 Python tests passed locally.
- Tester runner regression: 456 tests passed, including 12 simulated PowerShell terminal scenarios. These simulations do not run MT5 or measure strategy performance.
- Runner uses a unique report name and a dedicated portable terminal, rejects an already-running target terminal, and never searches other terminals for evidence.
- Missing, empty, stale reports, nonzero process exit, and timeout cannot pass the infrastructure gate.
- Evidence records hashes of the compiled EA, runner, configuration and copied report. Infrastructure PASS explicitly does not mean the strategy is validated.
- Windows CI parses the runner and runs simulated terminal tests without accessing the VPS.

## Run an actual tester verification

Use a dedicated, writable MT5 portable installation with the compiled EA under `MQL5/Experts`. Do not point this runner at an active trading terminal. Broker history must already be available. Select the actual broker symbol and explicit historical dates.

```powershell
powershell.exe -NoProfile -File scripts/stage35/Run-KatarinaStage35Tester.ps1 `
  -TerminalPath 'C:\KatarinaTester\terminal64.exe' -Portable `
  -Expert 'KatarinaTester' -Symbol 'XAUUSD' -Period M1 `
  -FromDate '2026.01.01' -ToDate '2026.02.01'
```

`KatarinaTester` is a placeholder for an actually compiled, tester-compatible EA; this command does not create one. In particular, bridge transport tests are not evidence that the Python AI strategy executes inside Strategy Tester. Validate the complete strategy path separately.

The runner creates a unique directory under `C:\KatarinaDev\stage35`, or `-OutputRoot`, with the generated INI and evidence. It requests real-tick mode and disables chart live trading. Verify report contents, actual tick coverage, transaction costs, trade count, drawdown and out-of-sample performance separately. Requested `Model=4` is not proof of complete broker tick coverage.

Parameter behavior is documented by MetaQuotes: https://www.metatrader5.com/en/terminal/help/start_advanced/start

## Current remote blocker

The connected account now resolves to `alfaauliau-katarinaAI` (same numeric owner identity as the previous `alfaaulia8-sys`). The existing private control repository reports a missing KATARINA workspace in its latest fetch result. Its VPS agent v0.3.2 only supports `status`, `katarina_git_status` and `katarina_fetch`; it has no approved compile/test operation. No unsupported job, allowlist bypass, terminal shutdown or live activation was attempted.

A working, supported verification route to the isolated Windows MT5 environment is required before claiming MT5 readiness. Local tests and a GitHub PR alone do not satisfy that requirement.
