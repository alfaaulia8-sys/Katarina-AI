# Stage 07 — Freeze Record

**Status:** FINALIZED / FROZEN v1.0.0  
**Stage:** MT5 ↔ Python Communication  
**Freeze date:** 2026-10-04

## Governed freeze result

`PASS_STAGE07_FINAL_CLEARANCE`

Stage 07 is frozen under accepted ADR-0009, ADR-0011 and ADR-0012 and against the frozen Stage-04 KAT1, Stage-05 Core and Stage-06 Bridge contracts.

## Frozen communication contract

- Primary live transport: localhost ZeroMQ, Python ROUTER bind / MT5 DEALER connect.
- One ZeroMQ message carries exactly one complete KAT1 frame.
- Fallback live transport: native localhost TCP.
- TCP stream framing uses the frozen KAT1 `frame_length`; there is no secondary application envelope.
- KAT1 identity/account/stream binding is authoritative; routing metadata is not authorization.
- Initial MT5 presence HEARTBEAT does not imply READY.
- HELLO / HELLO_ACK is followed by binding validation, snapshot recovery and reconciliation.
- READY requires completed recovery; reconnect alone never marks the session READY.
- Sequence namespace is stream ID plus producer role.
- MT5→Python and Python→MT5 sequence lanes remain monotonic and independent.
- Duplicate/decreasing sequence fails closed.
- A gap requires recovery and fails closed until recovery completes.
- Reconnect does not reset sequence state for the same stream.
- Queues are bounded; critical loss is prohibited.
- Critical control frames are retried without allocating a replacement sequence.
- Production transport endpoints remain localhost-only; public bind is prohibited.
- Stage-06 timer/queue safety budgets remain inherited.
- Stage 07 introduces no broker order submission and never grants live-risk readiness.

## Freeze-qualified evidence

- Validation host: Windows Server 2022 x64
- GitHub Actions workflow: `Stage 07 Final Clearance`
- GitHub Actions run: `37209799384`
- Evidence head SHA: `f83ab5eb6f57b2c30428122f69a807c9ace673f1`
- 37/37 Stage-07 Python regressions: PASS
- MQL5 KAT1 codec / 13 frozen golden vectors: PASS
- ZeroMQ ROUTER ↔ DEALER raw KAT1 roundtrip: PASS
- HEARTBEAT → HELLO → HELLO_ACK: PASS
- Cross-language snapshot/reconciliation recovery: PASS
- Cross-language recovery byte equality: PASS
- Persistent wire-sequence restart continuity: PASS
- Cross-process reconnect with stable stream sequence: PASS
- Native MQL5 TCP fallback compile: 0 errors / 0 warnings
- Native TCP MQL5 ↔ Python byte equality: `PASS_STAGE07_NATIVE_TCP_FALLBACK`
- Native TCP EX5 SHA-256: `c9518375d0b06736ab5f26a62ac2ec5ceadf623f1336b3eccad732ce1aeb1ce4`
- Bounded backpressure/critical retry profile: `PASS_STAGE07_BACKPRESSURE_LATENCY_PROFILE`
- TCP loopback p99: `0.202 ms`
- KAT1 codec decode p99: `290.3 µs`
- Inherited Stage-06 timer budget: `2000 µs`
- Final evidence-bound audit: `PASS_STAGE07_FINAL_CLEARANCE`
- `ready_for_stage08=true`
- `live_risk_ready=false`
- Freeze artifact: `stage07-final-clearance-evidence`
- Artifact ID: `11306007351`
- Artifact digest: `sha256:d95c9f12816017ea87291582ffdded60c0d298035ca82bc55c689e1f94df2532`

## Legacy VPS boundary

The Windows Server 2012 R2 VPS remains an operational and compatibility lab. Its low-memory control plane, guardian/watchdog recovery and sparse GitHub write path are useful for diagnostics and later integration work, but they are not the freeze-qualified basis for Stage 07.

The freeze-qualified proof is the governed Windows Server 2022 run above.

## Safety boundary

Stage 07 proves communication, binding, recovery, sequencing and transport behavior. It does **not** authorize live broker risk.

The following remain blocked until later governed stages:

- live broker-risk enablement;
- production-ready trading claims;
- strategy-generated discretionary order authorization;
- any weakening of Stage-04, Stage-05, Stage-06 or Stage-07 fail-closed invariants.

## Governance consequence

Stage 08 — Data Validation Engine is unblocked.

Any later change to Stage-07 transport topology, KAT1 framing, binding, recovery, sequence semantics, queue/backpressure behavior or localhost-only security boundary requires explicit governed review and new evidence.
