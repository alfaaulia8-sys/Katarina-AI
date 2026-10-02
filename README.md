# Katarina-AI

Katarina AI is being rebuilt as a **central financial intelligence system** for data-driven, adaptive, risk-governed trading.

## Primary Direction

- First specialist market: **XAUUSD scalping**
- Selected forex pairs may be added only after their own validated evidence
- Python is the primary intelligence, research, memory, learning, and orchestration layer
- MT5/MQL5 is the execution and market-interface layer
- Risk Governor is non-bypassable
- Learning is controlled through research, drift/degradation detection, validation, shadow testing, and versioned promotion
- NO TRADE is a valid decision
- Decision quality is more important than raw realized profit
- Katarina must recognize uncertainty and out-of-distribution conditions
- Complexity must earn its place; simpler robust models are preferred when performance is comparable

## Frozen Project Objective

The permanent project mission and non-negotiable safety boundaries are defined in:

- [KATARINA_CONSTITUTION.md](KATARINA_CONSTITUTION.md)
- [config/constitution.json](config/constitution.json)

## North Star

> Katarina AI is a disciplined financial intelligence system that seeks sustainable long-term capital growth through high-quality decisions based on data, probability, evidence, and risk-adjusted expectancy.

> Katarina does not need to be right all the time. Katarina must make the best decision justified by the available evidence, know when it does not know enough, limit damage when wrong, and change only when validated evidence shows that the change is better.

## Canonical Execution Workflow

- [docs/KATARINA_FINAL_WORKFLOW.md](docs/KATARINA_FINAL_WORKFLOW.md)
- [config/execution_workflow.json](config/execution_workflow.json)

## Transport & Codec Policy

Stage 02 approved a binary-first realtime architecture:

- production hot path: versioned binary;
- live primary: ZeroMQ localhost;
- live fallback: native local TCP;
- Strategy Tester: dedicated TesterTransport adapter;
- JSON: audit/debug only, not authoritative realtime transport.

Canonical policy:

- [docs/KATARINA_TRANSPORT_PROTOCOL.md](docs/KATARINA_TRANSPORT_PROTOCOL.md)
- [config/transport_policy.json](config/transport_policy.json)

Exact binary field layouts are intentionally deferred to **Stage 04 — Data Protocol / Schemas**.

## Build Progress

- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)
