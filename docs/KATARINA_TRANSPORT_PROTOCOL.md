# KATARINA AI — TRANSPORT & CODEC POLICY

**Status:** APPROVED FOR STAGE 02  
**Version:** 1.0.0  
**Authority:** Human Project Owner  
**Scope:** MT5 ↔ Katarina communication architecture. Exact field layouts are defined later in Stage 04 Data Protocol / Schemas.

## 1. Core Rule

Katarina's intelligence must be independent from the transport and serialization technology.

```text
KATARINA CORE
    │
    ▼
TRANSPORT INTERFACE
    │
    ├── LiveTransport
    └── TesterTransport
```

Replacing ZeroMQ, TCP, the tester adapter, or the codec must not require changes to Market Intelligence, Decision Engine, Risk Governor, Memory, or Learning.

## 2. Production Realtime Policy

The production realtime hot path uses **binary payloads from day one**.

JSON is **not** the authoritative realtime wire format.

```text
MT5 Event
  ↓
Event Buffer
  ↓
Binary Encoder
  ↓
Local Transport
  ↓
Binary Decoder
  ↓
Katarina Ingest
```

### Hot-path messages

High-frequency messages should use a fixed/versioned binary representation:

- TickEvent
- BarEvent
- AccountDelta
- PositionDelta
- TradeEvent
- Heartbeat / HealthEvent

The exact binary field layout is intentionally deferred to Stage 04.

## 3. Flexible Command Policy

Lower-frequency messages whose structure may evolve more often may use a structured binary codec such as **MessagePack**, provided the implementation remains versioned and testable.

Examples:

- ExecutionIntent
- execution acknowledgement
- health/status payloads
- control commands
- diagnostics

If later profiling proves that one universal versioned binary schema is cleaner and faster, it may replace MessagePack without changing Katarina Core.

## 4. Human-Readable Policy

JSON is reserved for:

- audit logs;
- debug output;
- configuration where appropriate;
- offline inspection;
- test fixtures;
- human-readable decision records.

JSON must not be required for the realtime hot path.

## 5. Transport Modes

### Live Mode

Preferred transport:

```text
ZeroMQ over localhost
```

Rationale:

- persistent low-latency local communication;
- mature queue and messaging patterns;
- Python ecosystem support;
- suitable for bidirectional event/command channels.

Fallback transport:

```text
Native local TCP
```

The fallback exists so Katarina is not permanently dependent on one messaging library.

### Strategy Tester Mode

Strategy Tester uses a dedicated **TesterTransport adapter**.

The initial supported mechanism may use `FILE_COMMON` or another tester-compatible deterministic adapter. It must expose the same logical message interface as LiveTransport.

The tester must not force the production brain to understand file I/O.

## 6. Event-Driven Delta Architecture

MT5 must not resend the entire multi-timeframe/account/history state on every tick.

Use event-driven deltas:

```text
TickEvent       → price/tick changes
BarEvent        → new/closed bar
AccountDelta    → changed account state / heartbeat
PositionDelta   → changed position state
TradeEvent      → broker transaction changes
```

Katarina maintains a state cache and builds an immutable decision snapshot from the latest validated state.

```text
MT5 EVENTS
    ↓
KATARINA INGEST
    ↓
STATE CACHE
    ↓
SNAPSHOT BUILDER
    ↓
KATARINA BRAIN
```

## 7. Wire Header Requirements

Every authoritative realtime message must support a versioned envelope containing, at minimum, logical equivalents of:

- protocol magic / identifier;
- protocol version;
- message type;
- sequence number;
- event timestamp;
- payload length;
- integrity indicator/checksum where the final protocol requires it.

Stage 04 will define exact byte widths, endianness, field order, optional fields, and checksum policy.

## 8. Traceability IDs

The system must preserve end-to-end traceability:

```text
snapshot_id
    ↓
decision_id
    ↓
risk_decision_id
    ↓
execution_intent_id
    ↓
order_id
    ↓
broker_ticket / deal / position identifiers
```

A correlation identifier may join the whole chain.

## 9. Latency Observability

Every decision/execution path should record timing components such as:

- capture latency;
- encode latency;
- transport latency;
- decode/ingest latency;
- feature/analysis latency;
- decision latency;
- risk latency;
- return transport latency;
- MT5 preflight latency;
- broker/execution latency.

Exact latency thresholds are not frozen here. They will be determined by profiling and execution policy.

Stale decisions must be rejected according to the later execution policy.

## 10. Backpressure and Failure

The implementation must eventually define:

- bounded queues;
- overflow policy;
- heartbeat;
- reconnect behavior;
- sequence-gap detection;
- duplicate detection;
- stale-message handling;
- recovery after process restart.

These mechanisms must fail safe: communication failure cannot create new live risk.

## 11. Separation of Order and Position State

Transport events must be capable of representing broker transaction lifecycle separately from position lifecycle.

```text
ORDER STATE
CREATED → VALIDATED → SUBMITTED → PARTIAL/FILLED
                                 ↘ REJECTED/CANCELED/EXPIRED

POSITION STATE
CREATED → ACTIVE → MANAGING → EXITING → CLOSED
```

Actual broker transaction events, not a local boolean result alone, are the authoritative source for execution state.

## 12. Approved Direction

For the current architecture:

```text
PRODUCTION HOT PATH
→ versioned binary

FLEXIBLE CONTROL PATH
→ structured binary / MessagePack candidate

LIVE PRIMARY TRANSPORT
→ ZeroMQ localhost

LIVE FALLBACK
→ Native local TCP

TESTER
→ TesterTransport adapter

HUMAN AUDIT / DEBUG
→ JSON
```

This policy is binding for Stage 02. Exact schemas belong to Stage 04.
