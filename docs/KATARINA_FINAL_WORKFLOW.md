# KATARINA AI — FINAL MT5 EXECUTION WORKFLOW

**Status:** FROZEN BASELINE  
**Version:** 1.0.0  
**Purpose:** This document is the canonical end-to-end workflow from MT5 market data acquisition to trade execution, position management, memory, and learning. Future development must follow this direction unless the human Project Owner intentionally versions and changes it.

---

## 1. Architectural Rule

Katarina is the central intelligence.

```text
KATARINA
   |
   | decides WHAT
   v
RISK GOVERNOR
   |
   | decides HOW MUCH / WHETHER ALLOWED
   v
EXECUTION ENGINE
   |
   | decides HOW TO EXECUTE SAFELY
   v
MT5 / BROKER
   |
   | performs ACTION
   v
RESULT
```

MT5/MQL5 does not independently invent BUY/SELL decisions. It acts primarily as:

- market/account sensor;
- communication bridge;
- deterministic safety layer;
- execution engine;
- execution/result reporter.

If Katarina is unavailable or critical data is invalid, MT5 must not open new risk.

---

## 2. Canonical End-to-End Flow

```text
MT5
│
├─ Receive Tick / Timer Event
├─ Collect Market Data
├─ Collect Account Data
├─ Collect Position / Order State
└─ Build Market Snapshot
        │
        v
DATA VALIDATOR
        │
   ┌────┴────┐
   │         │
 INVALID    VALID
   │         │
   v         v
SAFE MODE  KATARINA CORE
NO TRADE      │
              ├─ Health Check
              ├─ Market Regime
              ├─ Multi-Timeframe Analysis
              ├─ Economic / Event Context
              ├─ Memory Retrieval
              ├─ Strategy Ensemble
              └─ Decision Engine
                    │
                    v
              TRADE CANDIDATE
                    │
                    v
               RISK GOVERNOR
                    │
          ┌─────────┼─────────┐
          v         v         v
       REJECT     REDUCE    APPROVE
          │         │         │
          v         └────┬────┘
       NO TRADE           v
                   POSITION SIZING
                          │
                          v
                       ORDER PLAN
                          │
                          v
                 PRE-EXECUTION CHECK
                          │
                  ┌───────┴───────┐
                  v               v
                REJECT           VALID
                  │               │
                  v               v
              RE-ANALYZE     MT5 EXECUTOR
                                  │
                                  v
                                BROKER
                                  │
                                  v
                  FILLED / REJECTED / ERROR
                                  │
                                  v
                        EXECUTION CONFIRMATION
                                  │
                                  v
                         POSITION STATE MACHINE
                                  │
                                  v
                         POSITION MANAGEMENT
                                  │
                                  v
                              EXIT / CLOSE
                                  │
                                  v
                              TRADE LOG
                                  │
                                  v
                               MEMORY
                                  │
                                  v
                           RESEARCH LAB
                                  │
                                  v
                         LEARNING PIPELINE
```

---

## 3. MT5 Market and Account Collection

Katarina Bridge EA should collect the data required by the active specialist model, including where available:

### Market
- symbol;
- bid / ask;
- spread;
- point / digits;
- tick size / tick value;
- tick data;
- M1 / M5 / M15 / M30 / H1 / H4 candles;
- tick volume;
- real volume when provided;
- broker/server time;
- session context.

### Account
- balance;
- equity;
- margin;
- free margin;
- leverage;
- open positions;
- pending orders;
- floating P/L;
- trading history relevant to current state.

### Infrastructure
- MT5 connection state;
- bridge state;
- broker connection;
- latency / response time;
- last valid tick time.

---

## 4. Market Snapshot

Each request to Katarina must be tied to an immutable snapshot identity.

Minimum identity:

```text
snapshot_id
timestamp
symbol
sequence_number
```

A snapshot must also include the market, account, position, execution-health, and strategy-required context.

Katarina decisions must reference the exact snapshot from which they were generated.

A stale or mismatched snapshot must not be executed.

---

## 5. Data Validation Gateway

Before reasoning, validate:

- missing or malformed candles;
- stale timestamp;
- price consistency;
- abnormal or impossible bid/ask;
- required history availability;
- spread condition;
- account data validity;
- bridge connectivity;
- tick continuity;
- time synchronization.

Critical failure:

```text
DATA INVALID
→ SAFE MODE
→ NO NEW LIVE RISK
```

