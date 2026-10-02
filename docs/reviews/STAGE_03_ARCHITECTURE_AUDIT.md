# STAGE 03 — REPOSITORY ARCHITECTURE AUDIT

**Stage:** 03/40  
**Status:** PASSED / FROZEN  
**Reviewed:** 2026-10-02  
**Architecture:** v1.0.0

## References Considered

The Stage 03 design was informed by patterns observed in mature open-source trading/research projects, especially:

- NautilusTrader: domain boundaries, event-driven architecture, ports/adapters, shared live/backtest core, immutable messages, reliability-first design;
- HFTFramework: explicit dependency graph and live/backtest path parity;
- Qlib / FinRL: separation of research, data, models, applications and trained artifacts;
- Freqtrade: separation of strategy, persistence, integration, backtest and operational interfaces.

Katarina adopts selected principles, not their codebase or full complexity.

## Accepted Architecture

- modular monolith;
- domain-driven boundaries;
- ports and adapters;
- event-driven internal contracts;
- shared core target across live/tester/shadow;
- research isolated from production execution;
- runtime/model artifacts kept out of source control;
- strict dependency direction;
- architecture decisions documented with ADRs.

## Strengths

- low runtime overhead compared with microservices;
- infrastructure can be replaced without rewriting the Brain;
- easier unit/contract/replay testing;
- clearer ownership of trading/risk/execution responsibilities;
- lower chance of strategy logic leaking into MT5 or adapters;
- easier future pair/model expansion.

## Costs / Weaknesses

- more up-front structure and interfaces;
- some boilerplate;
- strict boundaries require discipline;
- one Python process provides less process-level fault isolation than microservices;
- architectural checks need future CI enforcement.

These costs are accepted because they reduce long-term coupling without introducing distributed-system complexity.

## Deferred

Stage 03 intentionally does not implement:

- protocol byte layouts;
- actual engine logic;
- MT5 EA code;
- persistence technology;
- ZeroMQ/TCP code;
- model training;
- architecture CI checks.

These belong to later numbered stages.

## Result

Repository architecture is sufficiently defined and scaffolded.

**STAGE 03 PASSED.**

Next: **Stage 04 — Data Protocol / Schemas.**
