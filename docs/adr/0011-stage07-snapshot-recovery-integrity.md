# ADR-0011 — Stage-07 Snapshot Recovery Integrity Semantics

**Status:** Proposed  
**Stage:** 07  
**Protocol affected:** KAT1 v1.0.0 implementation clarification only

## Context

The frozen Stage-04 schema already defines:

- `SNAPSHOT_CHUNK.payload_crc32c`;
- `SNAPSHOT_COMMIT.aggregate_crc32c`;
- `RECONCILE_REPORT.discrepancies` with encoding `repeated_len32_record`.

The wire fields and their widths are frozen, but the repository did not record the
byte-level aggregation rule for those three constructs. Stage 07 must not silently
invent incompatible producer/consumer behavior.

## Proposed interpretation

### repeated_len32_record

The variable field is a concatenation of zero or more opaque records:

~~~text
record := body_length:u32 little-endian + body[body_length]
field  := record*
~~~

No nested KAT1 header is present.

The discrepancy body remains opaque to Stage 07. A nonzero discrepancy count blocks
recovery readiness regardless of body contents.

### SNAPSHOT_CHUNK payload_crc32c

`payload_crc32c` is CRC32C-Castagnoli over the exact serialized bytes of the
`records` variable field only, excluding:

- the outer 52-byte KAT1 frame header;
- the SNAPSHOT_CHUNK fixed root block;
- the outer KAT1 CRC32C trailer.

For an empty records field, CRC32C(empty) is `0x00000000`.

### SNAPSHOT_COMMIT aggregate_crc32c

`aggregate_crc32c` is CRC32C-Castagnoli over the concatenation of each chunk's
exact serialized `records` variable bytes in strictly increasing
`chunk_index` order.

For a zero-byte snapshot, CRC32C(empty) is `0x00000000`.

## Atomic recovery requirements

A snapshot transaction is accepted only if:

1. one SNAPSHOT_BEGIN starts a new snapshot;
2. chunk indexes are unique and contiguous from zero;
3. each chunk ID equals the active snapshot ID;
4. each chunk record_count equals the decoded record count;
5. each chunk_payload_bytes equals the serialized records-byte count;
6. each chunk payload CRC matches;
7. SNAPSHOT_COMMIT ID, counts, total bytes, aggregate CRC and account revision all match;
8. SNAPSHOT_ABORT invalidates the transaction;
9. no partial snapshot can be installed.

After an accepted snapshot, reconciliation is still mandatory.

A RECONCILE_REPORT permits communication readiness only when:

- request_id and snapshot_id match the outstanding reconciliation request;
- discrepancy_count is zero;
- the discrepancy variable field is empty;
- recovery_state is READY (enum value 2);
- event cursor range is monotonic.

## Safety boundary

This ADR does not change any Stage-04 field, width, message ID, enum or direction.
It only proposes the missing serialization/integrity semantics needed by Stage 07.

Until cross-language tests prove these semantics, Stage 07 remains fail-closed and
must not mark the session READY.

Live-risk readiness remains outside Stage 07 even after communication recovery.

## Gate

Promote this ADR from Proposed only after Python and MQL5 generate identical bytes
and CRCs for snapshot/reconciliation fixtures on modern Windows/MT5.
