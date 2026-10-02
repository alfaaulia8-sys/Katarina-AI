# KAT1 V1 — CONFORMANCE CONTRACT

**Status:** FROZEN CANDIDATE  
**Version:** 1.0.0  
**Stage:** 04/40

## Canonical Wire Rules

- magic: ASCII `KAT1`;
- wire major: 1;
- wire minor: 0;
- fixed frame header: 52 bytes;
- all multibyte numeric fields: little-endian;
- fixed root layout: exact offsets in `protocol/kat1_message_schemas_v1.json`;
- variable fields: after root, in schema order;
- max frame size: 65,536 bytes;
- raw native MQL5/Python struct layout is never the protocol contract.

## CRC32C

Algorithm: CRC32C (Castagnoli).

Parameters:

~~~text
initial value = 0xFFFFFFFF
reflected polynomial = 0x82F63B78
final xor = 0xFFFFFFFF
trailer = uint32 little-endian
covered bytes = frame header + payload, excluding trailer
~~~

Required for:

- every critical message;
- snapshot transaction frames;
- execution mutation/lifecycle messages;
- journal/replay authoritative records;
- golden fixtures.

Optional for advisory-only:

- TICK_EVENT;
- BAR_EVENT;
- HEARTBEAT;
- TRANSPORT_METRICS.

If CRC-present flag is set, the decoder must verify it.

## Frame Semantics

`frame_length` includes:

~~~text
header + payload + optional CRC trailer
~~~

`block_length` is only the fixed root payload size.

The decoder must reject impossible lengths before reading variable fields.

## Sequence Semantics

A serialized frame receives sequence after any permitted local tick coalescing.

Therefore normal coalescing does not manufacture a false sequence gap.

Receiver behavior:

- duplicate critical sequence: reject/reconcile;
- backwards critical sequence: reject/reconcile;
- missing critical sequence: integrity degraded, reconcile before new live risk;
- advisory market gap: record data-quality degradation and continue only according to Data Validation policy.

Execution journal uses its own durable `event_cursor` inside execution lifecycle messages.

## Time Semantics

`source_time_ns` is Unix epoch UTC nanoseconds as a wire unit.

It does not claim the source actually measured nanoseconds.

Examples:

- MT5 millisecond timestamp is multiplied by 1,000,000;
- second precision is multiplied by 1,000,000,000.

Message semantics must preserve source precision/provenance when material.

Monotonic clocks from separate processes are not compared as if they share one epoch.

## Numeric Semantics

Execution-sensitive decimal quantities are scaled integers.

Examples:

~~~text
real price  = price_units  × 10^-price_scale
real volume = volume_units × 10^-volume_scale
native money = money_units × 10^-money_scale
~~~

Rules:

- no NaN sentinel;
- no infinity;
- zero and missing are distinct;
- money_scale comes from the account-unit profile;
- prices/volumes bind to the active SymbolSpec revision.

Analytical/model values may use finite float64 in internal Katarina contracts where exact decimal arithmetic is not required.

## Standard / Cent Invariant

A standard-like account and cent-like account use the same KAT1 schemas.

Risk/execution logic may not branch on broker marketing labels.

It uses:

- account native currency/unit;
- ACCOUNT_CURRENCY_DIGITS;
- broker-native account values;
- current symbol economic properties;
- OrderCalcProfit/OrderCalcMargin evidence where requested;
- normalized percentage/R metrics for cross-account learning.

Golden fixtures include both USD-like and USC-like examples.

## Hedging / Netting Invariant

Account mode is explicit.

Hedging:

- multiple position records per symbol allowed.

Netting:

- one active net position per symbol;
- POSITION_IDENTIFIER is stable lineage;
- POSITION_TICKET is a current broker handle and may change on reversal;
- stale approved position revisions invalidate pending/execution assumptions.

## Entry-Type Invariant

V1 production schema supports:

- MARKET;
- LIMIT;
- STOP.

STOP_LIMIT enum value is reserved but must be rejected by V1 execution admission.

All exposure-creating Katarina entries require broker-native SL.

## Golden Vector Requirement

Canonical vectors live in:

`protocol/golden/kat1_v1_vectors.json`

Python and MQL5 implementations must:

1. decode every positive vector successfully;
2. reproduce the exact canonical bytes for equivalent logical input;
3. reject every negative case;
4. preserve scaled integers without float round-tripping;
5. agree on CRC32C.

No bridge implementation is Stage-07-ready until this passes on both sides.

## Compatibility Rules

Compatible within wire major 1:

- append new fixed root fields at the end;
- increase block_length;
- increase schema_version;
- add new message types in reserved ranges;
- add bounded variable tail fields at the end.

Not compatible without a major protocol change:

- reorder existing fields;
- change an existing primitive width;
- change the meaning/unit/scale of an existing field;
- reuse enum/message IDs for new meanings;
- remove required execution-critical semantics.

Unknown execution-critical schema is fail-closed.

## Authoritative Files

- `protocol/kat1_message_schemas_v1.json`
- `protocol/enums_v1.json`
- `protocol/message_registry_v1.json`
- `protocol/golden/kat1_v1_vectors.json`
