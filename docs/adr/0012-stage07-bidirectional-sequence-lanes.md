# ADR-0012 — Stage-07 Bidirectional KAT1 Sequence Lanes

**Status:** Accepted  
**Stage:** 07  
**Wire change:** none

## Problem

KAT1 carries a single `sequence:u64` in every frame and Stage-07 live transport is
bidirectional. MT5 and Python are independent producers. A single shared counter
cannot be allocated safely by two processes without an additional coordination
protocol and would create collision/race risk.

The existing wire contract already exposes enough information to avoid adding a
field.

## Proposed interpretation

A KAT1 sequence namespace is:

~~~text
(stream_id, producer_role)
~~~

Producer roles for Stage 07 are:

- `MT5_TO_PYTHON`;
- `PYTHON_TO_MT5`.

Each lane is strictly monotonically increasing and independent.

This is an implementation clarification only. The KAT1 header remains unchanged.

## MT5 → Python lane

MT5 owns this counter for all frames it produces.

Rules:

- assign sequence after any permitted pre-wire coalescing;
- persist the latest allocated sequence with the persistent stream identity;
- reconnect does not reset it;
- a new boot_id does not reset it while stream_id is unchanged;
- if MT5 cannot prove the next value after restart, it must fail closed or create
  a governed new stream identity rather than reuse a sequence.

`HEARTBEAT.latest_produced_sequence` reports this lane's latest produced value.

## Python → MT5 lane

Python owns this counter for commands/system frames it produces.

Rules:

- reconnect does not reset it for the same stream_id;
- after Python restart/recovery, the next value must be greater than MT5's
  `HEARTBEAT.latest_consumed_command_sequence`;
- the local Python counter may also retain a higher value and must never move
  backwards.

`HEARTBEAT.latest_consumed_command_sequence` is therefore the remote floor for
Python's next outbound sequence.

## Receive validation

Within either producer lane:

- duplicate sequence: reject/fail closed;
- decreasing sequence: reject/fail closed;
- observed gap: recovery required/fail closed;
- new stream_id: starts a new lane namespace.

A sequence gap is treated as integrity loss even if the currently observed frame
is advisory, because the receiver cannot safely infer the criticality of the
missing frame.

## Reconnect

Socket reconnect alone never changes sequence ownership or readiness.

For the same stream_id:

~~~text
fresh HEARTBEAT
→ validate MT5 lane sequence continuity
→ seed Python lane above latest_consumed_command_sequence
→ HELLO / HELLO_ACK
→ snapshot + reconciliation
→ communication READY
~~~

## Safety

Sequence continuity is transport/protocol integrity only. It never grants live-risk
readiness.

## Acceptance evidence

Accepted after all three sequence-lane gates passed:

- Python duplicate/decreasing/gap/floor validation: PASS;
- MT5 persistent directional allocator survives a fresh terminal process: PASS;
- cross-process MT5 ↔ Python reconnect and full recovery: PASS.

Cross-process evidence:

- workflow run: `37166695631`;
- head SHA: `ced99e3d13924e368b05a171d24dffe490ef1fa0`;
- artifact: `stage07-cross-process-reconnect-evidence`;
- artifact digest: `sha256:a6a340a756d802200f63d33231be6d8d94511e4d637641a87bca24705461f286`;
- stable stream_id across reconnect: PASS;
- boot_id changed: PASS;
- MT5 lane: `1..7 → 8..14`;
- Python lane: `1..4 → 5..8`;
- duplicate/gap: none;
- stale gate + re-handshake + repeated snapshot/reconciliation: PASS;
- final communication state: READY;
- live-risk readiness: false.

This acceptance resolves directional sequence ownership only; it does not by itself
freeze Stage 07.
