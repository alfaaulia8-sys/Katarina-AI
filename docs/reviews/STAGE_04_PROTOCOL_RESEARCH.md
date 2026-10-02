# STAGE 04 — DATA PROTOCOL / SCHEMA RESEARCH

**Stage:** 04/40  
**Status:** IN REVIEW  
**Reviewed:** 2026-10-02

## Purpose

Define one deterministic language for MT5 ↔ Katarina messages before implementation of the Brain, EA bridge, transport, validation, and execution modules.

Stage 04 must remove ambiguity around framing, byte order, primitive widths, identifiers, timestamps, numeric representation, versioning, message types, bounded variable data, corruption detection, compatibility, and conformance fixtures.

## GitHub References Reviewed

### FIX Simple Binary Encoding (SBE)

Repository: FIXTradingCommunity/fix-simple-binary-encoding

Useful ideas:

- explicit binary message header;
- template/message IDs;
- block length;
- schema version on wire;
- positional fixed fields without field-name overhead;
- bounded repeating groups;
- compatible schema extension by appending fields;
- explicit framing when transport does not provide safe record boundaries.

Katarina should adopt fixed positional fields, explicit message type, explicit schema version, explicit fixed block length, and append-only compatible payload evolution.

Katarina should not copy the full SBE XML/code-generation ecosystem because there is no native MQL5 target and it would add build complexity.

### FlatBuffers

Repository: google/flatbuffers

Useful ideas:

- schema-defined binary buffers;
- reduced parsing/allocation;
- forward/backward schema thinking;
- strong typed access.

Weakness for Katarina: MQL5 integration/code generation would be disproportionately complex for the initial bridge.

### MT5 protocol examples

Repositories reviewed included:

- microqqq/arbi-nautilus;
- parrondo/mql5-json-api;
- dingmaotu/mql-zmq.

Useful production lessons:

- request receipt is not fill proof;
- stream/boot identity matters;
- durable cursor/event replay matters;
- strict request grammar is valuable;
- bounded frames prevent uncontrolled resource use;
- account/build/symbol binding should fail closed;
- ambiguous execution must remain UNKNOWN until reconciliation.

The JSON-based examples are valuable for semantics and recovery, but Katarina keeps the Stage 02 decision to use binary on the production hot path.

## MQL5 Platform Findings

MQL5 exposes fixed-width integer types suitable for an explicit binary codec, including 8/16/32/64-bit unsigned and signed values.

MQL5 double is IEEE-754 64-bit.

MQL5 can copy POD structures to byte arrays and can send uchar arrays through sockets, but Katarina should **not** define the wire contract as a raw in-memory struct dump.

Reasons:

- structure padding/alignment can become an implicit protocol;
- schema evolution becomes fragile;
- byte order becomes accidental rather than explicit;
- one language/compiler layout can leak into the external contract.

Katarina should manually encode/decode canonical fields using explicit offsets and byte order.

## Options Compared

| Option | Advantages | Weaknesses | Decision |
|---|---|---|---|
| JSON | easiest to inspect | text parsing, large, repeated keys | audit/debug only |
| MessagePack | compact, flexible | weak MQL5 ecosystem, less strict schema | not primary |
| Protocol Buffers | excellent schema evolution | MQL5/codegen/dependency burden | not primary |
| FlatBuffers | fast access, schema based | substantial MQL5 integration complexity | not primary |
| Full SBE | finance/low-latency oriented | no native MQL5 generator, more tooling | principles only |
| **Katarina SBE-inspired canonical binary** | fast, compact, deterministic, simple MQL implementation | custom codec must be tested rigorously | **recommended** |

## Research Conclusion

Recommended Stage 04 direction:

~~~text
ONE CANONICAL AUTHORITATIVE BINARY PROTOCOL
        +
SBE-INSPIRED FIXED ROOT BLOCKS
        +
BOUNDED VARIABLE TAILS
        +
EXPLICIT LITTLE-ENDIAN ENCODING
        +
VERSIONED MESSAGE SCHEMAS
        +
GOLDEN CROSS-LANGUAGE FIXTURES
~~~

This removes the need for a second MessagePack codec in the authoritative MT5 path.

JSON remains for human audit and diagnostics.
