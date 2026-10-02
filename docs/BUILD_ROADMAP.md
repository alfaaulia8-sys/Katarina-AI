# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | ✅ FINALIZED / FROZEN v1.2.0 |
| 03 | Repository Architecture | ✅ FINALIZED / FROZEN v1.0.0 |
| 04 | Data Protocol / Schemas | ✅ FINALIZED / FROZEN — KAT1 v1.0.0 |
| 05 | Katarina Core / Orchestrator | ✅ FINALIZED / FROZEN — Core v1.0.0 |
| 06 | MT5 Bridge EA | 🟡 IN REVIEW — Bridge v0.4.0 / MODERN WINDOWS VALIDATION / COMPILE PROOF PENDING |
| 07 | MT5-Python Communication | ⬜ |
| 08 | Data Validation Engine | ⬜ |
| 09 | Health & Safety Engine | ⬜ |
| 10 | Database & Memory V1 | ⬜ |
| 11 | Market Intelligence Engine | ⬜ |
| 12 | Multi-Timeframe Engine | ⬜ |
| 13 | Market Regime Engine | ⬜ |
| 14 | XAUUSD Specialist V1 | ⬜ |
| 15 | Decision Engine | ⬜ |
| 16 | Risk Governor | ⬜ |
| 17 | Position Sizing Engine | ⬜ |
| 18 | Execution Engine | ⬜ |
| 19 | Position Manager | ⬜ |
| 20 | Trade Evaluation Engine | ⬜ |
| 21 | Research Engine | ⬜ |
| 22 | Backtesting Engine | ⬜ |
| 23 | Out-of-Sample + Walk-Forward | ⬜ |
| 24 | Monte Carlo / Robustness | ⬜ |
| 25 | Shadow Katarina | ⬜ |
| 26 | Learning Engine | ⬜ |
| 27 | Machine Learning V1 | ⬜ |
| 28 | Model Promotion & Rollback | ⬜ |
| 29 | Economic Intelligence Engine | ⬜ |
| 30 | Portfolio & Multi-Pair Engine | ⬜ |
| 31 | Correlation & Global Exposure Engine | ⬜ |
| 32 | Dashboard | ⬜ |
| 33 | Automated Testing / CI | ⬜ |
| 34 | Constitution Guard | ⬜ |
| 35 | MT5 Strategy Tester Integration | ⬜ |
| 36 | Paper / Demo Trading | ⬜ |
| 37 | Stress Test | ⬜ |
| 38 | Live Micro-Risk Validation | ⬜ |
| 39 | Performance Monitoring | ⬜ |
| 40 | Continuous Evolution | ⬜ |

## Current Position

**Stage 06 — MT5 Bridge EA — is active and in review.**

## Frozen Stage 04 Scope

KAT1 v1.0.0 now freezes:

- canonical little-endian binary framing;
- exact 30-message registry and payload layouts;
- scaled execution-sensitive numeric representation;
- explicit identity/revision binding;
- standard + cent account-native handling;
- shared-account/manual-trade learning visibility;
- Hedging + Netting account support;
- MARKET + LIMIT + STOP entries;
- mandatory broker-native SL for Katarina exposure;
- first-class account ledger;
- chunked atomic snapshots;
- CRC32C/conformance rules;
- 13 canonical golden vectors.


## Frozen Stage 05 Scope

Implemented:

- immutable internal EventEnvelope / priorities;
- explicit lifecycle state machine;
- deterministic component dependency ordering;
- BOOTSTRAP vs RUNTIME phases;
- lifecycle-scoped internal event subscriptions;
- deterministic serial EventBus;
- bounded priority ingress;
- readiness gate separate from lifecycle;
- explicit live-risk admission gate;
- orchestration runtime status;
- central KatarinaOrchestrator;
- 16 standard-library unit tests.

Current rule:

```text
RUNNING != LIVE TRADING ALLOWED
```

New live risk additionally requires fresh/healthy/reconciled/risk-ready state and explicit execution arming.

Stage 05 is frozen as Core v1.0.0.


## Stage 06 In-Review Scope

Implemented so far:

- capture-only OnTick / OnTradeTransaction;
- bounded lossless-required trade-event queue;
- latest-tick coalescing;
- complete account/position/order snapshot source;
- local duplicate-instance lease;
- approved-vs-observed symbol registry;
- raw manual order/deal/position reason evidence;
- terminal/account/session health source;
- standard/cent broker-native account and SymbolSpec facts;
- deal-history source for account ledger;
- broker OrderCalcProfit / OrderCalcMargin source;
- broker bar source through CopyRates;
- local MARKET/LIMIT/STOP preflight with mandatory native SL;
- KAT1 field-source mapping;
- MQL self-test + read-only account probe;
- Python static bridge-safety test;
- Windows MetaEditor compile-proof script;
- type-aware MqlTradeTransaction validity bitmap;
- persistent stream/per-boot bridge identity;
- broker-server + login scoped duplicate lease;
- strengthened pending/TP preflight;
- 15 bridge static safety regression tests;
- 10 Windows compatibility regression tests;
- modern-Windows host preflight;
- strict MetaEditor UTF-16LE log parser;
- zero-warning compile policy;
- fresh EX5 existence + SHA-256 evidence;
- Windows Server 2012 R2 explicitly deferred.

Production broker mutation remains disabled and the bridge remains RECOVERING.

Remaining freeze blocker: actual MetaEditor compilation/runtime proof on a modern 64-bit Windows validation host, followed by self-test/account probes and final audit. Windows Server 2012 R2 is explicitly deferred and does not block Stage 06.

Stage 06 is not frozen yet.
