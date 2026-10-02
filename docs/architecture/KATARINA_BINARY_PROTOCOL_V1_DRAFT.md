# KATARINA BINARY PROTOCOL V1 — DRAFT

**Status:** IN REVIEW  
**Protocol:** KAT1  
**Draft:** 0.1  
**Stage:** 04/40

## 1. Design Goals

The protocol must be deterministic, compact, fast enough for XAUUSD scalping, safe to decode, bounded in memory/work, versioned, replayable, identical in logical semantics across LiveTransport and TesterTransport, independent from Python or MQL5 in-memory layouts, and suitable for golden cross-language conformance tests.

## 2. Canonical Byte Order

All numeric fields use **little-endian** encoding in KAT1.

Reason:

- current production target is Windows x86-64;
- Python supports explicit little-endian packing;
- it avoids unnecessary byte swaps on the target platform.

The protocol remains explicit; host-native byte order must never be assumed by codec code.

## 3. Canonical Frame Header

KAT1 v1 uses a fixed 52-byte frame header.

| Offset | Bytes | Field | Type |
|---:|---:|---|---|
| 0 | 4 | magic | raw bytes KAT1 |
| 4 | 1 | wire_major | uint8 |
| 5 | 1 | wire_minor | uint8 |
| 6 | 2 | header_length | uint16 |
| 8 | 2 | message_type | uint16 |
| 10 | 2 | schema_version | uint16 |
| 12 | 2 | block_length | uint16 |
| 14 | 2 | flags | uint16 |
| 16 | 4 | frame_length | uint32 |
| 20 | 8 | sequence | uint64 |
| 28 | 8 | source_time_ns | uint64 |
| 36 | 8 | stream_id | uint64 |
| 44 | 8 | boot_id | uint64 |

V1 invariants:

- magic must be exactly KAT1;
- wire_major = 1;
- header_length = 52;
- frame_length includes header, payload and optional trailer;
- frame_length must not exceed the negotiated/configured maximum;
- stream_id identifies the persistent logical event stream;
- boot_id changes on each successful MT5 bridge boot;
- sequence ordering rules depend on the stream/message class and are explicitly validated.

## 4. Frame Flags

Initial flags:

- 0x0001 — CRC32C trailer present;
- 0x0002 — critical/reconciliation-required message;
- 0x0004 — snapshot transaction frame;
- remaining bits reserved and must be zero unless negotiated by a compatible version.

Unknown critical flags cause rejection.

## 5. CRC Policy

CRC32C is available as an application-level integrity trailer.

Proposed V1 policy:

- mandatory for durable journal/replay records;
- mandatory for golden fixtures;
- mandatory for execution mutation commands and execution lifecycle events;
- configurable for high-frequency advisory TickEvent/BarEvent live frames after benchmarking.

Transport checksums do not replace protocol/journal integrity checks.

## 6. Maximum Frame Size

Initial protocol bound:

~~~text
MAX_FRAME_BYTES = 65,536
~~~

This is a Katarina resource-safety bound, not a ZeroMQ technical limit.

Large state bootstrap uses snapshot chunking instead of unbounded frames.

## 7. Primitive Types

Allowed canonical primitives:

- uint8 / int8;
- uint16 / int16;
- uint32 / int32;
- uint64 / int64;
- float64 where analytical non-exact values are appropriate;
- opaque 128-bit identifiers represented as two uint64 values;
- bounded UTF-8 byte strings only outside the hot path.

Disallowed:

- platform-dependent integers;
- unbounded strings/arrays;
- NaN or infinity;
- raw pointers;
- Python pickles;
- raw MQL structure layout as the wire contract.

## 8. Trading Numeric Policy

Monetary/execution-sensitive values use scaled integers where practical.

### Price

~~~text
price_real = price_units × 10^(-price_scale)
~~~

price_units is int64. price_scale comes from the negotiated SymbolSpec revision.

### Volume

~~~text
volume_real = volume_units × 10^(-volume_scale)
~~~

volume_units is int64.

### Money

Account currency values use int64 money units with an explicit account money scale.

### Analytical values

Probability, model scores, volatility metrics, expected-R and research features may use finite float64 where exact decimal arithmetic is not required.

This prevents binary floating-point rounding from silently becoming order-sizing semantics.

## 9. Missing / Optional Values

No NaN sentinel is allowed.

Optional values use message-specific presence bitmaps/flags or explicit optional record variants.

A missing value and a numeric zero must never be indistinguishable.

## 10. Identifier Policy

### 64-bit operational identity

- stream_id: persistent across boots for one logical MT5 bridge stream;
- boot_id: new nonzero value on each successful boot;
- sequence: ordered uint64 counter.

### 128-bit trace identity

The following use opaque Id128 values where cross-process uniqueness is required:

- snapshot_id;
- decision_id;
- risk_decision_id;
- execution_intent_id;
- order_id / client_request_id;
- correlation_id where used.

Wire representation:

~~~text
id_hi: uint64
id_lo: uint64
~~~

Human logs may render Id128 as 32 lowercase hexadecimal characters.

## 11. Instrument Dictionary

Hot market frames do not resend broker symbol strings.

Handshake/symbol-spec messages establish:

~~~text
instrument_id uint32
→ canonical symbol
→ broker symbol
→ price_scale
→ volume_scale
→ tick size
→ contract/tick-value metadata
→ specification revision
~~~

Execution commands bind to both instrument_id and the required spec_revision.

A changed broker specification invalidates stale sizing/execution approval.

## 12. Time Policy

Wire timestamps use uint64 nanoseconds since Unix epoch UTC.

