# STAGE 05 — CORE / ORCHESTRATOR IMPLEMENTATION CHECK

**Stage:** 05/40  
**Status:** PASS FOR REVIEW / NOT FROZEN  
**Reviewed:** 2026-10-02  
**Core Draft:** v0.1.0

## What Was Implemented

Stage 05 now contains a real Python Core skeleton rather than only architecture documentation.

Implemented modules:

- `src/katarina/contracts/runtime.py`
- `src/katarina/core/lifecycle.py`
- `src/katarina/core/component.py`
- `src/katarina/core/message_bus.py`
- `src/katarina/core/queue.py`
- `src/katarina/core/readiness.py`
- `src/katarina/core/state.py`
- `src/katarina/core/orchestrator.py`

Tests:

- `tests/unit/core/test_stage05_core.py`

## Implemented Guarantees

### Lifecycle

The Core rejects invalid transitions and explicitly models:

- creation;
- initialization;
- bootstrap start;
- recovery;
- readiness;
- runtime start;
- running;
- degraded/resume;
- stop;
- fault;
- disposal.

### Component Graph

The component graph rejects:

- duplicate names;
- missing dependencies;
- dependency cycles;
- BOOTSTRAP components depending on RUNTIME components.

Startup is dependency ordered.

Stop/dispose is reverse ordered.

### Lifecycle-Scoped Subscriptions

Internal event handlers are bound to component start/stop.

This means:

- BOOTSTRAP handlers may operate during recovery;
- RUNTIME handlers are not active during recovery;
- runtime handlers activate only after the Core becomes READY and the runtime component starts;
- subscriptions are removed before component stop.

This reduces the chance of decision components acting on incomplete recovery state.

### Event Processing

Core routing is deterministic:

- priority-ordered ingress;
- serial handler invocation;
- stable subscription order;
- emitted events are queued only after the current dispatch finishes;
- no recursive immediate child-event dispatch.

### Fail-Closed Behavior

Lossless-required queue overflow:

- is never silently dropped;
- faults the Core;
- clears live execution arming;
- prevents new live risk.

Non-critical queue rejection is observable and counted.

### Lifecycle vs Trading Authorization

The following remains a hard Stage 05 invariant:

~~~text
RUNNING != NEW LIVE RISK ALLOWED
~~~

Live-risk admission additionally requires:

- trustworthy bootstrap state;
- current reconciliation;
- fresh data;
- health readiness;
- Risk Governor readiness;
- explicit execution arming.

## Test Result

The Stage 05 source logic was compiled and run locally using Python standard-library `unittest`.

Result:

~~~text
16 tests
16 passed
0 failed
~~~

Covered cases include:

- valid/invalid lifecycle transitions;
- component dependency ordering;
- cycle rejection;
- bootstrap/runtime dependency guard;
- deterministic EventBus order;
- non-reentrant child events;
- readiness gating;
- research-mode bootstrap;
- reverse shutdown;
- runtime-start fault cleanup;
- runtime subscriptions disabled during recovery;
- live readiness loss closes new-risk admission;
- advisory queue rejection;
- critical queue overflow fault.

## Static Repository Audit

The committed Stage 05 Python files were also checked for forbidden outward dependencies.

Result:

~~~text
adapters imported by Core       : 0
MT5 direct dependency           : 0
ZeroMQ direct dependency        : 0
SQLite/database dependency      : 0
HTTP/network client dependency  : 0
ML/dataframe dependency         : 0

Stage 05 unit tests detected    : 16
architecture/config issues      : 0
~~~

This preserves Stage 03 dependency direction.

## Research Basis

The design was informed by selected patterns from:

- NautilusTrader — kernel ownership, event-driven core, lifecycle state machines, shared live/backtest core;
- Freqtrade — centralized worker lifecycle, heartbeat/status, operational failure handling;
- QuantConnect LEAN — central operating manager and separated runtime handlers.

Katarina adopts the useful principles without copying their full framework complexity.

## Important Limitations

Stage 05 does not yet prove:

- KAT1 wire decoding;
- MT5 communication;
- real broker recovery;
- persistent journal restoration;
- production queue capacity;
- production latency;
- actual Risk Governor readiness;
- live order execution.

Those are intentionally later stages.

## Result

The Stage 05 implementation is structurally coherent and ready for owner/review inspection.

**PASS FOR REVIEW.**

It is intentionally **not frozen yet**.
