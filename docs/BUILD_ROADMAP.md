# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | ✅ FINALIZED / FROZEN v1.2.0 |
| 03 | Repository Architecture | ✅ FINALIZED / FROZEN v1.0.0 |
| 04 | Data Protocol / Schemas | ✅ FINALIZED / FROZEN — KAT1 v1.0.0 |
| 05 | Katarina Core / Orchestrator | ✅ FINALIZED / FROZEN — Core v1.0.0 |
| 06 | MT5 Bridge EA | ✅ FINALIZED / FROZEN v1.0.0 — Bridge design v0.5.0 |
| 07 | MT5-Python Communication | ✅ FINALIZED / FROZEN v1.0.0 |
| 08 | Data Validation Engine | ✅ FINALIZED / FROZEN v1.0.0 — `PASS_STAGE08_FINAL_CLEARANCE` |
| 09 | Health & Safety Engine | ✅ FINALIZED / FROZEN v1.0.0 — `PASS_STAGE09_FINAL_CLEARANCE` |
| 10 | Database & Memory V1 | LOCAL FREEZE CANDIDATE - persistence audit PASS |
| 11 | Market Intelligence Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 12 | Multi-Timeframe Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 13 | Market Regime Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 14 | XAUUSD Specialist V1 | 🟡 IMPLEMENTED BASELINE / PASS |
| 15 | Decision Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 16 | Risk Governor | 🟡 IMPLEMENTED BASELINE / PASS |
| 17 | Position Sizing Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 18 | Execution Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 19 | Position Manager | 🟡 IMPLEMENTED BASELINE / PASS |
| 20 | Trade Evaluation Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 21 | Research Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 22 | Backtesting Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 23 | Out-of-Sample + Walk-Forward | 🟡 IMPLEMENTED BASELINE / PASS |
| 24 | Monte Carlo / Robustness | 🟡 IMPLEMENTED BASELINE / PASS |
| 25 | Tester Evaluation | IMPLEMENTED BASELINE / PASS |
| 26 | Learning Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 27 | Machine Learning V1 | 🟡 IMPLEMENTED BASELINE / PASS |
| 28 | Model Promotion & Rollback | 🟡 IMPLEMENTED BASELINE / PASS |
| 29 | Economic Intelligence Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 30 | Portfolio & Multi-Pair Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 31 | Correlation & Global Exposure Engine | 🟡 IMPLEMENTED BASELINE / PASS |
| 32 | Dashboard | 🟡 IMPLEMENTED BASELINE / PASS |
| 33 | Automated Testing / CI | 🟡 IMPLEMENTED BASELINE / PASS |
| 34 | Constitution Guard | 🟡 IMPLEMENTED BASELINE / PASS |
| 35 | MT5 Strategy Tester Integration | 🟡 IMPLEMENTED BASELINE / PASS |
| 36 | Live Environment Preflight | IMPLEMENTED BASELINE / read-only preflight |
| 37 | Stress Test | 🟡 IMPLEMENTED BASELINE / PASS |
| 38 | Live Micro-Risk Validation | GATE READY - authorization/evidence pending |
| 39 | Performance Monitoring | 🟡 IMPLEMENTED BASELINE / PASS |
| 40 | Continuous Evolution | 🟡 IMPLEMENTED BASELINE / PASS |

## Current Position

**Stages 01-09 remain frozen. Stage 10 is a local freeze candidate. Stages 11-40 have implementation baselines on the VPS. Live-capital validation remains intentionally blocked until Stage 36/38 external evidence is complete.**

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


## Frozen Stage 07 Scope

Stage 07 MT5 ↔ Python Communication is **FINALIZED / FROZEN v1.0.0**.

Frozen communication contract:

- Python owns the localhost ZeroMQ ROUTER primary endpoint;
- MT5 uses a bounded DEALER peer and one complete KAT1 frame per ZeroMQ message;
- native localhost TCP is the governed fallback and uses KAT1 `frame_length` directly, with no secondary application envelope;
- KAT1 remains the authoritative application wire contract;
- MT5 emits presence HEARTBEAT before HELLO/HELLO_ACK and presence never implies READY;
- communication readiness requires binding validation, atomic snapshot recovery and reconciliation;
- sequence namespaces remain directional and persistent across reconnect for a stable stream;
- duplicate/decreasing sequence fails closed and gaps require recovery;
- reconnect does not reset sequence state;
- queues are bounded and critical control frames are retried without sequence reallocation;
- transport endpoints are localhost-only and public bind remains prohibited;
- Stage-06 timer/queue safety budgets are preserved;
- Stage 07 does not submit broker orders and does not grant live-risk readiness.

Freeze-qualified proof completed on Windows Server 2022 x64:

