# Protocol

Language-neutral MT5 ↔ Katarina contracts live here.

## Stage 04 Status

Stage 04 is now **IN REVIEW**.

Current proposal:

~~~text
KAT1
→ canonical binary
→ little-endian
→ 52-byte fixed frame header
→ SBE-inspired block-length/schema-version evolution
→ scaled int64 for execution-sensitive decimals
→ bounded UTF-8 / bounded arrays
→ optional/required CRC32C by message policy
→ max frame 65,536 bytes
→ chunked atomic snapshot bootstrap
→ cross-language golden fixtures
~~~

Draft documents:

- ../docs/architecture/KATARINA_BINARY_PROTOCOL_V1_DRAFT.md
- ../docs/reviews/STAGE_04_PROTOCOL_RESEARCH.md
- ../config/protocol_schema_draft.json
- message_registry_v1_draft.json

## Important Rule

The canonical wire format is **not** a raw MQL5/Python memory-structure dump.

Python and MQL5 implementations must use explicit field offsets, widths and byte order.

Exact payload layouts and golden vectors will be completed and reviewed before Stage 04 is frozen.
