# ADR-0009 — Stage-07 Live Communication Topology

**Status:** Proposed
**Stage:** 07

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

This ADR stays Proposed until Stage-07 integration tests prove the topology on modern Windows/MT5 and Stage-06 external clearance is complete.
