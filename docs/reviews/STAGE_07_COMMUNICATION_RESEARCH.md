# Stage 07 — MT5 ↔ Python Communication Research

**Stage:** 07/40  
**Status:** RESEARCH COMPLETE / DESIGN ACTIVE  
**Reviewed:** 2026-10-03

## Scope

Stage 07 implements the communication layer between the transport-neutral MT5 bridge and Katarina/Python without changing the frozen KAT1 v1.0.0 wire contract.

Stage 07 does **not** own:

- discretionary trading logic;
- Risk Governor policy;
- broker execution semantics;
- durable execution idempotency;
- Strategy Tester orchestration;
- data-quality policy beyond transport/protocol integrity.

Those remain in their assigned stages.

## Frozen Inputs

Stage 07 must obey:

- Stage 02 transport policy:
  - ZeroMQ localhost primary;
  - native local TCP fallback;
  - TesterTransport abstraction;
  - bounded buffers;
  - reconnect never means READY;
- Stage 04 KAT1:
  - 52-byte little-endian header;
  - maximum frame 65,536 bytes;
  - stream_id / boot_id / sequence;
  - CRC32C rules;
  - canonical message registry and schemas;
- Stage 05 Core:
  - Core remains transport-independent;
  - readiness is separate from lifecycle;
- Stage 06 Bridge:
  - fast handlers do not block on transport;
  - transport work is performed from bounded timer work;
  - local_capture_id is not KAT1 sequence;
  - Stage-06 production broker mutation is still disabled until clearance.

## GitHub References Reviewed

### dingmaotu/mql-zmq

Useful findings:

- full MQL4/5 ZeroMQ binding;
- MQL strings are UTF-16 and binding converts to UTF-8;
- one shared ZeroMQ context per terminal process is recommended;
- blocking recv in an MQL thread can hang MetaTrader.

Katarina conclusion:

- ZeroMQ calls must never block OnTick/OnTradeTransaction;
- communication belongs in bounded OnTimer work;
- one transport context per MT5 terminal process is the target;
- authoritative payload is raw KAT1 bytes, not MQL strings.

### coke5151/mql5-zmq

Useful findings:

- modern MQL5 fork fixes char[] / uchar[] conversion failures;
- explicitly targets 64-bit MT5;
- documents modern MetaEditor compatibility fixes;
- documents secondary DLL dependency behavior in Strategy Tester.

Katarina conclusion:

- use an MQL5-maintained ZeroMQ binding path for modern MT5 validation;
- perform a dedicated DLL/ZeroMQ compatibility spike before enabling the live adapter;
- do not make Stage 07 live transport responsible for Strategy Tester compatibility. TesterTransport remains separate.

### darwinex/dwx-zeromq-connector

Useful findings:

- demonstrates practical Python ↔ MetaTrader ZeroMQ architecture;
- separates market publishing and trade/control communication;
- explicitly warns that dependency/runtime issues can produce apparent resource timeouts;
- project is legacy/archived direction and successor moved away from ZeroMQ.

Katarina conclusion:

- adopt the communication lessons, not its JSON/trading semantics;
- KAT1 remains the canonical binary contract;
- dependency/DLL failure must surface as transport health failure, never as a trading signal;
- avoid tight coupling between trading semantics and transport library.

### Darwinex/dwxconnect

Useful findings:

- file-based fallback architecture shows why transport-neutral application contracts matter;
- state resynchronization after process restart is necessary;
- simple communication can still miss intermediate state without explicit recovery.

Katarina conclusion:

- live transport may change without changing Brain contracts;
- reconnect always requires snapshot/reconciliation;
- file transport is not promoted to production live hot path, but reinforces TesterTransport abstraction.

### Bandd-Analytics/core-helix

Useful findings:

- explicit bridge compatibility spike before adopting a ZeroMQ DLL stack;
- async Python ZeroMQ consumer;
- heartbeat/staleness tracking;
- reconnect backoff;
- warning that a stale bridge must not be treated as ready;
- real-world evidence that older mql-zmq may fail on modern MT5 builds while an MQL5-focused fork compiles.

Katarina conclusion:

- add a Stage-07 ZeroMQ capability spike/gate;
- Python side should use nonblocking/async receive;
- heartbeat updates transport health only;
- a real heartbeat is required after reconnect; reconnect itself does not reset health to ready.

## Transport Topology Decision — Draft

### Primary live topology

~~~text
Katarina / Python
    ROUTER
    bind tcp://127.0.0.1:<port>
        │
        │ one ZeroMQ message = one complete KAT1 frame
        │
        ▼
MT5 Bridge
    DEALER
    connect tcp://127.0.0.1:<port>
~~~

Why this topology is preferred:

- Python is the central brain and natural local server;
- multiple future bridge instances can be multiplexed by ROUTER;
- DEALER is asynchronous and does not impose REQ/REP lock-step;
- bidirectional command/event traffic can use one logical connection;
- KAT1 already provides message type, sequence and execution lineage.

