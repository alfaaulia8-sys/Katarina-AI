# STAGE 06 — KAT1 FIELD SOURCE MAPPING

**Status:** IN REVIEW  
**Stage:** 06/40  
**KAT1:** v1.0.0

## Purpose

Define where authoritative MT5-side facts come from before Stage 07 adds the binary codec and transport.

Frozen KAT1 remains defined by protocol/kat1_message_schemas_v1.json and protocol/payload_catalog_v1.json.

## General conversion rules

- MT5 broker-native doubles are not serialized as raw MQL5 structs.
- Stage 07 converts exact execution-sensitive values into KAT1 scaled integers.
- MQL5 epoch milliseconds are converted to KAT1 nanosecond wire units by multiplying by 1,000,000.
- MQL5 epoch seconds are converted by multiplying by 1,000,000,000.
- GetTickCount64/GetMicrosecondCount are local monotonic capture clocks only; they are never labeled UTC epoch time.
- Stage-06 local_capture_id is internal observation ordering only. It is NOT the KAT1 wire sequence. Stage 07 assigns wire sequence after any permitted coalescing.

## HELLO_ACK

- broker_login <- ACCOUNT_LOGIN
- terminal_build <- TERMINAL_BUILD
- account_mode <- ACCOUNT_MARGIN_MODE normalized
- trade_mode <- ACCOUNT_TRADE_MODE normalized
- money_scale/account_currency_digits <- ACCOUNT_CURRENCY_DIGITS
- broker_server <- ACCOUNT_SERVER
- account_currency <- ACCOUNT_CURRENCY
- account_id, stream_id, boot_id, source hash and capability synthesis are Stage-07/build identity work.

## TICK_EVENT

- bid/ask/last <- MqlTick.bid/ask/last
- broker event time <- MqlTick.time_msc
- tick flags <- MqlTick.flags
- volume <- MqlTick volume fields according to KAT1 presence policy
- instrument_id and spec_revision are Stage-07 dictionary/revision values.

Stage-06 source: SKatCapturedTick and KatCaptureTick.

## BAR_EVENT

Stage 06 does not fabricate bars from ticks. BarSource.mqh now reads broker series data through CopyRates/MqlRates outside OnTick, including OHLC, tick volume, real volume and spread.

## SYMBOL_SPEC

Native sources currently implemented:

- SYMBOL_DIGITS
- SYMBOL_TRADE_CALC_MODE
- SYMBOL_TRADE_MODE
- SYMBOL_ORDER_MODE
- SYMBOL_FILLING_MODE
- SYMBOL_EXPIRATION_MODE
- SYMBOL_TRADE_STOPS_LEVEL
- SYMBOL_TRADE_FREEZE_LEVEL
- SYMBOL_POINT
- SYMBOL_TRADE_TICK_SIZE
- SYMBOL_TRADE_TICK_VALUE
- SYMBOL_TRADE_TICK_VALUE_PROFIT
- SYMBOL_TRADE_TICK_VALUE_LOSS
- SYMBOL_TRADE_CONTRACT_SIZE
- SYMBOL_VOLUME_MIN / MAX / STEP / LIMIT
- SYMBOL_CURRENCY_BASE / PROFIT / MARGIN

Swap and margin-detail sources are now present in SKatSymbolFacts: SYMBOL_MARGIN_INITIAL / MAINTENANCE, SYMBOL_SWAP_MODE, SYMBOL_SWAP_LONG / SHORT, and all seven weekday swap ratios.

## SESSION_STATE / HEALTH

- terminal_connected <- TERMINAL_CONNECTED
- terminal_trade_allowed <- TERMINAL_TRADE_ALLOWED
- mql_trade_allowed <- MQL_TRADE_ALLOWED
- account trade allowed <- ACCOUNT_TRADE_ALLOWED
- expert trade allowed <- ACCOUNT_TRADE_EXPERT
- terminal_ping_us <- TERMINAL_PING_LAST
- server time <- TimeTradeServer() with explicit source precision
- last tick time <- MqlTick.time_msc

Stage-06 source: SKatHealthSample / KatSampleHealth.

