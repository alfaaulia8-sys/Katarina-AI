# STAGE 05 — CORE / ORCHESTRATOR RESEARCH

**Stage:** 05/40  
**Status:** IN REVIEW  
**Reviewed:** 2026-10-02

## Goal

Define and implement the smallest reliable central runtime that can coordinate Katarina without embedding trading edge, risk policy, broker I/O, or model intelligence.

The Core must be reusable across live, tester, shadow, and research contexts.

## GitHub Patterns Reviewed

### NautilusTrader

Repository: `nautechsystems/nautilus_trader`

Relevant findings:

- a central kernel owns shared core resources and lifecycle;
- live/backtest contexts share the same central core;
- event-driven communication is routed through an in-process message bus;
- cache/state, engines, and lifecycle are explicit concerns;
- components use an explicit finite state machine;
- reliability and data integrity are prioritized over availability;
- synchronous re-entrant callbacks can observe surprising state, so event ordering and mutation ownership must be deliberate;
- the kernel is not treated as a cross-thread synchronization boundary.

Katarina adopts:

- one central orchestration boundary;
- explicit lifecycle;
- deterministic in-process routing;
- shared core across environments;
- one authoritative mutation lane.

Katarina does not copy the full Nautilus component/cache/trader complexity.

### Freqtrade

Repository: `freqtrade/freqtrade`

Relevant findings from `freqtrade/worker.py`:

- worker lifecycle is explicit;
- state transitions trigger startup/cleanup behavior;
- heartbeat/operational status is visible;
- operational exceptions move the bot into a stopped state instead of silently continuing;
- configuration/reload behavior is centralized.

Katarina adopts the principle that lifecycle and failure handling belong in one runtime owner.

Katarina does not adopt Freqtrade's coarse polling loop as the internal market-event model.

### QuantConnect LEAN

Repository: `QuantConnect/Lean`

Relevant findings:

- the Engine is a primary operating loop;
- setup, data, transactions, realtime behavior, result handling, and brokerage are separated behind explicit handler boundaries;
- algorithm processing is coordinated by a manager rather than allowing each subsystem to own the process;
- runtime state changes can terminate or alter processing centrally.

Katarina adopts separation between orchestration and subsystem implementation.

Katarina does not copy LEAN's much larger plugin/thread/job architecture.

## Stage 05 Design Conclusion

Katarina should use:

~~~text
ONE ORCHESTRATOR
+
SINGLE-WRITER CORE MUTATION LANE
+
BOUNDED PRIORITY INGRESS
+
DETERMINISTIC SERIAL DISPATCH
+
EXPLICIT COMPONENT DEPENDENCY GRAPH
+
BOOTSTRAP vs RUNTIME COMPONENT PHASES
+
LIFECYCLE STATE MACHINE
+
SEPARATE READINESS / LIVE-RISK GATE
+
REVERSE-ORDER SHUTDOWN
+
FAIL-CLOSED CRITICAL ERRORS
~~~

## Important Distinction

`RUNNING` does **not** mean "allowed to open new live risk".

A process may be alive and processing recovery/health events while execution is blocked.

This avoids coupling application liveness to trading authorization.

## Concurrency Direction

The authoritative core mutation path is single-writer.

External adapters may perform I/O concurrently, but they must hand immutable events into the core.

CPU-heavy model work may later run outside the mutation lane, but results must return as explicit events/contracts before changing authoritative state.

The Core is not a shared-memory multi-thread mutation surface.

## Expected Advantages

- deterministic replay/testing;
- fewer race conditions;
- clean live/tester parity;
- clear startup/recovery/shutdown ownership;
- critical queue overflow can fail closed;
- easier fault diagnosis;
- prevents transport/model/database details from taking over system lifecycle.

## Costs

- slow handlers can block deterministic dispatch;
- components must respect lifecycle boundaries;
- expensive computations need explicit worker/adapter boundaries later;
- one mutation lane sacrifices some parallel write throughput in exchange for correctness.

These costs are accepted for the V1 trading core.

## Implementation Scope

Stage 05 may implement:

- runtime event envelope;
- event priority;
- lifecycle state machine;
- component dependency ordering;
- deterministic in-process event bus;
- bounded priority ingress queue;
- readiness gate;
- runtime status store;
- central orchestrator;
- unit tests.

Stage 05 must **not** implement:

- KAT1 network decoder;
- ZeroMQ/TCP;
- MT5 bridge;
- market intelligence;
- Risk Governor policy;
- position sizing;
- broker execution;
- persistent database;
- learning/model logic.

Those remain later roadmap stages.
