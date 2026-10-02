# ADR-0005 — Single-Writer Deterministic Core

**Status:** Proposed  
**Stage:** 05

## Decision

Katarina's authoritative runtime state is mutated through one serialized Core event lane.

External I/O and expensive computation may run concurrently outside that lane, but authoritative results return through immutable contracts/events.

## Why

- deterministic replay;
- simpler correctness reasoning;
- fewer race conditions;
- consistent live/tester behavior;
- clearer audit ordering.

## Cost

A slow handler can delay all later events.

Therefore blocking I/O and long model computation are prohibited on the mutation lane and must be moved behind worker/adapter boundaries.

This ADR remains Proposed until Stage 05 audit/freeze.
