# Katarina-AI

Katarina AI is being rebuilt as a **central financial intelligence system** for data-driven, adaptive, risk-governed trading.

## Primary Direction

- First specialist market: **XAUUSD scalping**
- Selected forex pairs may be added only after their own validated evidence
- Python is the primary intelligence, research, memory, learning, and orchestration layer
- MT5/MQL5 is the execution and market-interface layer
- Risk Governor is non-bypassable
- NO TRADE is valid
- Decision quality is more important than raw realized profit
- Katarina must recognize uncertainty and out-of-distribution conditions
- Learning is controlled by research, validation, shadow testing, promotion, monitoring, and rollback

## Frozen Project Objective

- [KATARINA_CONSTITUTION.md](KATARINA_CONSTITUTION.md)
- [config/constitution.json](config/constitution.json)

## Frozen MT5-to-Execution Workflow

Stage 02 is complete and frozen at v1.2.0:

- [docs/KATARINA_FINAL_WORKFLOW.md](docs/KATARINA_FINAL_WORKFLOW.md)
- [config/execution_workflow.json](config/execution_workflow.json)
- [docs/KATARINA_TRANSPORT_PROTOCOL.md](docs/KATARINA_TRANSPORT_PROTOCOL.md)
- [config/transport_policy.json](config/transport_policy.json)
- [docs/KATARINA_EXECUTION_RELIABILITY.md](docs/KATARINA_EXECUTION_RELIABILITY.md)
- [config/execution_reliability.json](config/execution_reliability.json)

## Frozen Repository Architecture

Stage 03 is complete and frozen at v1.0.0.

Architectural style:

```text
MODULAR MONOLITH
+ DOMAIN-DRIVEN BOUNDARIES
+ EVENT-DRIVEN CORE
+ PORTS & ADAPTERS
+ STRICT DEPENDENCY DIRECTION
```

Canonical documents:

- [docs/architecture/REPOSITORY_ARCHITECTURE.md](docs/architecture/REPOSITORY_ARCHITECTURE.md)
- [docs/architecture/DEPENDENCY_RULES.md](docs/architecture/DEPENDENCY_RULES.md)
- [config/repository_architecture.json](config/repository_architecture.json)
- [docs/reviews/STAGE_03_ARCHITECTURE_AUDIT.md](docs/reviews/STAGE_03_ARCHITECTURE_AUDIT.md)

Architecture decisions:

- [ADR-0001 — Modular Monolith](docs/adr/0001-modular-monolith.md)
- [ADR-0002 — Ports and Adapters](docs/adr/0002-ports-and-adapters.md)
- [ADR-0003 — Shared Core Across Environments](docs/adr/0003-shared-core-environments.md)

Python source boundaries now exist under:

```text
src/katarina/
├── domain/
├── contracts/
├── core/
├── engines/
├── intelligence/
├── ports/
├── adapters/
└── entrypoints/
```

Supporting top-level boundaries now exist for MT5, protocol, research, tests, models, and scripts.

## Build Progress

- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)

Current position: **Stage 03 complete. Stage 04 — Data Protocol / Schemas — is next.**
