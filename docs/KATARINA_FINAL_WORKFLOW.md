# KATARINA AI — FINAL MT5 EXECUTION WORKFLOW

**Status:** STAGE 02 — IN REVIEW  
**Version:** 1.1.0  
**Purpose:** Canonical end-to-end workflow from MT5 market data acquisition to trade execution, position management, memory, and learning.

## 1. Architectural Rule

```text
KATARINA          decides WHAT
      ↓
RISK GOVERNOR     decides WHETHER / HOW MUCH
      ↓
EXECUTION ENGINE  decides HOW TO EXECUTE SAFELY
      ↓
MT5 / BROKER      performs ACTION
      ↓
RESULT
```

MT5/MQL5 does not invent discretionary BUY/SELL decisions. If Katarina is unavailable or critical data/communication integrity fails, MT5 must not open new risk.

## 2. Canonical End-to-End Flow

```text
MT5 FAST EVENT CAPTURE
        │
        ├─ TickEvent
        ├─ BarEvent
        ├─ AccountDelta
        ├─ PositionDelta
        └─ TradeEvent
        │
        ▼
EVENT BUFFER
        │
        ▼
VERSIONED BINARY CODEC
        │
        ▼
TRANSPORT ABSTRACTION
   ┌────┴──────────┐
   │               │
 LIVE            TESTER
   │               │
ZeroMQ/TCP     TesterAdapter
   └────┬──────────┘
        ▼
KATARINA INGEST
        │
        ▼
STATE CACHE
        │
        ▼
SNAPSHOT BUILDER
        │
        ▼
DATA VALIDATION
        │
   INVALID ─────→ SAFE MODE / NO NEW RISK
        │
      VALID
        ▼
KATARINA CORE
        │
        ├─ Health Check
        ├─ Market Regime
        ├─ Multi-Timeframe Analysis
        ├─ Economic/Event Context
        ├─ Memory Retrieval
        ├─ Strategy Ensemble
        └─ Decision Engine
                 │
                 ▼
           TRADE CANDIDATE
                 │
                 ▼
            RISK GOVERNOR
          ┌──────┼──────┐
        REJECT  REDUCE APPROVE
          │       └──┬──┘
          ▼          ▼
       NO TRADE   POSITION SIZING
                     │
                     ▼
              EXECUTION INTENT
                     │
              BINARY COMMAND PATH
                     │
                     ▼
                 MT5 GATEWAY
                     │
             PRE-EXECUTION CHECK
                     │
                  OrderCheck
                     │
                  OrderSend
                     │
                     ▼
                   BROKER
                     │
                     ▼
          BROKER TRANSACTION EVENTS
                     │
                     ▼
          ORDER STATE / POSITION STATE
                     │
                     ▼
                  KATARINA
                     │
             POSITION MANAGEMENT
                     │
                     ▼
                   CLOSED
                     │
                     ▼
             EXPERIENCE / MEMORY
                     │
                     ▼
                 RESEARCH
                     │
                     ▼
             LEARNING PIPELINE
```

## 3. MT5 Event Collection

MT5 should keep realtime handlers fast and event-driven.

It collects required market/account/execution state and emits deltas rather than repeatedly sending full history on every tick.

Relevant information includes:

- symbol, bid, ask, spread, tick time/sequence;
- new/closed bars for required timeframes;
- account balance/equity/margin/free margin/leverage;
- open positions and pending orders;
- broker/server time;
- broker and bridge health;
- execution/trade transaction changes.

Historical synchronization/bootstrap may send larger state payloads when required, but this is not the normal hot path.

## 4. Transport & Codec

The authoritative policy is defined in:

- `docs/KATARINA_TRANSPORT_PROTOCOL.md`
- `config/transport_policy.json`

Binding direction:

```text
Realtime production hot path → VERSIONED BINARY
Flexible control path         → structured binary / MessagePack candidate
Live primary transport        → ZeroMQ localhost
Live fallback                 → Native local TCP
Strategy Tester               → TesterTransport adapter
Human audit/debug             → JSON
```

Katarina Core must remain independent from transport/codec implementation.

## 5. State Cache and Immutable Snapshot

Katarina maintains the latest validated state from event streams.

A decision snapshot is built internally and tied to immutable identifiers such as:

```text
snapshot_id
timestamp
symbol
sequence state
```

A stale, sequence-inconsistent, or mismatched snapshot must not be executed.

Traceability should preserve:

```text
snapshot_id
→ decision_id
→ risk_decision_id
→ execution_intent_id
→ order_id
→ broker identifiers
```

## 6. Data Validation Gateway

Validate at least:

- stale or malformed events;
- sequence gaps when material;
- missing required bars/history;
- impossible/inconsistent price state;
- spread condition;
- account state;
- transport/bridge connectivity;
- time synchronization.

Critical failure:

```text
SAFE MODE
NO NEW LIVE RISK
```

## 7. Katarina Analysis

The Brain may use:

- system/health state;
- market regime;
- multi-timeframe structure;
- economic/event context;
- memory and comparable historical conditions;
- strategy ensemble;
- uncertainty / out-of-distribution state.

