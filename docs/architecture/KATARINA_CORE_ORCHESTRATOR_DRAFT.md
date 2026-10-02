# KATARINA CORE / ORCHESTRATOR — DRAFT

**Status:** IN REVIEW  
**Version:** 0.1.0  
**Stage:** 05/40

## 1. Responsibility

The Katarina Core is the runtime coordinator.

It owns:

- lifecycle;
- component initialization/start/stop/dispose ordering;
- central readiness state;
- bounded ingress;
- deterministic event dispatch;
- runtime status counters;
- fault escalation.

It does **not** own trading edge.

~~~text
KAT1 / adapters
      ↓
immutable internal event
      ↓
BOUNDED INGRESS
      ↓
KATARINA ORCHESTRATOR
      ↓
DETERMINISTIC EVENT BUS
      ↓
engines / components
      ↓
new immutable events
      ↓
back to ingress
~~~

## 2. Single-Writer Mutation Lane

Authoritative Core state is mutated only through one serialized event-processing lane.

Rules:

- adapters do not mutate Core state directly;
- components do not share arbitrary mutable Core internals;
- handlers run serially for one event;
- events emitted by handlers are queued **after** the current dispatch finishes;
- recursive immediate dispatch is not used;
- external threads must hand work to the event-loop owner through a later adapter boundary.

This is primarily a correctness choice, not a claim that all Katarina computation must be single-threaded.

## 3. Runtime Modes

Core supports:

- LIVE;
- TESTER;
- SHADOW;
- RESEARCH.

The Core implementation remains shared.

Environment-specific transport, persistence, broker, timing, and execution behavior belongs outside the Core or behind explicit ports/adapters.

## 4. Component Phases

Two startup phases are defined.

### BOOTSTRAP

Infrastructure needed to establish trustworthy state.

Future examples:

- transport;
- protocol adapter;
- journal;
- persistence recovery;
- snapshot/reconciliation support.

Bootstrap components may start before the system is ready to trade.

### RUNTIME

Normal analytical/trading components.

Future examples:

- market engine;
- timeframe/regime engines;
- decision engine;
- Risk Governor;
- execution engine;
- evaluation/learning-facing components.

Runtime components start only after Core bootstrap readiness is satisfied.

A BOOTSTRAP component may not depend on a RUNTIME component.

## 5. Component Dependency Graph

Each managed component declares:

- unique name;
- dependencies;
- phase.

The Orchestrator performs deterministic topological ordering.

Rejected:

- duplicate component name;
- unknown dependency;
- dependency cycle;
- BOOTSTRAP → RUNTIME dependency.

Startup follows dependency order.

Stop/dispose follows reverse order.

## 6. Lifecycle

Proposed lifecycle:

~~~text
CREATED
  ↓
INITIALIZING
  ↓
STARTING (bootstrap components)
  ↓
RECOVERING
  ↓
READY
  ↓
STARTING (runtime components)
  ↓
RUNNING
  ├──→ DEGRADING → DEGRADED → RESUMING → RUNNING
  ├──→ STOPPING → STOPPED → DISPOSING → DISPOSED
  └──→ FAULTING → FAULTED → DISPOSING → DISPOSED
~~~

Invalid lifecycle transitions are rejected.

Live faults do not auto-rearm execution.

## 7. Readiness Is Separate From Lifecycle

Core readiness signals:

- TRANSPORT;
- PROTOCOL;
- IDENTITY;
- SNAPSHOT;
- JOURNAL;
- EVENT_CURSOR;
- RECONCILED;
- DATA_FRESH;
- HEALTH;
- RISK;
- EXECUTION_ARMED.

### LIVE / SHADOW bootstrap readiness

Required before Core becomes READY:

~~~text
TRANSPORT
PROTOCOL
IDENTITY
SNAPSHOT
JOURNAL
EVENT_CURSOR
RECONCILED
~~~

### TESTER bootstrap readiness

Initial proposal:

~~~text
PROTOCOL
IDENTITY
SNAPSHOT
~~~

