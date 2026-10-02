# MT5 Layer

This tree contains the MQL5 bridge, include files, and MT5-side tests.

Allowed responsibilities:

- market/account sensing;
- protocol-facing communication;
- deterministic local safety;
- execution gateway;
- transaction reporting/reconciliation support.

MT5 must not become a second discretionary trading brain.

## Stage 06 — In Review

Current files:

- `Experts/KatarinaBridgeEA.mq5`
- `Include/Katarina/BridgeState.mqh`
- `Include/Katarina/EventBuffer.mqh`
- `Include/Katarina/NativeFacts.mqh`
- `Include/Katarina/TransportPort.mqh`

Current behavior:

~~~text
OnInit
→ validate account/symbol facts
→ init buffers
→ start timer
→ RECOVERING
→ execution NOT armed

OnTick
→ capture latest tick only

OnTradeTransaction
→ capture raw transaction/result evidence
→ bounded critical queue
→ overflow = BLOCKED / fail-closed

OnTimer
→ bounded housekeeping
→ future Stage-07 transport pump

OnDeinit
→ disarm
→ stop timer/transport
→ STOPPED
~~~

Important: Stage 06 currently uses a NullTransport and has no external execution command path. It deliberately remains RECOVERING until later complete snapshot/transport/reconciliation readiness is implemented.

Concrete ZeroMQ/TCP communication belongs to Stage 07.
