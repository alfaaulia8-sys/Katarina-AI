# Katarina MT5-Python Communication — Draft

Stage: 07/40
Version: 0.1.0
Status: IN REVIEW

## Boundary

Stage 07 implements communication only. KAT1 remains the authoritative wire contract. Core remains transport-independent. Strategy, risk policy, execution journaling, and tester orchestration stay in later stages.

## Primary live topology

Python is the local ZeroMQ server using ROUTER. MT5 is the local ZeroMQ client using DEALER. Production endpoints are localhost-only.

One ZeroMQ message carries one complete KAT1 frame. No JSON wrapper is added.

## Initial handshake

MT5 first emits a KAT1 HEARTBEAT presence frame so the ROUTER learns the peer route. Python then sends HELLO, MT5 replies HELLO_ACK, and recovery proceeds through snapshot and reconciliation. A heartbeat or socket connection never implies live-risk readiness.

## TCP fallback

Native local TCP carries the exact same KAT1 bytes. TCP framing uses the existing 52-byte KAT1 header and frame_length. No second application framing format is introduced.

## Sequence ownership

KAT1 sequence is assigned after permitted local coalescing and before serialization. Stage-06 local_capture_id is not the wire sequence. Reconnect does not reset sequence inside the same stream_id.

## Heartbeat and reconnect

Draft heartbeat interval is 1 second and stale threshold is 5 seconds, subject to profiling. Reconnect requires a real heartbeat plus HELLO/HELLO_ACK and then recovery; reconnect alone does not restore readiness.

## Backpressure

All queues are bounded. Critical execution and risk-state traffic has priority over bars, ticks, and advisory telemetry. Unsent ticks may be coalesced before sequence assignment. Critical loss is fail-closed.

## KAT1 codec

Python codec work may proceed now. It must validate the 52-byte header, CRC32C, frozen schema layouts, bounded UTF-8 tails, embedded snapshot records, and exact scaled integers. It must reproduce Stage-04 golden vectors.

MQL5 codec integration waits for Stage-06 external clearance so the Stage-06 proof candidate is not mutated.

## ZeroMQ capability gate

Before live integration, the modern Windows MT5 target must prove that the MQL5 ZeroMQ binding compiles, the required DLLs load, localhost send/receive works, and polling is nonblocking.

## Security

Production defaults are localhost-only. Transport routing identity is metadata, not authorization. KAT1 account/stream/boot binding remains authoritative.

## Acceptance draft

Stage 07 cannot freeze until Stage 06 is externally cleared; Python and MQL5 codecs match all golden vectors; cross-language bytes match; ZeroMQ and TCP integrations pass; reconnect/backpressure tests pass; binding mismatches fail closed; and final audit passes.

## Current boundary

Allowed now: research, architecture, Python transport contracts, Python KAT1 conformance, and in-memory tests.

Blocked until Stage-06 proof: modifying the Stage-06 MQL bridge for live ZeroMQ/TCP integration, enabling external execution commands, or claiming production communication is operational.
