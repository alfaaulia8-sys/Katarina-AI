# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | ✅ FINALIZED / FROZEN v1.2.0 |
| 03 | Repository Architecture | ✅ FINALIZED / FROZEN v1.0.0 |
| 04 | Data Protocol / Schemas | ✅ FINALIZED / FROZEN — KAT1 v1.0.0 |
| 05 | Katarina Core / Orchestrator | ✅ FINALIZED / FROZEN — Core v1.0.0 |
| 06 | MT5 Bridge EA | ✅ FINALIZED / FROZEN v1.0.0 — Bridge design v0.5.0 |
| 07 | MT5-Python Communication | 🟡 IMPLEMENTATION ACTIVE — Python session/TCP + MQL5 KAT1 baseline PASS |
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

**Stage 06 is FINALIZED / FROZEN v1.0.0. Stage 07 communication development may now proceed against the frozen Bridge v0.5.0 contract.**

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


## Frozen Stage 06 Scope

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
- 25 bridge static safety regression tests;
- 10 Windows compatibility regression tests;
- count + microsecond timer budget;
- queue/tick/timer backpressure observability;
- finite-number + broker tick-grid preflight;
- FILE_COMMON MQL runtime evidence;
- standard/cent typed evidence collector;
- GitHub prior-art gap audit;
- complete MQL source-manifest binding in compile evidence;
- stale/version-mismatched runtime-proof rejection;
- final evidence-bound audit script;
- one-command end-to-end Stage-06 clearance runner;
- modern-Windows host preflight;
- strict MetaEditor UTF-16LE log parser;
- zero-warning compile policy;
- fresh EX5 existence + SHA-256 evidence;
- Windows Server 2012 R2 explicitly deferred.

Production broker mutation remains disabled and the bridge remains RECOVERING.

Freeze-qualified proof completed on Windows Server 2022 x64:

- MetaEditor 5.0.0.6235 strict compile;
- 0 errors / 0 warnings for Bridge EA, SelfTest and AccountProbe;
- non-empty EX5 artifacts;
- modern-host MQL self-test PASS;
- 35/35 Stage-06 static regressions PASS;
- complete MQL source-manifest binding PASS;
- final evidence-bound audit `PASS_STAGE06_FINAL_CLEARANCE`;
- freeze artifact provenance recorded in `docs/reviews/STAGE_06_FREEZE_RECORD.md`.

Per ADR-0010 and the frozen Stage-04 account-compatibility contract, real STANDARD_LIKE and CENT_LIKE broker validation is deferred to Stage 36/38 and is not a Stage-06 freeze blocker.

Windows Server 2012 R2 remains deferred and was not used as freeze-qualified evidence.

Stage 06 is FINALIZED / FROZEN v1.0.0.


## Stage 07 Active Scope

Completed/started without crossing the Stage-06 external-proof boundary:

- GitHub prior-art research for MQL5/Python ZeroMQ communication;
- localhost ZeroMQ ROUTER (Python) / DEALER (MT5) topology draft;
- native localhost TCP fallback design using native KAT1 frame_length;
- initial HEARTBEAT → HELLO → HELLO_ACK route/handshake design;
- application-owned Python TransportPort;
- bounded in-memory transport adapter for tests;
- Python schema-driven KAT1 codec;
- Stage-04 golden-vector round-trip tests;
- Stage-07 communication config draft;
- ADR-0009 proposed;
- fail-closed Python session supervisor PASS;
- localhost native TCP KAT1 fallback (Python side) PASS;
- MQL5 KAT1 header/CRC32C codec baseline PASS;
- 13/13 MQL5 golden-vector validation PASS on Windows Server 2022.

Stage-06 clearance is complete. Production MQL5 ZeroMQ/TCP transport implementation may now proceed under the frozen Stage-06 bridge contract; live broker-risk enablement remains governed by later stages.
