# ADR-0012 — Stage-07 Bidirectional KAT1 Sequence Lanes

**Status:** Proposed  
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

## Gate

Promote this ADR after:

1. Python lane validation tests pass;
2. MT5 persistent sequence allocator compiles and survives simulated reboot;
3. cross-language reconnect test proves both lane counters continue without
   duplicates or gaps.
