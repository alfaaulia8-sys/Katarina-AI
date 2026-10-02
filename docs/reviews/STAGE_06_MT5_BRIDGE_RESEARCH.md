# STAGE 06 — MT5 BRIDGE EA RESEARCH

**Stage:** 06/40  
**Status:** IN REVIEW  
**Reviewed:** 2026-10-02

## Goal

Build the MT5-side sensor and deterministic execution gateway without turning MQL5 into a second trading brain.

Stage 06 must preserve the frozen Stage 02/04/05 boundaries:

- MT5 observes broker/terminal truth;
- Katarina/Python decides;
- Risk Governor approval remains external to the EA;
- live execution is fail-closed;
- KAT1 remains the canonical cross-language contract;
- transport implementation remains Stage 07.

## Official MQL5 Findings

### OnInit / OnDeinit

Official MQL5 documentation recommends the integer-returning OnInit so initialization failure can be reported and the EA unloaded safely. OnDeinit(reason) is the canonical cleanup point.

Katarina implication:

- validate local prerequisites before successful init;
- install timers/resources only after local setup succeeds;
- stop bridge activity deterministically in OnDeinit.

### OnTick

OnTick is an EA event handler for a new quote.

Katarina implication: capture only. No AI, history scan, blocking communication, account-wide reconciliation, or model computation.

### OnTimer / EventSetMillisecondTimer

MQL5 provides per-program Timer events and a millisecond timer. The documentation notes that if a Timer event is already queued or processing, a new Timer event is not added.

Katarina implication:

- Timer is suitable for bounded housekeeping/drain work;
- Timer frequency is not a guaranteed hard realtime scheduler;
- work per Timer callback must remain bounded.

### OnTradeTransaction

Official documentation is especially important:

- manual GUI trades also generate trade transactions;
- pending/stop activation and server-side operations generate transactions;
- one trade request may generate multiple transaction events;
- transaction arrival priority/order is not guaranteed;
- account state can change while the handler is running;
- the transaction queue contains 1024 elements and slow handling can allow older events to be superseded.

Katarina implication: OnTradeTransaction must do minimal capture/enqueue and return quickly.

It must not assume:

~~~text
one request = one transaction
or
transaction arrival order = business lifecycle order
~~~

Reconciliation remains authoritative.

### OrderSend

Official documentation states that OrderSend() returning true does not prove successful final execution.

Frozen rule remains:

~~~text
OrderSend boolean != final fill truth
~~~

Final truth comes from result codes, trade transactions, history, current broker state, and reconciliation.

### Account / Symbol Facts

MQL5 exposes account and symbol properties through AccountInfo* and SymbolInfo*.

These remain the source of broker-native facts needed for standard/cent accounts, margin/account mode, contract size, tick size/value, volume rules, trade/filling/order modes, and stops/freeze rules.

## GitHub Patterns Reviewed

### parrondo/mql5-json-api

Useful pattern:

- separates request/reply and automatically streamed events;
- exposes OnTradeTransaction data;
- reconnect/history refresh is explicit.

Katarina adopts conceptual separation between commands and streamed broker events, but not JSON as the authoritative production hot path.

### microqqq/arbi-nautilus

Useful patterns:

- explicit account/EA/stream/boot binding;
- snapshot/recovery;
- execution journal;
- UNKNOWN outcomes;
- no blind retry;
- reconciliation blocks execution until state is proven.

These semantics already match frozen Stages 02/04 and must remain true in the EA.

### dingmaotu/mql-zmq

Useful lesson: ZeroMQ is practical from MQL, but blocking receive paths can block the MQL event thread.

Katarina therefore keeps transport out of event handlers and defers concrete ZeroMQ/TCP implementation to Stage 07.

## Stage 06 Design Direction

~~~text
ONE EA INSTANCE PER ACCOUNT / EXECUTION NAMESPACE
        |
        +-- FAST EVENT CAPTURE
        |    +-- OnTick
        |    +-- OnTradeTransaction
        |
        +-- LOCAL BROKER STATE READERS
        +-- SNAPSHOT BUILDER
        +-- CRITICAL EVENT BUFFER
        +-- LATEST-MARKET COALESCER
        +-- LOCAL SAFETY STATE
        +-- EXECUTION GATEWAY INTERFACE
        +-- TRANSPORT PORT (NO NETWORK IMPLEMENTATION YET)
~~~

## Important Bridge Rule

The EA starts not armed for execution.

Stage 06 creates the sensor/gateway structure. Stage 07 communication and later execution stages must prove the full readiness chain before any external command can create live risk.

## Stage 06 Scope

Implement now:

- EA lifecycle skeleton;
- bridge state;
- fast tick capture;
- fast trade-transaction capture;
- bounded critical queue;
- coalesced latest tick;
- transport-neutral port;
- local fail-closed status;
- account/symbol fact reader interfaces;
- snapshot/execution gateway architecture.

Do not implement now:

- ZeroMQ/TCP transport;
- Python connection;
- AI/strategy/risk policy;
- production execution admission;
- persistent request journal;
- broker-specific certification.
