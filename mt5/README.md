# MT5 Layer

This tree contains the MQL5 bridge, include files, and MT5-side tests.

Allowed responsibilities:

- market/account sensing;
- protocol-facing communication;
- deterministic local safety;
- execution gateway;
- transaction reporting/reconciliation support.

MT5 must not become a second discretionary trading brain.

## Stage 06 — In Review v0.2.0

Current production bridge:

- `Experts/KatarinaBridgeEA.mq5`

Current include modules:

- `Include/Katarina/BarSource.mqh`
- `Include/Katarina/BridgeState.mqh`
- `Include/Katarina/BrokerCalc.mqh`
- `Include/Katarina/BrokerReason.mqh`
- `Include/Katarina/DealHistory.mqh`
- `Include/Katarina/EventBuffer.mqh`
- `Include/Katarina/ExecutionPreflight.mqh`
- `Include/Katarina/HealthSample.mqh`
- `Include/Katarina/InstanceGuard.mqh`
- `Include/Katarina/NativeFacts.mqh`
- `Include/Katarina/NativeSnapshot.mqh`
- `Include/Katarina/SessionState.mqh`
- `Include/Katarina/SymbolRegistry.mqh`
- `Include/Katarina/TransportPort.mqh`

Tests:

- `Tests/KatarinaStage06SelfTest.mq5`
- `Tests/KatarinaStage06AccountProbe.mq5`

Current behavior:

~~~text
OnInit
→ account + SymbolSpec facts
→ duplicate-instance lease
→ approved symbol validation
→ bounded critical buffer
→ complete local account/position/order snapshot
→ health/session sample
→ NullTransport
→ timer
→ RECOVERING
→ execution NOT armed

OnTick
→ latest tick capture only

OnTradeTransaction
→ raw transaction/request-validity capture only
→ bounded critical queue
→ snapshot dirty
→ overflow = BLOCKED / fail-closed

OnTimer
→ lease refresh
→ account/health/session refresh
→ deferred snapshot rebuild
→ deferred reason enrichment
→ bounded future transport drain

OnDeinit
→ disarm
→ stop timer/transport
→ release lease
→ STOPPED
~~~

Important:

- Stage 06 has no OrderSend/OrderSendAsync path.
- NullTransport cannot become ready.
- execution is never automatically armed.
- the bridge deliberately remains RECOVERING.
- concrete ZeroMQ/TCP communication belongs to Stage 07.

Compile/runtime proof procedure:

- `../docs/operations/STAGE_06_MT5_COMPILE_PROOF.md`
- `../scripts/mt5/compile_stage06.ps1`
