# MT5 verification

`Test-KatarinaBuild.ps1` compiles every EA/test in a fresh output directory. Supply MetaEditorPath, DependencyInclude (Zmq, Mql, Arrays, Trade, Object.mqh and StdLibErr.mqh), and OutputRoot. Evidence records source/include/EX5 hashes and requires zero errors/warnings.

Verified 2026-10-10: 18 MQL5 targets compiled with MetaEditor 6230; Stage06 self-test returned PASS. Windows Server 2012 R2 remains exploratory compatibility evidence. Python suite: 457 tests without failure, four local PowerShell skips covered by Windows runner checks.

The existing MT5 ALFA installation successfully ran September 2026 XAUUSD.vx M1 with 100% real ticks. The research baseline used explicit `config/mt5-research-baseline.set` inputs. Results: 136 trades, net USD -46.52, profit factor 0.89; these results do not validate profitability or live readiness. Private reports and journals remain under `C:\KatarinaDev\artifacts\mt5`.

For an existing terminal, pass `-ExistingTerminalDataPath` to `Run-KatarinaStage35Tester.ps1`; origin.txt must match the executable directory and the terminal must be stopped. Pass `-ParametersPath` to prevent reuse of cached tester parameters. The runner hashes and retains the preset, writes a uniquely named report, disables live trading, and never closes a pre-existing terminal. Portable mode remains available as a mutually exclusive option.

The imported research EA implements rule-based pullback, sweep and Fibonacci experiments. It rejects non-tester initialization and trade submission. Full AI bridge publication and end-to-end AI execution remain separate unfinished work; a successful tester run does not establish that integration.
