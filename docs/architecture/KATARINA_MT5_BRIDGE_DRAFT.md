# KATARINA MT5 BRIDGE EA — DRAFT

**Status:** IN REVIEW  
**Version:** 0.1.0  
**Stage:** 06/40

## 1. Role

The MT5 Bridge is a sensor plus deterministic safety/execution gateway. It is not a discretionary strategy.

~~~text
BROKER / MT5
     ↓
Katarina Bridge EA
     ├─ capture broker facts
     ├─ capture manual/Katarina trade lifecycle
     ├─ build complete native snapshots
     ├─ enforce local execution invariants
     └─ report actual broker state
     ↓
Stage-07 Transport
     ↓
Katarina Core / Brain
~~~

## 2. Single Bridge Instance

Baseline V1 uses one logical bridge instance per account/execution namespace.

Reasons:

- one execution journal namespace;
- one stream_id / boot_id;
- one account-wide snapshot/reconciliation owner;
- one idempotency authority;
- easier manual-trade learning across the whole account;
- avoids independent chart EAs racing to mutate the same account.

The bridge may observe multiple symbols later; it must not require one independent trading brain per chart.

## 3. Event Handler Rules

### OnInit

Responsibilities:

- validate local terminal/account prerequisites;
- initialize bridge state;
- create new boot identity;
- initialize event buffers;
- start timer;
- enter RECOVERING / NOT ARMED.

If mandatory local initialization fails, return an initialization failure code.

### OnTick

Allowed:

- capture latest tick;
- capture local timestamp;
- update a coalesced latest-tick slot;
- return.

Forbidden:

- network blocking;
- AI/model inference;
- complete account scans;
- history scans;
- order execution;
- reconciliation.

### OnTradeTransaction

Allowed:

- copy fields needed for later interpretation;
- assign local capture sequence;
- enqueue into the lossless-required transaction buffer;
- set critical-integrity failure if the buffer cannot accept the event;
- return.

Forbidden:

- assuming transaction arrival order;
- treating one event as full order truth;
- long history/reconciliation work;
- blocking transport calls.

### OnTimer

Bounded housekeeping owner:

- drain captured transaction events;
- publish/coalesce latest market state later through Stage-07 transport;
- sample account/permission health;
- process bounded transport work later;
- process bounded command work later;
- maintain heartbeat/status.

### OnDeinit

- disable new execution;
- stop timer;
- mark stopping;
- release resources.

## 4. Local Bridge State

~~~text
BOOTING
RECOVERING
READY_READONLY
READY_ARMABLE
BLOCKED
STOPPING
STOPPED
~~~

Stage 06 remains effectively read-only for external commands until communication/execution wiring is added.

## 5. Critical Integrity State

Local flags include:

- critical_event_integrity_ok;
- account_binding_ok;
- symbol_spec_ok;
- terminal_connected;
- terminal_trade_allowed;
- mql_trade_allowed;
- snapshot_available;
- transport_ready;
- reconciled;
- execution_armed.

Any critical-integrity failure closes new-risk admission.

## 6. Capture Architecture

~~~text
OnTradeTransaction
        ↓
fixed bounded critical queue
        ↓
OnTimer bounded drain
        ↓
Stage-07 transport port
~~~

~~~text
OnTick
   ↓
latest tick slot (coalesced)
   ↓
OnTimer bounded publish
~~~

Trade lifecycle is lossless-required. Ticks are latest-state/coalescible when backlogged.

## 7. Manual Trades

Manual desktop/mobile/web activity is observable where MT5 exposes raw broker reason/type fields.

Bridge rule:

- capture raw broker reason/type;
- do not destructively relabel raw evidence;
- normalized origin classification stays separate;
- manual orders/positions are read-only by default.

## 8. Snapshot Builder

A complete native snapshot must distinguish:

~~~text
VALID COMPLETE EMPTY STATE
vs
READ FAILED / SNAPSHOT UNAVAILABLE
~~~

The bridge must never convert read failure into false empty positions/orders.

Snapshot scope includes account state, symbol specs, positions, pending/open orders, relevant history watermarks, and permissions/terminal health.

## 9. Execution Gateway

Stage 06 defines the local gateway boundary but does not yet enable external live execution.

When later enabled, the sequence remains:

~~~text
binding
→ expiry/freshness
→ symbol/account capability
→ idempotency reservation
→ lot/stops/margin/exposure preflight
→ OrderCheck
→ reread critical state
→ material-change rejection
→ OrderSend once
→ OnTradeTransaction/history reconciliation
~~~

OrderSend true is never treated as final fill truth.

## 10. Mandatory Native SL

Every Katarina-owned exposure-creating MARKET/LIMIT/STOP request must already contain approved broker-native SL.

The bridge must later reject missing/invalid SL, stale SymbolSpec, unsupported order types, invalid volume rules, and binding/revision mismatches.

## 11. Hedging / Netting

The bridge reports native account mode and raw order/position facts.

Hedging may have multiple positions per symbol. Netting has one net position per symbol, with POSITION_IDENTIFIER as stable lineage and ticket as current broker handle.

## 12. Standard / Cent

The EA reports broker-native values. It performs no hard-coded cent conversion.

## 13. Transport Boundary

~~~text
Bridge
   ↓
IKatTransport
   ├─ Null / development
   ├─ ZeroMQ        Stage 07
   ├─ native TCP    Stage 07
   └─ Tester        Stage 35
~~~

Event handlers do not know concrete transport implementation details.

## 14. Failure Policy

Examples forcing BLOCKED / no new risk:

- critical transaction queue overflow;
- account identity mismatch;
- required SymbolSpec unavailable;
- invalid trade permissions;
- incomplete snapshot;
- unresolved execution outcome;
- transport/reconciliation/journal failure later.

## 15. Initial Physical Layout

~~~text
mt5/
├─ Experts/
│  └─ KatarinaBridgeEA.mq5
├─ Include/
│  └─ Katarina/
│     ├─ BridgeState.mqh
│     ├─ EventBuffer.mqh
│     └─ TransportPort.mqh
└─ Tests/
~~~

## 16. Stage 06 Acceptance Target

Before freeze, Stage 06 should prove:

- valid MQL5 event-handler architecture;
- handler work remains capture-oriented;
- critical overflow is fail-closed;
- no discretionary signal logic exists;
- transport implementation is absent/replaceable;
- startup is not live-armed;
- manual trades are observable;
- account-wide state ownership is unambiguous;
- Stage 04 KAT1 fields can be sourced from MT5.

Stage 06 is not yet frozen.