- 37/37 Stage-07 Python regressions PASS;
- MQL5 KAT1 codec and 13 frozen golden vectors PASS;
- ZeroMQ ROUTER ↔ DEALER raw KAT1 roundtrip PASS;
- HEARTBEAT → HELLO → HELLO_ACK PASS;
- cross-language snapshot/reconciliation and byte equality PASS;
- persistent MT5/Python sequence continuity across process reconnect PASS;
- native TCP MQL5 ↔ Python KAT1 byte equality PASS;
- native TCP proof compiled 0 errors / 0 warnings;
- native TCP EX5 SHA-256: `c9518375d0b06736ab5f26a62ac2ec5ceadf623f1336b3eccad732ce1aeb1ce4`;
- bounded backpressure profile PASS;
- TCP loopback p99: **0.202 ms**;
- KAT1 codec decode p99: **290.3 µs**;
- inherited Stage-06 timer budget: **2000 µs**;
- final evidence-bound audit: `PASS_STAGE07_FINAL_CLEARANCE`;
- `ready_for_stage08=true`;
- `live_risk_ready=false`.

Governed final evidence:

- GitHub Actions run: `37209799384`
- evidence head SHA: `f83ab5eb6f57b2c30428122f69a807c9ace673f1`
- artifact: `stage07-final-clearance-evidence`
- artifact ID: `11306007351`
- artifact digest: `sha256:d95c9f12816017ea87291582ffdded60c0d298035ca82bc55c689e1f94df2532`
- permanent freeze record: `docs/reviews/STAGE_07_FREEZE_RECORD.md`

ADR-0009, ADR-0011 and ADR-0012 are accepted as the frozen Stage-07 communication governance.

Stage 07 is frozen. Any change to its transport topology, KAT1 framing, recovery semantics, sequence semantics or security boundary requires governed review. Live broker-risk enablement and production-readiness claims remain blocked until later roadmap stages.

## Next Stage

**Stage 08 — Data Validation Engine is FINALIZED / FROZEN v1.0.0. Stage 09 — Health & Safety Engine is active.**


## Frozen Stage 08 Scope

Stage 08 Data Validation Engine is **FINALIZED / FROZEN v1.0.0**.

Frozen guarantees:

- decoded data must pass semantic validation before authoritative promotion;
- dispositions are ACCEPT / QUARANTINE / REJECT;
- SymbolSpec revision binding is mandatory for market/position/order state;
- stale or future-clock data fails closed;
- NaN/Infinity fails closed;
- bid/ask, tick-grid and OHLC consistency are enforced;
- history completeness uses count, identity, timeframe, sequence and monotonic open-time checks;
- account/position/order critical enum and identity semantics are enforced;
- Stage 08 may set only DATA_FRESH readiness;
- Stage 08 cannot arm execution, set RISK/HEALTH readiness, size positions, create trade decisions, or submit broker orders.

Freeze-qualified proof:

- GitHub Actions run: `37211163352`
- evidence head SHA: `66fb7958416c13ca5bc16b7c38510cd71bdf86b3`
- 37/37 Stage-08 tests PASS
- final audit: `PASS_STAGE08_FINAL_CLEARANCE`
- artifact: `stage08-final-clearance-evidence`
- artifact ID: `11306556690`
- artifact digest: `sha256:adf3e17aadf7d6ad674e722d0a41781e511aeb5407541e7c7339c9500db25f3d`
- `ready_for_stage09=true`
- `live_risk_ready=false`

Any change to Stage-08 validation authority or frozen semantics requires governed review.


## Frozen Stage 09 Scope

Stage 09 Health & Safety Engine is **FINALIZED / FROZEN v1.0.0**.

Frozen guarantees:

- health states are UNKNOWN / OK / DEGRADED / BLOCKED;
- dimensions are data, transport, execution, reconciliation, journal, clock and snapshot;
- authoritative KAT1 HEALTH_EVENT drives dimension state;
- HEARTBEAT, SESSION_STATE and TRANSPORT_METRICS may only worsen safety state;
- stale heartbeat/health events fail closed;
- frozen critical queue capacity 2048 blocks health readiness;
- broker-observation freshness, session tick freshness, permission state, ping, RTT and clock skew are governed;
- decode-error increases temporarily degrade transport health;
- two consecutive all-OK health events are required before recovery readiness;
- Stage 09 may set only HEALTH readiness;
- Stage 09 cannot set RISK/EXECUTION_ARMED, approve risk, size positions, create strategy decisions or submit broker orders.

Freeze-qualified proof:

- GitHub Actions run: `37211508723`
- evidence head SHA: `5fed0dec3caaf689e149e0b34e25fa749e773caa`
- 20/20 Stage-09 tests PASS
- final audit: `PASS_STAGE09_FINAL_CLEARANCE`
- artifact: `stage09-final-clearance-evidence`
- artifact ID: `11306568221`
- artifact digest: `sha256:b008f10ae53fedb2fc018e384437ef7eea7fac6c85ebe27ad7ee20dfa0fbd690`
- `ready_for_stage10=true`
- `live_risk_ready=false`

Any change to Stage-09 health authority or frozen fail-closed semantics requires governed review.