### RESEARCH bootstrap readiness

No external transport bootstrap requirement.

## 8. New Live Risk Gate

New live risk is allowed only when:

~~~text
mode == LIVE
AND lifecycle == RUNNING
AND core bootstrap readiness == TRUE
AND DATA_FRESH
AND HEALTH
AND RISK
AND EXECUTION_ARMED
~~~

Therefore:

~~~text
RUNNING != TRADING ALLOWED
~~~

Loss of reconciliation/data/health/risk readiness closes the live-risk gate without requiring the process itself to die.

Actual risk policy and execution authorization are implemented in later stages.

## 9. Explicit Live Arming

`EXECUTION_ARMED` is reset on:

- process/core construction;
- fault.

The Core never silently restores live arming from the previous process.

This preserves Stage 02 fail-closed behavior.

## 10. Event Contract

Internal `EventEnvelope` is immutable at the envelope level and contains:

- topic;
- payload;
- priority;
- optional source sequence;
- optional source timestamp;
- source identifier.

Priority classes:

~~~text
CRITICAL
RISK_STATE
MARKET
ADVISORY
~~~

CRITICAL/RISK_STATE events are lossless-required.

## 11. Bounded Ingress

Ingress is bounded and priority ordered.

If full:

- non-critical event submission may be rejected observably;
- lossless-required event overflow is a Core fault;
- the system fails closed for new live risk.

Exact production queue capacity is **not frozen in Stage 05** and remains runtime/performance configuration.

Tick coalescing policy remains a transport/data-ingress concern for later implementation.

## 12. Deterministic Event Bus

Handlers execute serially in subscription order.

A handler may return new immutable events.

Those events are not recursively dispatched.

They are appended to Core ingress after all handlers for the current event complete.

This creates an explicit event boundary:

~~~text
EVENT A
  ↓
handler 1
handler 2
handler 3
  ↓
emitted B/C queued
  ↓
EVENT B
...
~~~

## 13. Handler Rule

Core handlers must not perform long blocking network/database/model work on the mutation lane.

Later components should use:

- ports/adapters;
- worker execution;
- explicit request/result contracts;

and return results to Core as events.

## 14. Runtime State

Stage 05 runtime state contains orchestration facts only:

- mode;
- lifecycle;
- readiness snapshot;
- processed-event count;
- rejected non-critical-event count;
- last runtime error.

It is not the trading/account/portfolio database.

Domain trading state is introduced by later engines/state modules.

## 15. Fault Semantics

The Core faults on examples such as:

- component bootstrap/start failure;
- event handler exception;
- critical ingress overflow;
- invalid lifecycle operation that crosses a safety boundary.

Fault behavior:

1. reset live execution arming;
2. record reason;
3. stop started components in reverse order;
4. enter FAULTED;
5. require explicit disposal/restart/recovery path.

MT5 broker-native protection for already-open positions remains a separate Stage 06/18 responsibility.

## 16. Stage 05 Implementation Files

~~~text
src/katarina/contracts/runtime.py

src/katarina/core/
├── lifecycle.py
├── component.py
├── message_bus.py
├── queue.py
├── readiness.py
├── state.py
└── orchestrator.py
~~~

## 17. Current Test Target

Stage 05 draft unit tests cover:

- lifecycle transition validity;
- dependency order/cycle rejection;
- bootstrap/runtime phase dependency rule;
- deterministic handler order;
- readiness gating;
- reverse-order shutdown;
- runtime-start failure cleanup;
- non-critical ingress rejection;
- critical ingress overflow fail-closed;
- emitted-event non-reentrancy;
- live-risk gate closure when readiness is lost.

## 18. Deferred

Not frozen/implemented here:

- transport thread handoff;
- KAT1 codec;
- actual health thresholds;
- actual Risk Governor readiness;
- persistent journal/database;
- market/account state reducers;
- engine-specific event topics;
- production queue capacity;
- latency budgets;
- CPU-heavy model worker design.

Those belong to later stages.