The unit is always nanoseconds even when the source has lower real precision.

Source precision/provenance must be carried by the message/schema when material.

Katarina must not infer nanosecond measurement precision merely because the wire unit is nanoseconds.

Absolute monotonic clocks from Python and MQL5 are not assumed comparable across processes. Round-trip and component latency use local monotonic measurements plus explicit processing-duration fields where needed.

## 13. Message-Type Registry

Reserved initial ranges:

### 0–99 System / lifecycle

- 1 HELLO
- 2 HELLO_ACK
- 3 HEARTBEAT
- 4 PROTOCOL_ERROR
- 10 SNAPSHOT_REQUEST
- 11 SNAPSHOT_BEGIN
- 12 SNAPSHOT_CHUNK
- 13 SNAPSHOT_COMMIT
- 14 SNAPSHOT_ABORT

### 100–199 Market

- 100 TICK_EVENT
- 101 BAR_EVENT
- 102 SYMBOL_SPEC
- 103 SESSION_STATE

### 200–299 Account / broker state

- 200 ACCOUNT_DELTA
- 201 POSITION_DELTA
- 202 ORDER_STATE_EVENT

### 300–399 Execution

- 300 OPEN_INTENT
- 301 MODIFY_PROTECTION_INTENT
- 302 REDUCE_INTENT
- 303 CLOSE_INTENT
- 304 CANCEL_ORDER_INTENT
- 310 EXECUTION_ACK
- 311 TRADE_EVENT
- 312 RECONCILE_REQUEST
- 313 RECONCILE_REPORT

### 400–499 Health / diagnostics

- 400 HEALTH_EVENT
- 401 TRANSPORT_METRICS

Ranges 500+ remain reserved for later protocol review.

## 14. Why Separate Execution Intent Types

V1 does not use one giant command with many optional fields.

Separate message types reduce invalid combinations such as OPEN carrying close-only ticket fields, CLOSE accidentally carrying new-order semantics, MODIFY silently changing volume, or CANCEL being misinterpreted as position close.

Shared lineage is carried by a common execution-prefix layout, but each intent has its own strict schema.

## 15. Execution Lineage Prefix

Every broker-mutating intent includes logical equivalents of:

- execution_intent_id: Id128;
- order_id/client_request_id: Id128;
- snapshot_id: Id128;
- decision_id: Id128;
- risk_decision_id: Id128;
- instrument_id: uint32;
- spec_revision: uint32;
- expiry_time_ns: uint64;
- approved-risk binding/hash or version reference as finalized later.

The MT5 gateway rejects malformed, expired, mismatched or stale lineage.

## 16. Snapshot Transaction

Large complete state bootstrap is atomic at the Katarina state-cache level.

~~~text
SNAPSHOT_BEGIN
    ↓
SNAPSHOT_CHUNK #0
SNAPSHOT_CHUNK #1
...
    ↓
SNAPSHOT_COMMIT
~~~

Katarina does not install a partial snapshot.

The transaction binds snapshot_id, expected chunk count, expected record counts, sequence watermark, and total integrity value.

Missing, duplicate, conflicting or corrupt chunks cause SNAPSHOT_ABORT / SNAPSHOT_UNAVAILABLE.

## 17. Schema Evolution

KAT1 adopts SBE-style safe evolution principles.

Compatible changes:

- append new fixed fields at the end of a root block;
- increase schema_version;
- increase block_length;
- add new message types;
- append bounded variable sections according to the message contract.

Forbidden without a major compatibility break:

- reorder an existing field;
- change its primitive width;
- reuse a removed message/field semantic ID for a different meaning;
- silently change units;
- change scale interpretation;
- reinterpret enum values.

Older decoders use block_length/schema_version to skip fields they do not understand when the message policy permits it.

Unknown execution-critical schema versions fail closed.

## 18. String Policy

Strings are absent from normal tick hot-path frames.

When required:

- UTF-8 only;
- explicit byte length;
- strict maximum length;
- malformed UTF-8 rejected;
- no implicit NUL termination;
- unknown/unbounded text from a broker is never copied blindly into fixed protocol fields.

## 19. Decoder Failure Policy

The decoder rejects frames for wrong magic, incompatible wire major, invalid header length, impossible frame length, unsupported critical message, invalid enum, reserved flags set unexpectedly, sequence violation where ordering is required, malformed length/count, checksum failure, non-finite float, invalid scale/range, or trailing bytes not permitted by the active schema.

Critical protocol failure leads to NO NEW LIVE RISK until the affected state is re-established.

## 20. Golden Conformance Fixtures

Before Stage 04 is frozen, each foundational message class should have canonical fixtures containing exact field values, exact expected bytes/hex, expected decoded representation, and expected rejection cases.

Python and MQL5 must encode the same logical fixture to the same bytes and decode the same bytes to the same values.

This becomes the protocol conformance contract for later Stage 06/07 implementation.

## 21. Current Recommendation

Adopt KAT1 as a **custom SBE-inspired canonical binary protocol**, not as a raw memory-struct protocol and not as a full SBE/FlatBuffers/Protobuf dependency.

The first Stage 04 implementation target should cover HELLO/HELLO_ACK, SYMBOL_SPEC, TICK_EVENT, BAR_EVENT, ACCOUNT_DELTA, POSITION_DELTA, SNAPSHOT transaction, execution intents, EXECUTION_ACK, TRADE_EVENT, HEARTBEAT/HEALTH, and reconciliation.

No implementation is authorized to treat this draft as frozen until Stage 04 review is completed.
