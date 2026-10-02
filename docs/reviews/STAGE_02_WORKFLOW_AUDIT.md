# STAGE 02 — MT5-TO-EXECUTION WORKFLOW AUDIT

**Stage:** 02/40  
**Status:** PASSED / FROZEN  
**Reviewed:** 2026-10-02  
**Workflow:** v1.2.0

## Reference Findings Incorporated

GitHub implementations and protocol designs reviewed included:

- ZeroMQ-based MQL/Python bridges;
- MQL5 JSON API patterns with dedicated live and trade-event sockets;
- MT5 execution protocols using durable idempotency journals;
- transaction-event based execution truth;
- tester/file-based adapters.

The most useful production-grade ideas incorporated into Katarina are:

1. transport is separate from strategy/intelligence;
2. realtime market traffic and trade lifecycle events are separate logical classes;
3. request receipt is not execution proof;
4. idempotency must survive restart;
5. ambiguous execution must become UNKNOWN, not automatically retried;
6. durable transaction/event replay is required for recovery;
7. startup/reconnect must reconcile broker and local state before new risk;
8. complete snapshot failure must not become a false empty state.

## Positive Development

Compared with workflow v1.1.0, v1.2.0 adds:

- startup/reconnect recovery gate;
- instance/account/build binding;
- capability negotiation;
- stream_id and boot_id;
- bounded priority queues;
- critical-event durability;
- durable idempotency journal;
- final state revalidation after OrderCheck;
- UNKNOWN execution state;
- broker reconciliation;
- ordered event cursor/replay;
- localhost-only baseline transport security;
- complete snapshot semantics;
- explicit order vs position state machines.

## Remaining Deferred Work

Not a Stage 02 blocker:

- exact binary struct layout;
- byte order;
- numeric widths;
- checksum algorithm;
- symbol-id mapping;
- exact queue capacities;
- exact latency budgets;
- exact risk thresholds;
- tester adapter implementation.

These belong to Stages 04, 07, 16, 18, and 35.

## Acceptance Result

All Stage 02 architecture questions are sufficiently defined for repository/module design to begin.

**STAGE 02 PASSED.**

Next: **Stage 03 — Repository Architecture.**
