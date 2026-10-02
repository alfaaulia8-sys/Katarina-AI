# Katarina-AI

Katarina AI is being rebuilt as a **central financial intelligence system** for data-driven, adaptive, risk-governed trading.

## Current Build Position

- Stage 01 — Constitution & North Star: ✅ FROZEN v1.1.0
- Stage 02 — MT5-to-Execution Workflow: ✅ FROZEN v1.2.0
- Stage 03 — Repository Architecture: ✅ FROZEN v1.0.0
- Stage 04 — Data Protocol / Schemas: ✅ FROZEN — KAT1 v1.0.0
- Stage 05 — Katarina Core / Orchestrator: 🟡 IN REVIEW — v0.1.0

## KAT1 v1.0.0

KAT1 is the canonical binary MT5 ↔ Katarina protocol.

~~~text
MT5 / Katarina logical message
        ↓
KAT1 explicit schema
        ↓
canonical little-endian bytes
        ↓
ZeroMQ / TCP / TesterTransport
~~~

Frozen properties:

- fixed 52-byte frame header;
- explicit message type, schema version and block length;
- 30 registered message types with exact layouts;
- stream_id, boot_id and sequence;
- scaled int64 for execution-sensitive price/volume/money values;
- 128-bit lineage IDs;
- max frame bound 65,536 bytes;
- CRC32C for critical/durable frames;
- instrument dictionary + SymbolSpec revisions;
- transactional chunked snapshots;
- durable execution/reconciliation semantics;
- shared-account/manual-trade observation;
- Hedging + Netting support;
- MARKET + LIMIT + STOP entries;
- broker-native SL required for Katarina-created exposure;
- standard + cent account-native normalization;
- first-class deposit/withdrawal/credit/balance ledger;
- Python/MQL5 golden conformance contract.

## Canonical Stage 04 Documents

- [KAT1 Protocol V1](docs/architecture/KATARINA_BINARY_PROTOCOL_V1.md)
- [KAT1 Data Contract V1](docs/architecture/KAT1_DATA_CONTRACT_V1.md)
- [KAT1 Conformance V1](docs/architecture/KAT1_CONFORMANCE_V1.md)
- [Hedging / Netting Contract](docs/architecture/KAT1_HEDGING_NETTING_EXECUTION.md)
- [Standard / Cent Compatibility](docs/architecture/STANDARD_CENT_ACCOUNT_COMPATIBILITY.md)
- [Manual Trade Learning V1](docs/architecture/MANUAL_TRADE_LEARNING_CONTRACT_V1.md)
- [Stage 04 Audit](docs/reviews/STAGE_04_PROTOCOL_AUDIT.md)

Machine-readable contracts:

- [Protocol Config](config/protocol_schema.json)
- [Message Registry](protocol/message_registry_v1.json)
- [Exact Schemas](protocol/kat1_message_schemas_v1.json)
- [Enums](protocol/enums_v1.json)
- [Flags](protocol/flags_v1.json)
- [Capabilities](protocol/capabilities_v1.json)
- [Reason Codes](protocol/reason_codes_v1.json)
- [Payload Catalog](protocol/payload_catalog_v1.json)
- [Golden Vectors](protocol/golden/kat1_v1_vectors.json)

## Canonical Project Documents

- [KATARINA_CONSTITUTION.md](KATARINA_CONSTITUTION.md)
- [docs/KATARINA_FINAL_WORKFLOW.md](docs/KATARINA_FINAL_WORKFLOW.md)
- [docs/architecture/REPOSITORY_ARCHITECTURE.md](docs/architecture/REPOSITORY_ARCHITECTURE.md)
- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)


## Stage 05 — Core / Orchestrator (In Review)

The first Katarina runtime core is now implemented as a standard-library Python skeleton.

```text
adapters / future KAT1 decode
        ↓
immutable EventEnvelope
        ↓
bounded priority ingress
        ↓
KatarinaOrchestrator
        ↓
deterministic serial EventBus
        ↓
started components only
        ↓
new events return to ingress
```

Important safety properties:

- one authoritative mutation lane;
- runtime components do not receive recovery traffic before they start;
- component dependencies are topologically validated;
- critical ingress overflow faults fail-closed;
- live execution arming resets on boot/fault;
- `RUNNING` does not imply permission to open live risk;
- shared Core design remains compatible with Live / Tester / Shadow / Research.

Stage 05 documents:

- [Core / Orchestrator Draft](docs/architecture/KATARINA_CORE_ORCHESTRATOR_DRAFT.md)
- [Stage 05 Research](docs/reviews/STAGE_05_CORE_RESEARCH.md)
- [Core Config Draft](config/core_orchestrator_draft.json)

Current implementation:

- `src/katarina/contracts/runtime.py`
- `src/katarina/core/lifecycle.py`
- `src/katarina/core/component.py`
- `src/katarina/core/message_bus.py`
- `src/katarina/core/queue.py`
- `src/katarina/core/readiness.py`
- `src/katarina/core/state.py`
- `src/katarina/core/orchestrator.py`

Unit tests:

- `tests/unit/core/test_stage05_core.py`

Stage 05 remains **IN REVIEW** until its final audit/freeze.
