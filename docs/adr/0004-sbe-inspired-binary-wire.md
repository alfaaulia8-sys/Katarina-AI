# ADR-0004 — SBE-Inspired Canonical Binary Wire Protocol

**Status:** Accepted  
**Stage:** 04

## Context

Katarina needs a fast deterministic MT5 ↔ Python protocol with explicit versioning and bounded decoding.

JSON is easy to debug but adds repeated text parsing and field-name overhead. MessagePack, Protobuf, FlatBuffers and full SBE each add different levels of external tooling/dependency complexity on the MQL5 side.

## Decision

Use one custom canonical binary protocol with:

- explicit little-endian encoding;
- fixed message header;
- message type and schema version;
- SBE-inspired block-length evolution;
- scaled integers for execution-sensitive decimal values;
- bounded variable tails;
- explicit cross-language golden fixtures;
- no raw native-struct wire contract.

## Consequences

Advantages:

- compact and fast;
- no second production codec;
- easy explicit MQL5 byte encoder;
- deterministic Python/MQL5 conformance;
- schema evolution rules are visible.

Costs:

- Katarina owns the codec;
- malformed-frame validation must be rigorous;
- schema changes require discipline;
- conformance tests are mandatory.

Stage 04 review completed. KAT1 v1.0.0 is frozen as the canonical MT5 ↔ Katarina binary wire contract.
