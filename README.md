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
- [docs/reviews/STAGE_02_WORKFLOW_AUDIT.md](docs/reviews/STAGE_02_WORKFLOW_AUDIT.md)

Key Stage 02 decisions:

- event-driven MT5 data flow;
- binary-first production hot path;
- ZeroMQ localhost primary + local TCP fallback;
- dedicated tester transport;
- state cache + immutable snapshots;
- durable idempotency;
- broker transaction events and reconciliation as execution truth;
- UNKNOWN outcome is never automatically retried;
- startup/reconnect remains fail-closed until reconciliation;
- critical execution events are durable/replayable.

## Build Progress

- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)

Current position: **Stage 02 complete. Stage 03 — Repository Architecture — is next.**
