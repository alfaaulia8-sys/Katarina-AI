# STAGE 06 — MT5 BRIDGE INITIAL IMPLEMENTATION CHECK

**Stage:** 06/40  
**Status:** PASS FOR CONTINUED DEVELOPMENT / NOT FROZEN  
**Reviewed:** 2026-10-02  
**Bridge Draft:** v0.2.0

## Current Implementation

Implemented:

- `mt5/Experts/KatarinaBridgeEA.mq5`
- `mt5/Include/Katarina/BridgeState.mqh`
- `mt5/Include/Katarina/EventBuffer.mqh`
- `mt5/Include/Katarina/NativeFacts.mqh`
- `mt5/Include/Katarina/TransportPort.mqh`

## Safety Review

Current EA source contains no enabled:

- OrderSend path;
- indicator/strategy entry logic;
- WebRequest path;
- native Socket path;
- ZeroMQ implementation;
- automatic live execution arming.

Current bridge behavior:

~~~text
INIT
→ broker-native account/symbol validation
→ bounded buffers
→ timer
→ RECOVERING
→ READ-ONLY / NOT ARMED
~~~

OnTick remains capture-only.

OnTradeTransaction remains capture/enqueue-only.

Trade-event queue overflow blocks the bridge rather than silently dropping critical lifecycle evidence.

The latest tick is coalescible.

## Important Correction Made During Review

The first Stage-06 skeleton briefly promoted local initialization to READY_READONLY from OnTimer.

This was removed.

Reason:

~~~text
local initialization
!=
complete snapshot + transport + reconciliation proof
~~~

The bridge now remains RECOVERING until later readiness work actually proves the frozen Stage-02 chain.

The internal trade capture timestamp was also renamed to `capture_monotonic_ms` so it cannot be confused with KAT1 epoch event time.

## Additional Recheck Finding

Official MQL5 documentation states that the `request` and `result` parameters supplied to `OnTradeTransaction` are meaningful for `TRADE_TRANSACTION_REQUEST`; other transaction types must be interpreted from the transaction fields relevant to that type.

The initial Stage-06 capture structure copied result fields unconditionally.

This has been corrected:

- `request_result_valid` is explicit;
- result/request-derived values are zeroed for non-request transactions;
- result fields are copied only for `TRADE_TRANSACTION_REQUEST`;
- order `time_type` and `time_expiration` are now captured as native transaction facts.

This prevents meaningless result fields from being mistaken for broker execution evidence.

## Standard / Cent Review

NativeFacts reads broker account currency/currency digits and symbol contract/tick/volume facts.

No standard/cent multiplier is hard-coded.

## Hedging / Netting Review

The bridge reads native account margin mode and does not emulate a different position accounting mode.

Complete current account/position/order snapshot sourcing is now implemented with bounded stable retry. Broker-atomic continuity is still correctly delegated to transaction events plus later reconciliation.

## Compilation Status

This repository review environment does not provide MetaEditor/MetaTrader compilation.

Therefore the current MQL5 skeleton has been statically reviewed against official MQL5 API definitions, but **MetaEditor compile proof is still required before Stage 06 freeze**.

No production-readiness claim is made yet.

## Stage 06 v0.2 Work Completed

Since the initial check, Stage 06 now includes:

- complete account/position/order snapshot source with bounded stable retry;
- local duplicate bridge-instance lease guard;
- persistent stream_id + per-boot boot_id source;
- approved-vs-observed symbol registry;
- raw ORDER_REASON / DEAL_REASON / POSITION_REASON enrichment;
- terminal/account permission + ping health sampling;
- broker trading-session reader;
- complete Stage-04 account margin/stopout native facts;
- SymbolSpec margin/swap/weekday-swap native facts;
- bounded complete deal-history range reader;
- broker-native OrderCalcProfit / OrderCalcMargin wrapper;
- BAR_EVENT broker series source through CopyRates/MqlRates;
- local MARKET/LIMIT/STOP execution preflight with native-SL requirement;
- KAT1-to-MT5 field-source mapping;
- MQL self-test script;
- Python static bridge-safety test.

## Latest Static Source Recheck

A repository-level source audit was run over the current production MQL files.

~~~text
production bridge/include files checked : 16
forbidden OrderSend path                : 0
forbidden OrderSendAsync path           : 0
WebRequest/socket transport             : 0
strategy indicator calls                : 0
automatic SetExecutionArmed(true)       : 0
heavy history/session/calc in
OnTradeTransaction                      : 0
brace/parenthesis balance issues        : 0
include-guard issues                    : 0
static structural issues found          : 0
local capture ID / KAT1 sequence conflation : 0
~~~

This is a static source check, not a substitute for MetaEditor compilation.

## Remaining Stage 06 Freeze Blockers

- MetaEditor compile proof for KatarinaBridgeEA.mq5, KatarinaStage06SelfTest.mq5 and KatarinaStage06AccountProbe.mq5;
- run KatarinaStage06SelfTest.mq5 and the read-only account probe;
- run tests/static/test_stage06_mt5_bridge.py from a repository checkout;
- correct any compiler/runtime issues discovered;
- final Stage-06 audit/freeze.

## Result

**PASS FOR CONTINUED STAGE 06 DEVELOPMENT.**

Stage 06 remains **IN REVIEW**.


## v0.2 Safety Corrections Found During Continued Review

### Duplicate-Guard Initialization Race

The first lease implementation used GlobalVariableSet to create a missing mutex variable.

That contained a race:

~~~text
EA A sees missing
EA B sees missing
EA A creates + acquires
EA B performs unconditional GlobalVariableSet(0)
→ A's lease could be clobbered
~~~

The implementation now uses GlobalVariableTemp for missing-variable initialization and GlobalVariableSetOnCondition for ownership changes.

No unconditional write is used to overwrite an existing lease.

### Local Capture ID vs KAT1 Sequence

The original local field name `capture_sequence` could be confused with the frozen KAT1 frame sequence.

It was renamed to `local_capture_id`.

Rule:

~~~text
Stage-06 local_capture_id
!=
KAT1 wire sequence
~~~

Stage 07 assigns the KAT1 wire sequence only after permitted market coalescing.

### Snapshot Stability

The native snapshot builder now:

- rechecks position/order totals;
- re-selects each structural position/order record;
- rejects changed volume/SL/TP/order state/price structure during the read;
- re-reads account facts at the end;
- binds the installed local snapshot back to the active login/server.

It still does not claim broker-atomic state; later reconciliation remains authoritative.

### Stream / Boot Identity

Stage 06 now supplies:

- persistent stream_id scoped by server + login;
- per-initialization boot_id.

stream_id is persisted as two uint32 halves so a uint64 is not lossy-converted through one double terminal global variable.

account_id derivation remains Stage 07.


### Single-Symbol Realtime Scope Correction

The draft briefly exposed an input for multiple execution-approved symbols while the EA's realtime OnTick source only covers its chart symbol.

That could have implied market-data coverage that did not actually exist.

Stage 06 now enforces:

- chart symbol = the only execution-approved realtime market symbol;
- all other account symbols = observable through account-wide positions/orders/trade events;
- future multi-symbol execution approval = forbidden until an explicit multi-symbol tick source is implemented and validated.
