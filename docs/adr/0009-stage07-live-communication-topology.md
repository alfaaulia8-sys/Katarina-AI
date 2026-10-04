# ADR-0009 — Stage-07 Live Communication Topology

**Status:** Accepted
**Stage:** 07\n**Accepted:** 2026-10-04

## Decision

For the Stage-07 live-primary draft, Python owns a localhost ZeroMQ ROUTER endpoint and each MT5 bridge connects as a DEALER peer.

One ZeroMQ message carries one complete KAT1 frame. KAT1 remains the only application wire contract.

Native local TCP is the fallback and carries the exact same KAT1 frame bytes, using KAT1 frame_length for stream framing.

## Why

- Python is the central Katarina process and can multiplex future bridge sessions.
- DEALER/ROUTER is asynchronous and does not impose REQ/REP lock-step.
- One bidirectional connection can carry events, heartbeat, handshake and commands.
- Transport metadata does not replace KAT1 identity/account/stream binding.
- The same logical TransportPort can be implemented by ZeroMQ, TCP, memory and later TesterTransport.

## Initial-contact constraint

A ROUTER learns a DEALER route only after the peer sends traffic. Therefore MT5 emits a KAT1 HEARTBEAT presence frame first. Python then sends HELLO and the normal KAT1 recovery handshake begins.

Presence does not mean READY.

## Security

Production defaults are localhost-only. Public bind is prohibited by the frozen Stage-02 policy.

## Gate

The gate is satisfied. Stage-07 cross-language integration proved the ROUTER/DEALER primary path, native TCP fallback, reconnect behavior and fail-closed binding on modern Windows/MT5. Final governed clearance is `PASS_STAGE07_FINAL_CLEARANCE` from GitHub Actions run `37209799384` (head `f83ab5eb6f57b2c30428122f69a807c9ace673f1`).
