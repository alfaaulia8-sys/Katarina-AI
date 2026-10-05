# Stage 35 — GitHub Prior-Art Reference

Status: SEARCHED / REVIEW INPUT  
Stage: MT5 Strategy Tester Integration

## Search intent

`MetaTrader 5 strategy tester automation MQL5`

## Selected references

1. Original roadmap reference:
   https://github.com/terrylica/mql5-crossover/blob/0c4bf7b36e922e8a19947463af1659b63042f4a5/docs/plans/STRATEGY_TESTER_BLOCKING_ISSUE.md

2. MT5 command-line tester reference:
   https://github.com/tradermonty/claude-trading-skills/blob/258e82565415f35969a70c1255eff5e8500479d7/skills/mt5-robot-tester/references/mt5-cli-reference.md

3. Headless backtest orchestration example:
   https://github.com/PHUICMT/mcp-mt5/blob/9a859e1d03d1d7222b8c05b21af3762694260838/README.md

## Patterns adopted

- launch `terminal64.exe /config:tester.ini`;
- set `ShutdownTerminal=1` so batch execution has a bounded lifecycle;
- use `Model=4` for governed real-tick evidence;
- keep `Optimization=0` for a deterministic single-run infrastructure proof;
- emit a report and evidence artifact after the tester process exits;
- treat installed MT5 build/report behavior as something that must be verified on Windows rather than assumed.

## KATARINA adaptation rule

- Reference is prior art only; code is not copied blindly.
- Frozen Stage 01–09 invariants remain authoritative.
- Python remains central intelligence.
- Strategy/risk policy is not silently finalized.
- Live risk and live execution authority remain disabled.
- Stage 35 runner is Strategy Tester infrastructure only; it contains no broker order submission path.
- Windows/MT5 runtime proof remains pending until the QEMU Windows host is ready.

## Body-build result

`BODY_FRAMEWORK_COMPLETE / TESTER_RUNNER_PREPARED / WINDOWS_PROOF_PENDING`

This does **not** mean production trading logic or live-risk validation is finalized.
