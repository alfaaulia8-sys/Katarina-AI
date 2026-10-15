# 2026-10-15 — Windows MT5 17-market read-only integration and activation gate

## Status (separate infrastructure and production gates)

- **PASS — 17/17 real-broker historical UTC Bid/Ask quote snapshots** and contract metadata, with no trading API.
- **PASS — 17/17 MarketDecisionBrain V3 read-only evaluations**, with zero sensor failures and 17 final **WAIT** decisions. Technical regimes are descriptive, **not** profitable signals.
- **PASS — 844 relevant Windows Python tests:** 42 integration, 636 intelligence unit, 166 risk/engine unit.
- **BLOCKED — full canonical observer execution and scheduled forward journal**, because `terminal_info().trade_allowed == true` on the existing terminal. The implementation deliberately raises `FAIL_CLOSED_TRADING_MUST_BE_DISABLED`.
- **NOT VERIFIED — full news + portfolio risk + adaptive cognition + Smart Entry/Exit in a single market-open scheduled observer cycle; independent cost-adjusted forward returns; any live trading authorization**.

GitHub source SHA under examination: `39440c95ae028be331780ae95cfe53fa4459168c` (PR #65 merged UTC data ingestion, checked out cleanly on Windows VPS). MT5 broker account type was **DEMO**; no login number or credential was recorded. Market evidence was observed on **2026-10-15**.

## Reproducible evidence

Run Windows Python from `C:\KatarinaDev\brain-runtime\Scripts\python.exe`, with the checked-out GitHub source under `C:\KatarinaFreshLab\source` and `PYTHONPATH=src`:

1. Use existing `scripts/mt5/audit_readonly_quotes.py` logic with `resolve_broker_symbols` selection and the current `last_past_quote` UTC tick reader. Results: `PASS_SINGLE_READ_ONLY_OBSERVATION`, **17 fresh quotes / 17 requested**, 0 WAIT quotes, current broker timestamp shift **+3 hours**, **17 confirming symbols**. The shift is **not** proof of historical DST behavior.
2. The one-shot test harness `C:\KatarinaFreshLab\build-proof\Katarina17BrainReadonlyAudit.py` reuses `run_decision_brain_v3.bars_for`, `causal_broker_quotes.market_event_clock`, `closed_bars_as_of_market_tick`, and `MarketDecisionBrain.evaluate`. It deliberately provides unverified news and a failed paper risk gate, never forwards a trade, and produces **17 evaluated, 17 WAIT, 0 errors**.
3. The descriptive market-state counts were `TREND_DOWN=8`, `TREND_UP=4`, `VOLATILITY_SHOCK=3`, `PULLBACK_DOWN=1`, `SIDEWAYS=1`. These are one-off research classifications, not forward evidence.
4. `python -m unittest discover -s tests/integration -p 'test_*.py' -q`: **42 passed**.
5. `python -m unittest discover -s tests/unit/intelligence -p 'test_*.py' -q`: **636 passed**.
6. `python -m unittest discover -s tests/unit/engines -p 'test_*.py' -q`: **166 passed**.
7. Running the **actual** `scripts/ai/run_contextual_market_observer.py --max-symbols 17 --no-fetch` with an isolated state directory halted at the mandatory `FAIL_CLOSED_TRADING_MUST_BE_DISABLED` guard, before any production journal or trade.

All of these are read-only broker probes or unit/integration tests. No market/pending orders were submitted by this work. A zero-position / zero-pending check was observed during the terminal safety check.

## Scheduler inventory / safe handoff

The existing single task `Katarina-MarketBrain-Observer` was repointed to the canonical GitHub checkout:
`C:\KatarinaFreshLab\source\scripts\ai\run_contextual_market_observer.py`, Python `C:\KatarinaDev\brain-runtime\Scripts\python.exe`, state journal `C:\KatarinaDev\artifacts\contextual-observer`, 17 symbols. The task remains **DISABLED** while the terminal safety condition is unmet; its original IgnoreNew behavior and other task settings were retained.

The two legacy observers `Katarina-DecisionObserver-ReadOnly` and `Katarina-AnalogMemory-Observer` remain **DISABLED**. No duplicate recurring observer has been installed. The existing MT5 session remains connected, and its Algo Trading permission has **not** been changed.

### Explicit outstanding steps

1. In the existing terminal, **verify that global Algo Trading is disabled** (`terminal_info().trade_allowed == false`); do not bypass the Python guard, change account credentials, or place broker orders. The current authorized desktop automation was unable to reliably change the terminal UI state.
2. Run a single fresh canonical observer pass against the actual live-market quote feed. Require 17/17 UTC-causal sensors, no lookahead, no false claims about verified news/costs, and inspect the journal plus `time_reference` from PR #65.
3. Only when the terminal gate and first pass succeed, enable **one** canonical observer task; leave legacy tasks disabled and review subsequent shadow outcomes as research, not broker P&L.
4. Validate real commissions/swap, forward paper restarts, multi-asset risk telemetry and Stage 35/36/38 owner gates separately before considering any production promotion.

**No live authority, validated trade expectancy, strategy profitability, or automated broker execution is claimed.**
