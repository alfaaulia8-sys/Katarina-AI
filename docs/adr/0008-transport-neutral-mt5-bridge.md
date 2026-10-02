# ADR-0008 — Transport-Neutral MT5 Bridge

**Status:** Proposed  
**Stage:** 06

## Decision

The MT5 Bridge owns broker sensing/safety/execution-gateway responsibilities but does not own a concrete network transport.

Transport is accessed through a small MQL5 port abstraction.

## Why

This preserves the frozen architecture:

- ZeroMQ localhost primary later;
- native TCP fallback later;
- TesterTransport later;
- broker logic must not be duplicated for each transport.

## Consequence

Stage 06 can build and review EA lifecycle/event handling without prematurely coupling it to ZeroMQ/TCP.

Concrete communication is Stage 07.

This ADR remains Proposed until Stage 06 audit/freeze.
