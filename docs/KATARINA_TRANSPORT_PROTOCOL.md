# KATARINA AI — TRANSPORT & CODEC POLICY

**Status:** FROZEN FOR STAGE 02  
**Version:** 1.1.0  
**Authority:** Human Project Owner  
**Scope:** MT5 ↔ Katarina transport architecture. Exact message fields/byte layouts belong to Stage 04.

## Approved Direction

```text
PRODUCTION HOT PATH
→ versioned binary

FLEXIBLE CONTROL PATH
→ MessagePack or versioned binary

LIVE PRIMARY
→ ZeroMQ localhost

LIVE FALLBACK
→ native local TCP

TESTER
→ TesterTransport adapter

HUMAN AUDIT / DEBUG
→ JSON
```

## Transport Independence

Katarina Core depends on logical interfaces, not ZeroMQ/TCP/file details.

Required logical operations include:

- connect;
- disconnect;
- send event;
- receive command;
- heartbeat / health;
- reconnect;
- expose transport state.

## Event-Driven Delta Model

Do not resend full multi-timeframe/account/history state on every tick.

Primary event classes:

- TickEvent;
- BarEvent;
- AccountDelta;
- PositionDelta;
- TradeEvent;
- Heartbeat / HealthEvent.

Katarina State Cache builds coherent immutable snapshots.

## Binary Envelope Concepts

Every authoritative realtime frame supports logical equivalents of:

- protocol identifier;
- protocol version;
- message type;
- stream_id;
- boot_id;
- sequence number;
- event timestamp;
- payload length;
- integrity mechanism as defined in Stage 04.

## Backpressure

Transport buffers are bounded.

Priority:

1. execution/trade lifecycle;
2. risk-critical account/position state;
3. bars;
4. ticks.

Tick coalescing is allowed; critical execution-event loss is not.

Critical backlog/overflow must degrade to NO NEW RISK.

## Reconnect

Reconnect does not imply READY.

After reconnect, the workflow requires handshake, binding validation, sequence/journal recovery, complete snapshot, and broker reconciliation before new risk.

## Security

Baseline ZeroMQ/TCP interfaces are localhost-only. Do not expose command sockets publicly.

Execution requires explicit execution mode and correct account/instance binding.

## Tester

TesterTransport presents the same logical contracts while using deterministic tester-compatible I/O. FILE_COMMON is an implementation candidate, not part of the Brain API.

## JSON

JSON remains available for logs, audit records, config, fixtures, and diagnostics. It is not the authoritative realtime production wire format.
