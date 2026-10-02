# Katarina-AI

Katarina AI is being rebuilt as a **central financial intelligence system** for data-driven, adaptive, risk-governed trading.

## Current Build Position

- Stage 01 — Constitution & North Star: ✅ FROZEN v1.1.0
- Stage 02 — MT5-to-Execution Workflow: ✅ FROZEN v1.2.0
- Stage 03 — Repository Architecture: ✅ FROZEN v1.0.0
- Stage 04 — Data Protocol / Schemas: 🟡 IN REVIEW

## Stage 04 — KAT1 Draft

The current protocol proposal is a custom SBE-inspired canonical binary protocol:

~~~text
MT5 / Katarina logical message
        ↓
KAT1 explicit schema
        ↓
canonical little-endian bytes
        ↓
ZeroMQ / TCP / TesterTransport
~~~

Core draft properties:

- fixed 52-byte frame header;
- explicit message type, schema version and block length;
- stream_id, boot_id and sequence in the frame;
- int64 scaled decimal values for execution-sensitive prices/volumes/money;
- finite float64 only where approximate analytical values are appropriate;
- max frame bound of 65,536 bytes;
- 128-bit trace identifiers;
- instrument dictionary/spec revision instead of repeating symbol strings on the hot path;
- chunked atomic snapshot bootstrap;
- CRC32C policy for critical/durable records;
- no raw MQL5 memory-structure dump as the wire contract;
- golden Python/MQL5 byte fixtures required before freeze.

Draft sources:

- [docs/architecture/KATARINA_BINARY_PROTOCOL_V1_DRAFT.md](docs/architecture/KATARINA_BINARY_PROTOCOL_V1_DRAFT.md)
- [docs/reviews/STAGE_04_PROTOCOL_RESEARCH.md](docs/reviews/STAGE_04_PROTOCOL_RESEARCH.md)
- [config/protocol_schema_draft.json](config/protocol_schema_draft.json)
- [protocol/message_registry_v1_draft.json](protocol/message_registry_v1_draft.json)

## Canonical Project Documents

- [KATARINA_CONSTITUTION.md](KATARINA_CONSTITUTION.md)
- [docs/KATARINA_FINAL_WORKFLOW.md](docs/KATARINA_FINAL_WORKFLOW.md)
- [docs/architecture/REPOSITORY_ARCHITECTURE.md](docs/architecture/REPOSITORY_ARCHITECTURE.md)
- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)