The ZeroMQ routing identity is transport metadata only. KAT1 account/stream/boot identity remains authoritative.

### Initial contact

A ROUTER cannot address a DEALER until the DEALER has emitted traffic.

Therefore the first MT5 frame after socket connectivity is a KAT1 HEARTBEAT/presence frame.

~~~text
MT5 DEALER
→ HEARTBEAT
→ Python ROUTER learns route
→ Python sends HELLO
→ MT5 sends HELLO_ACK
→ snapshot/recovery/reconciliation
~~~

The initial heartbeat does **not** make the bridge READY.

### ZeroMQ frame rule

One ZeroMQ message contains exactly one KAT1 frame.

No JSON envelope.
No multipart application payload.
No transport-specific business fields.

### Native TCP fallback

TCP uses the same KAT1 frame bytes.

Because TCP is a byte stream, receiver logic is:

~~~text
read 52-byte header
→ validate preliminary frame_length
→ reject > 65,536 or < header
→ read remaining frame_length - 52 bytes
→ pass complete bytes to KAT1 decoder
~~~

No secondary TCP framing format is introduced.

### TesterTransport

TesterTransport implements the same logical send/receive port but does not depend on sockets/DLLs.

The exact Strategy Tester implementation remains Stage 35.

## Sequence Ownership

KAT1 frame sequence is assigned at serialization time after permitted coalescing.

Therefore:

~~~text
Stage-06 local_capture_id
!=
KAT1 sequence
~~~

Rules:

- every transmitted KAT1 frame gets one monotonically increasing stream sequence;
- dropped/replaced local advisory ticks before serialization consume no wire sequence;
- critical frame serialization followed by uncertain transport delivery still consumes its sequence;
- reconnect never resets sequence within the same stream_id;
- a new stream_id establishes a new sequence namespace.

Durable execution event_cursor remains distinct from transport sequence.

## Heartbeat / Liveness — Draft

Heartbeat is bidirectional and transport-health only.

Draft baseline:

- heartbeat interval: 1 second;
- stale threshold: 5 seconds;
- reconnect uses bounded exponential backoff;
- reconnect completion requires an actual received heartbeat/HELLO exchange.

These timing values remain tunable until Stage-07 profiling.

Never compare monotonic timestamps across MT5 and Python as a shared epoch.

## Reconnect State Machine

~~~text
STOPPED
  ↓
CONNECTING
  ↓
SOCKET_CONNECTED
  ↓
PRESENCE_SEEN
  ↓
HELLO_SENT
  ↓
HELLO_ACK_VALID
  ↓
RECOVERY_REQUIRED
  ↓
SNAPSHOT + RECONCILIATION
  ↓
TRANSPORT_READY
~~~

Any of these force degradation:

- socket disconnect;
- stale heartbeat;
- invalid KAT1 frame;
- unsupported critical schema/flag;
- stream/boot inconsistency;
- critical sequence gap;
- receive/send queue overflow.

Transport ready alone still does not imply live-risk ready.

## Backpressure

Python and MQL queues remain bounded.

Priority:

1. execution/trade/reconciliation;
2. account/position/risk state;
3. bars;
4. ticks/telemetry.

Market-data coalescing may happen only before KAT1 sequence assignment.

Critical message loss is never silently tolerated.

## Security Boundary

Stage-07 live endpoints:

- bind/connect only to 127.0.0.1 by default;
- public wildcard bind is forbidden;
- no credentials are sent over a public network;
- transport route identity is not authorization;
- KAT1 identity/binding plus later execution readiness remains authoritative.

Curve/security mechanisms are unnecessary for the approved localhost baseline and would add DLL/configuration complexity without replacing account/intent binding.

## Dependency Decision — Draft

Python live primary:

- pyzmq, async-capable.

MQL5 live primary:

- modern MQL5-compatible ZeroMQ binding, validated by a dedicated capability spike.

Fallback:

- native MQL5 socket API over localhost TCP.

The Brain and KAT1 codec may not import pyzmq directly. Only the ZeroMQ adapter may.

## Stage-07 Implementation Order

1. freeze Stage-07 architecture boundaries;
2. implement Python KAT1 frame/payload codec and golden-vector tests;
3. define application-owned TransportPort;
4. implement in-memory loopback transport tests;
5. implement ZeroMQ capability spike;
6. after Stage-06 external clearance, integrate MQL5 KAT1 codec;
7. reproduce all Stage-04 golden vectors on MQL5;
8. implement ZeroMQ live adapter;
9. implement native TCP fallback;
10. implement handshake/heartbeat/reconnect supervisor;
11. run disconnect/reconnect/backpressure tests;
12. final Stage-07 audit/freeze.

## Current Gate

Stage 07 research/design and pure-Python conformance work may proceed while Stage 06 waits for external proof.

Production MQL5 transport integration must not modify the Stage-06 clearance candidate before that candidate is proven/frozen.