The Decision Engine creates a Trade Candidate, not an order.

## 8. Trade Candidate

A candidate may include logical equivalents of:

- symbol/direction;
- entry concept;
- invalidation;
- proposed SL/TP or exit policy;
- expected risk/reward;
- calibrated probability and/or model confidence;
- evidence for/against;
- uncertainty;
- regime;
- model/strategy version;
- snapshot_id;
- expiry/validity window.

Possible actions include BUY_CANDIDATE, SELL_CANDIDATE, WAIT, HOLD, NO_TRADE, CLOSE/REDUCE candidate.

## 9. Risk Governor

Every live capital action must pass deterministic Risk Governor controls covering, as applicable:

- per-trade and aggregate open risk;
- drawdown/session/daily limits;
- symbol/currency/correlation exposure;
- margin/leverage;
- volatility/spread;
- data and execution health;
- uncertainty / out-of-domain state.

Results:

```text
REJECT / REDUCE / APPROVE
```

## 10. Position Sizing

Exact lot/size is calculated deterministically after approval using approved risk, stop distance, contract/tick values, broker lot constraints, margin constraints, and other frozen policy inputs.

## 11. Execution Intent

The final command must carry unique/traceable identifiers and logical equivalents of:

- execution_intent_id;
- order_id;
- snapshot_id / decision_id / risk_decision_id;
- symbol/side/order type;
- final lot;
- entry instruction;
- SL/TP or exit policy;
- approved risk;
- deviation/slippage rule;
- expiry;
- model/strategy version.

## 12. MT5 Pre-Execution Validation

Immediately before broker submission MT5 rechecks:

- instruction freshness;
- price deviation;
- spread;
- symbol/market/trading permission;
- lot/margin;
- approval integrity;
- duplicate order_id;
- message/protocol validity.

Then perform `OrderCheck` and only submit when valid.

Failure returns an explicit reason; MT5 must not silently turn a rejected idea into a different discretionary strategy.

## 13. Idempotency

Every execution request has a unique `order_id`.

Retransmitting the same order_id after a timeout must return the known state/ticket rather than opening another position.

## 14. Broker Execution Truth

`OrderSend` acceptance is not itself treated as final fill truth.

The authoritative execution lifecycle comes from actual broker transaction events and reconciliation.

Order state and position state are separate state machines.

Possible order states include logical equivalents of:

```text
CREATED
VALIDATED
SUBMITTING
SUBMITTED
PARTIALLY_FILLED
FILLED
REJECTED
CANCELED
EXPIRED
ERROR
```

Position states include:

```text
CREATED → ACTIVE → MANAGING → EXITING → CLOSED
```

## 15. Execution Confirmation

Store actual execution facts such as:

- order_id and broker identifiers;
- requested and fill price;
- requested and filled size;
- slippage;
- timing/latency;
- broker result/status;
- accepted SL/TP state.

## 16. Position Management

While active, Katarina continues receiving validated state and may create management decisions such as HOLD, MODIFY_SL, MODIFY_TP, PARTIAL_CLOSE, REDUCE_POSITION, CLOSE, or policy-authorized break-even actions.

Safety validation remains mandatory.

## 17. Local Emergency Safety

Local deterministic safety may block new entries, enter safe mode, cancel invalid pending state, or execute predefined emergency protections.

```text
NO KATARINA / NO VALID DATA / INVALID TRANSPORT
= NO NEW LIVE RISK
```

It does not grant MT5 permission to invent a new trading strategy.

## 18. Trade Experience

After closure, record decision context, execution facts, P/L after costs, MAE/MFE, R-multiple, duration, exit reason, regime, evidence, model/strategy version, risk decision, and relevant snapshot lineage.

## 19. Learning

```text
OBSERVE
→ RECORD
→ EVALUATE DECISION QUALITY
→ DETECT DRIFT/DEGRADATION
→ HYPOTHESIZE
→ OFFLINE TRAIN/ADJUST
→ BACKTEST
→ OUT-OF-SAMPLE
→ WALK-FORWARD
→ ROBUSTNESS
→ SHADOW/PAPER
→ COMPARE
→ APPROVED PROMOTION
→ MONITOR
→ ROLLBACK IF NEEDED
```

Live observations do not directly rewrite production behavior.

## 20. Latency Observability

The system must measure enough timing stages to identify whether delay is caused by capture, encoding, transport, decoding/ingest, analysis, decision, risk, return transport, MT5 validation, or broker execution.

Exact latency budgets will be set from profiling rather than guessed in this workflow.

## 21. Primary Safety Invariants

1. MT5 does not invent discretionary BUY/SELL decisions.
2. Every live entry requires a valid Katarina decision.
3. Every live entry requires Risk Governor approval.
4. Every execution references valid decision/snapshot lineage.
5. Every order uses idempotent unique order_id.
6. Invalid critical data/transport means NO NEW RISK.
7. Katarina failure means NO NEW RISK.
8. Learning cannot bypass validation.
9. Live capital is not a research sandbox.
10. Important decisions/executions are auditable.
11. Realtime hot-path JSON is not required.
12. Transport/codec changes must not require changing Katarina Brain.