Existing positions remain subject to predefined safety management.

---

## 6. Katarina Health Check

Before accepting a new trade decision, critical systems must report healthy state:

- Katarina Core;
- Market Engine;
- Risk Engine / Risk Governor;
- Memory / database;
- active model;
- MT5 Bridge;
- execution channel;
- data freshness.

Critical health failure:

```text
NO NEW TRADE
```

---

## 7. Market Understanding

Katarina should determine the market regime before entry logic.

Examples:

- TRENDING;
- RANGING;
- BREAKOUT;
- REVERSAL;
- HIGH VOLATILITY;
- LOW VOLATILITY;
- NEWS SHOCK;
- ABNORMAL / UNSAFE.

Strategy selection must be conditional on regime rather than forcing one strategy into every market condition.

---

## 8. Multi-Timeframe Reasoning

Default logical hierarchy:

```text
H4 → macro / major context
H1 → primary structure
M15 → trading structure
M5 → setup
M1 → precision entry
Tick → execution timing
```

The specialist model may adapt this hierarchy by instrument, but changes must remain auditable and validated.

---

## 9. Economic and Event Context

Where data is available, Katarina may use:

- USD conditions;
- rates and yields;
- central-bank events;
- inflation and employment events;
- economic calendar;
- major scheduled news;
- relevant risk-on / risk-off context.

Economic context can alter confidence, risk, or NO TRADE behavior and does not need to be the direct trigger.

---

## 10. Memory Retrieval

Before finalizing a candidate, Katarina may retrieve comparable historical situations based on factors such as:

- symbol;
- session;
- regime;
- structure;
- volatility;
- setup type;
- spread / execution state;
- correlated exposure;
- similar feature vectors.

Relevant historical measures may include:

- sample count;
- net expectancy after costs;
- MAE;
- MFE;
- R-multiple;
- failure modes;
- regime-specific stability.

---

## 11. Strategy Ensemble

Katarina may combine multiple specialist views, for example:

- trend;
- breakout;
- pullback;
- liquidity;
- mean reversion;
- statistical models;
- machine-learning models.

The Decision Engine combines evidence and uncertainty. No single model automatically receives unrestricted authority over live execution.

---

## 12. Decision Engine Output

The Decision Engine does **not** send an order directly.

It creates a **Trade Candidate**, which may include:

```text
symbol
direction
entry concept
invalidation
proposed SL
proposed TP / exit logic
expected R
calibrated probability / confidence
market regime
evidence for
evidence against
uncertainty
model version
snapshot_id
expiry / validity window
```

Possible decisions include:

- BUY_CANDIDATE;
- SELL_CANDIDATE;
- HOLD;
- WAIT;
- NO_TRADE;
- CLOSE / REDUCE candidate for active positions.

---

## 13. Risk Governor

Every live trade candidate must pass the Risk Governor.

Risk Governor evaluates deterministically:

- balance / equity;
- per-trade risk;
- total open risk;
- drawdown;
- daily / session limits;
- symbol exposure;
- currency exposure;
- correlation;
- margin;
- leverage;
- stop distance;
- volatility;
- spread;
- data quality;
- execution health.

Permitted results:

```text
REJECT
REDUCE
APPROVE
```

The Risk Governor is non-bypassable.

---

## 14. Position Sizing

After approval, exact lot sizing is calculated deterministically from:

- approved monetary / percentage risk;
- stop distance;
- tick value / contract specification;
- broker lot minimum;
- lot step;
- lot maximum;
- margin constraints.

The AI may recommend risk, but must not invent unsupported lot sizes.

---

## 15. Order Plan / Execution Intent

Only after approval does the system create the final Execution Intent.

Minimum fields:

```text
order_id
snapshot_id
symbol
side
order_type
final_lot
entry_instruction
SL
TP / exit policy
approved_risk
max_slippage / deviation rule
expiry
model_version
strategy_version
```

The order_id must be globally unique within the trading system.

---

## 16. MT5 Pre-Execution Validation

Immediately before OrderSend / equivalent execution, MT5 rechecks:

- instruction not expired;
- snapshot / instruction still valid;
- symbol correct;
- market open;
- current price within allowed deviation;
- spread within allowed condition;
- lot valid;
- margin sufficient;
- trading permission enabled;
- Risk Governor approval present;
- order_id not previously executed;
- no malformed parameters.

Failure returns an explicit rejection reason to Katarina.

