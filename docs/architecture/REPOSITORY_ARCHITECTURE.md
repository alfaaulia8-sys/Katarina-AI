# KATARINA AI — REPOSITORY ARCHITECTURE

**Status:** FROZEN  
**Version:** 1.0.0  
**Stage:** 03/40

## Architectural Style

Katarina uses a **modular monolith** with:

- domain-driven boundaries;
- event-driven internal flow;
- ports and adapters;
- immutable cross-boundary contracts;
- shared production core across live, tester, shadow, and research orchestration;
- strict dependency direction.

The goal is to keep low latency and operational simplicity while preventing the codebase from becoming tightly coupled.

## Design Priority

```text
RELIABILITY
  > PERFORMANCE
  > MODULARITY
  > TESTABILITY
  > MAINTAINABILITY
  > DEPLOYABILITY
```

Performance optimizations may not weaken correctness, auditability, risk controls, or recovery guarantees.

## Canonical Repository Shape

```text
Katarina-AI/
├── src/katarina/
│   ├── domain/
│   ├── contracts/
│   ├── core/
│   ├── engines/
│   ├── intelligence/
│   ├── ports/
│   ├── adapters/
│   └── entrypoints/
├── mt5/
├── protocol/
├── research/
├── tests/
├── models/
├── scripts/
├── config/
├── docs/
│   ├── architecture/
│   ├── adr/
│   ├── reviews/
│   └── operations/
├── .github/
├── KATARINA_CONSTITUTION.md
└── README.md
```

## Module Responsibilities

### domain

Pure trading concepts and value objects.

Examples:

- market primitives;
- price / quantity / money;
- symbols and identifiers;
- order / position semantics;
- exposure and portfolio concepts;
- risk-domain values.

Domain code must not depend on MT5, ZeroMQ, databases, ML frameworks, web APIs, or infrastructure adapters.

### contracts

Immutable messages crossing module boundaries.

Examples:

- TickEvent;
- BarEvent;
- AccountDelta;
- PositionDelta;
- TradeEvent;
- MarketSnapshot;
- TradeCandidate;
- RiskDecision;
- ExecutionIntent;
- ExecutionResult.

Corrections produce new messages; existing messages are not mutated.

### core

Runtime orchestration and system lifecycle.

Owns concepts such as:

- orchestrator;
- lifecycle;
- state cache;
- message/event routing;
- startup / shutdown coordination.

Core coordinates modules but does not contain instrument-specific trading edge.

### engines

Deterministic or policy-driven working components.

Planned engines include:

- market;
- timeframe;
- regime;
- decision;
- risk;
- portfolio;
- execution;
- health;
- memory;
- evaluation.

Engines operate through contracts and ports, not direct infrastructure imports.

### intelligence

Research-backed market intelligence.

Includes:

- XAUUSD specialist;
- future pair specialists;
- economics;
- statistics;
- model-facing logic;
- feature/model interpretation.

Production intelligence may not directly submit broker orders.

### ports

Stable interfaces owned by the application/core side.

Examples:

- transport;
- persistence;
- execution venue;
- market data;
- clock;
- model registry;
- economic data.

Ports define what Katarina needs, not how a provider implements it.

### adapters

Infrastructure implementations of ports.

Examples:

- ZeroMQ;
- native TCP;
- TesterTransport;
- MT5 bridge integration;
- persistence backends;
- economic providers;
- model storage/provider adapters.

Adapters may depend inward on ports/contracts/domain. Inner layers may not depend outward on adapters.

### entrypoints

Composition roots.

Examples:

- live;
- tester;
- shadow;
- research;
- CLI / maintenance.

Entrypoints are allowed to know concrete adapters because they assemble the application.

## Non-Python Areas

### mt5/

MQL5 bridge, include files, and MT5-side tests.

It implements sensor/execution-gateway duties defined by the frozen Stage 02 workflow.

### protocol/

Language-neutral communication contract.

It will hold schemas, golden binary fixtures, compatibility rules, and conformance material shared conceptually by Python and MQL5.

Exact binary layout belongs to Stage 04.

### research/

Experimental notebooks, hypotheses, offline studies, and research reports.

Research is intentionally isolated from production execution.

### tests/

Separate test families for unit, integration, contract, replay, property, regression, and later end-to-end validation.

### models/

Only model metadata, registry references, manifests, hashes, and promotion records belong in Git.

Large trained artifacts do not.

### scripts/

Build, deployment, maintenance, migration, and operator tooling. Scripts may orchestrate the application but may not become an alternative hidden trading engine.

## Live / Tester / Research Parity

The target is:

```text
                  SHARED KATARINA CORE
             ┌──────────┼──────────┐
             │          │          │
           LIVE       TESTER    SHADOW/RESEARCH
             │          │          │
        Live adapters  Tester   Research adapters
```

Core decision/risk behavior should be shared. Environment-specific differences belong at ports/adapters and explicit environment policies.

## Forbidden Structural Patterns

Do not create catch-all modules such as:

- utils.py containing unrelated trading logic;
- helpers.py as a dumping ground;
- misc/;
- old/;
- backup/;
- final2/;
- temporary production forks.

Shared code must have a clear domain owner.

## Runtime Artifacts

Runtime state must not live as source code.

Examples excluded from Git:

- live journals;
- runtime databases;
- logs;
- caches;
- downloaded raw data;
- trained binary model artifacts;
- secrets;
- temporary MT5 export files.

## Expansion Rule

New modules must fit an existing responsibility boundary or be introduced through a documented architecture decision.

If a feature requires violating dependency direction, the architecture must be reviewed before implementation.