Session schedule/open-state sourcing is implemented through SymbolInfoSessionTrade and broker/server time in SessionState.mqh. Stage 07 will encode the resulting state/revisions into KAT1.

## ACCOUNT_DELTA

Current native sources:

- ACCOUNT_BALANCE / EQUITY / CREDIT / PROFIT
- ACCOUNT_MARGIN / ACCOUNT_MARGIN_FREE
- ACCOUNT_LEVERAGE
- ACCOUNT_MARGIN_MODE
- ACCOUNT_TRADE_MODE
- ACCOUNT_CURRENCY / ACCOUNT_CURRENCY_DIGITS
- ACCOUNT_TRADE_ALLOWED / ACCOUNT_TRADE_EXPERT

Initial/maintenance margin, margin level, margin call, stopout mode/value, hedge permission and FIFO-close facts are now included in SKatAccountFacts.

## POSITION_DELTA / position snapshot

Stage 06 reads every current position with:

- PositionsTotal / PositionGetTicket
- POSITION_IDENTIFIER
- POSITION_SYMBOL / MAGIC / TYPE / REASON
- POSITION_TIME_MSC / POSITION_TIME_UPDATE_MSC
- POSITION_VOLUME
- POSITION_PRICE_OPEN / POSITION_PRICE_CURRENT
- POSITION_SL / POSITION_TP
- POSITION_SWAP / POSITION_PROFIT

Ticket and stable POSITION_IDENTIFIER are both preserved.

## ORDER_STATE_EVENT / order snapshot

Stage 06 reads every current order with:

- OrdersTotal / OrderGetTicket
- ORDER_SYMBOL / MAGIC / TYPE / STATE / REASON
- ORDER_TYPE_TIME / ORDER_TYPE_FILLING
- ORDER_TIME_SETUP_MSC / ORDER_TIME_DONE_MSC / ORDER_TIME_EXPIRATION
- ORDER_VOLUME_INITIAL / ORDER_VOLUME_CURRENT
- ORDER_PRICE_OPEN / ORDER_PRICE_STOPLIMIT
- ORDER_SL / ORDER_TP
- ORDER_POSITION_ID / ORDER_POSITION_BY_ID

## TRADE_EVENT / manual-origin evidence

Primary fast source is OnTradeTransaction.

MqlTradeRequest/MqlTradeResult are treated as meaningful only for TRADE_TRANSACTION_REQUEST.

Raw reason enrichment is performed later from ORDER_REASON, DEAL_REASON and POSITION_REASON so heavy history/current-state lookup stays out of OnTradeTransaction.

## ACCOUNT_LEDGER_EVENT

Authoritative source is MT5 deal history. Stage 06 now provides CKatDealHistoryRange, which reads:

- DEAL_TICKET / DEAL_TIME_MSC
- DEAL_TYPE / DEAL_REASON
- DEAL_PROFIT / DEAL_COMMISSION / DEAL_SWAP
- optional broker comment for audit.

Raw DEAL_TYPE and DEAL_REASON are preserved. CKatDealHistoryRange rejects oversized requested ranges rather than silently truncating them; normalization into balance/credit/charge/correction/bonus/commission/interest/dividend/tax remains a later Python responsibility.

## BROKER_CALC_REPORT

Stage 06 now provides BrokerCalc.mqh using OrderCalcProfit and OrderCalcMargin. Values remain in broker-native account units; no standard/cent multiplier is guessed.

## Snapshot completeness

CKatNativeSnapshot currently:

1. reads account facts;
2. enumerates every current position;
3. enumerates every current order;
4. rejects failed ticket enumeration;
5. rechecks totals after enumeration;
6. retries a bounded number of times.

A complete snapshot with zero records is distinct from snapshot build failure.

The local read is not claimed to be broker-atomic. Trade events plus later reconciliation provide continuity.

## Duplicate bridge protection

Stage 06 uses a terminal-global atomic lease with GlobalVariableSetOnCondition.

It protects multiple bridge instances inside one MT5 terminal/account context. It cannot alone detect the same broker account running in another terminal/process/machine; Stage-07 identity/stream binding and later reconciliation are still required.