MT5 must not silently modify the strategy decision beyond explicitly authorized deterministic safety adjustments.

---

## 17. Anti-Duplicate / Idempotency Protection

Every execution request uses the unique `order_id`.

If communication times out after the broker already executed an order, retransmission with the same `order_id` must not create another position.

Expected behavior:

```text
ORDER_ID already executed
→ return existing ticket / execution state
→ DO NOT duplicate
```

---

## 18. Broker Execution

After all checks pass:

```text
Katarina Execution Intent
        ↓
MT5 Execution Engine
        ↓
Broker
```

Possible outcomes include:

- FILLED;
- PARTIALLY_FILLED where supported;
- REJECTED;
- REQUOTE / PRICE_CHANGED;
- EXPIRED;
- ERROR.

All outcomes must be returned to Katarina.

---

## 19. Execution Confirmation

Confirmation should capture at least:

```text
order_id
ticket / position_id
requested_price
fill_price
requested_lot
filled_lot
slippage
latency
broker result code
timestamp
SL / TP accepted state
```

Execution quality becomes part of the permanent trade record.

---

## 20. Position State Machine

Canonical position states:

```text
CREATED
  ↓
ACTIVE
  ↓
MANAGING
  ↓
PARTIAL / MODIFY / HOLD
  ↓
EXITING
  ↓
CLOSED
```

State transitions must be logged and tied to decision IDs / snapshots.

---

## 21. Position Management

While a position is active, Katarina continues to receive current market and position state.

Possible management instructions include:

- HOLD;
- MODIFY_SL;
- MODIFY_TP;
- PARTIAL_CLOSE;
- MOVE_TO_BE where strategy allows;
- REDUCE_POSITION;
- CLOSE.

Management actions remain subject to deterministic validation and safety rules.

---

## 22. Local Emergency Safety

Certain protective actions must not depend on a probabilistic AI response.

Examples:

- block new entries;
- cancel invalid pending orders;
- enter SAFE MODE;
- stop new exposure when critical data or connection integrity fails;
- execute predefined emergency protection required by the frozen risk policy.

Important invariant:

```text
NO KATARINA / NO VALID DATA
≠ MT5 trades independently

NO KATARINA / NO VALID DATA
= NO NEW LIVE RISK
```

---

## 23. Trade Closure and Experience Record

After closure, record:

- trade / position ID;
- symbol;
- side;
- entry and exit;
- size;
- gross P/L;
- commission;
- swap where relevant;
- execution costs;
- net P/L;
- holding duration;
- MAE;
- MFE;
- R-multiple;
- exit reason;
- market regime;
- decision evidence;
- model / strategy version;
- snapshot history relevant to the trade.

This becomes a **Trade Experience** object for future research.

---

## 24. Memory and Learning

Live results go to Memory and Research, not directly into uncontrolled live self-editing.

Canonical learning path:

```text
OBSERVE
  ↓
RECORD
  ↓
EVALUATE
  ↓
HYPOTHESIZE
  ↓
OFFLINE TRAIN / ADJUST
  ↓
BACKTEST
  ↓
OUT-OF-SAMPLE TEST
  ↓
WALK-FORWARD
  ↓
ROBUSTNESS / MONTE CARLO
  ↓
SHADOW / PAPER
  ↓
COMPARE
  ↓
APPROVED PROMOTION
  ↓
LIVE
  ↓
MONITOR
  ↓
ROLLBACK IF DEGRADED
```

A win or loss by itself must never rewrite the live strategy.

---

## 25. Primary Safety Invariants

1. MT5 does not invent discretionary BUY/SELL decisions.
2. Every live entry requires a valid Katarina decision.
3. Every live entry requires Risk Governor approval.
4. Every order references a valid, non-stale snapshot.
5. Every order uses an idempotent unique order_id.
6. Invalid critical data means NO NEW RISK.
7. Katarina failure means NO NEW RISK.
8. Learning cannot bypass the validation pipeline.
9. Live capital is not the research sandbox.
10. All important decisions and executions are auditable.

---

## 26. Frozen Direction

This workflow is the implementation baseline for:

- Python architecture;
- MQL5 bridge;
- communication protocol;
- database schema;
- risk engine;
- execution engine;
- dashboard;
- tests;
- backtesting;
- future specialist models.

Any future module must map clearly to one or more stages in this workflow.

Changes require intentional human-owner review and a version increment.
