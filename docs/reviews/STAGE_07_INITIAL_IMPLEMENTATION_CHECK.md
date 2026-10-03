# Stage 07 — Initial Implementation Check

**Status:** ACTIVE IMPLEMENTATION / SESSION SUPERVISOR ADDED
**Stage:** 07/40
**Version:** 0.1.0

## Implemented now

- GitHub prior-art research;
- communication architecture draft;
- proposed ROUTER/DEALER ADR;
- machine-readable Stage-07 config draft;
- application-owned Python TransportPort;
- bounded in-memory transport adapter;
- Python KAT1 schema-driven codec;
- CRC32C implementation;
- fixed-root primitive encoder/decoder;
- bounded UTF-8 variable tails;
- embedded snapshot-record support;
- golden-vector decode/re-encode tests;
- corrupt magic/CRC/flag tests;
- bounded transport backpressure test;
- fail-closed Python KAT1 session supervisor;
- HEARTBEAT presence → HELLO → HELLO_ACK state machine;
- stale-session detection and reconnect handshake reset;
- explicit separation of communication readiness from live-risk readiness.

## Frozen boundaries preserved

- no pyzmq dependency leaks into Core or ports;
- no Stage-06 MQL bridge modification;
- no OrderSend enablement;
- no JSON realtime wrapper;
- localhost-only live design;
- TesterTransport remains separate.

## Current gate

Stage 06 is FROZEN, so MQL5 communication implementation is now unblocked. Live broker-risk enablement remains outside Stage 07 and stays governed by later stages.

Stage 07 continues with:

1. Python session supervisor CI proof;
2. MQL5 KAT1 codec;
3. MQL5 golden-vector conformance;
4. ZeroMQ capability spike;
5. ZeroMQ live adapter;
6. native TCP fallback;
7. cross-language heartbeat/reconnect/binding tests;
8. final Stage-07 audit.
