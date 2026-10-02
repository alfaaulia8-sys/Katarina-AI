# KAT1 — DATA CONTRACT CATALOG DRAFT

**Status:** IN REVIEW  
**Protocol:** KAT1  
**Draft:** 0.3  
**Stage:** 04/40

## 1. Data Ownership Rule

MT5 supplies broker/terminal facts.

Katarina/Python derives intelligence.

MT5 authoritative inputs include:

- raw ticks and broker bars;
- symbol contract/specification facts;
- account state;
- open positions and pending orders;
- transaction/order/deal events;
- session/trading permissions;
- terminal/bridge health;
- broker execution results.

Katarina derives:

- technical indicators;
- multi-timeframe structure;
- demand/supply analysis;
- regime;
- statistical features;
- model outputs;
- probability/confidence;
- OOD/uncertainty state;
- TradeCandidate;
- RiskDecision;
- position sizing;
- research/learning labels.

The EA must not calculate a second discretionary strategy merely to reduce traffic.

## 2. System / Identity Data

### HELLO

Katarina → MT5.

Logical fields:

- client_instance_id: Id128;
- requested_wire_major/minor;
- requested_capability_bits;
- requested_execution_mode;
- last_known_stream_id;
- last_known_execution_cursor;
- nonce/challenge field if later security design requires it.

### HELLO_ACK

MT5 → Katarina.

Logical fields:

- account_id: Id128;
- broker_login: uint64;
- broker_server: bounded UTF-8;
- terminal_build: uint32;
- ea_build_version: uint32;
- ea_source_hash: bytes32;
- stream_id: uint64;
- boot_id: uint64;
- account_mode enum;
- execution_mode enum;
- capability_bits: uint64;
- account_currency: bounded ASCII/UTF-8;
- money_scale: uint8;
- recovery_state enum;
- protocol compatibility result.

Identity mismatch is fail-closed.

## 3. Market Data

### TICK_EVENT

Hot-path fixed body proposal:

| Offset | Bytes | Field | Type |
|---:|---:|---|---|
| 0 | 4 | instrument_id | uint32 |
| 4 | 4 | spec_revision | uint32 |
| 8 | 8 | bid_units | int64 |
| 16 | 8 | ask_units | int64 |
| 24 | 8 | last_units | int64 |
| 32 | 8 | volume_units | int64 |
| 40 | 4 | tick_flags | uint32 |
| 44 | 4 | presence_flags | uint32 |

**Fixed body:** 48 bytes.

Frame `source_time_ns` is the broker tick/event timestamp.

Rules:

- bid/ask required for tradable tick;
- last/volume may be absent for OTC feeds and are controlled by presence flags;
- no symbol string is repeated;
- no indicator values are transported.

### BAR_EVENT

Fixed body proposal:

| Offset | Bytes | Field | Type |
|---:|---:|---|---|
| 0 | 4 | instrument_id | uint32 |
| 4 | 4 | spec_revision | uint32 |
| 8 | 2 | timeframe | uint16 |
| 10 | 1 | bar_state | uint8 |
| 11 | 1 | reserved | uint8 |
| 12 | 4 | bar_sequence | uint32 |
| 16 | 8 | bar_open_time_ns | uint64 |
| 24 | 8 | open_units | int64 |
| 32 | 8 | high_units | int64 |
| 40 | 8 | low_units | int64 |
| 48 | 8 | close_units | int64 |
| 56 | 8 | tick_volume | uint64 |
| 64 | 8 | real_volume_units | int64 |
| 72 | 4 | spread_points | uint32 |
| 76 | 4 | presence_flags | uint32 |

**Fixed body:** 80 bytes.

Protocol supports timeframe enum values independently from the active runtime subscription. Exact active timeframes/history depths remain runtime policy, not wire-format versioning.

## 4. Symbol / Contract Specification

### SYMBOL_SPEC

The message must carry enough broker-native information for deterministic sizing and preflight.

Required logical groups:

**Identity**
- instrument_id;
- spec_revision;
- canonical_symbol;
- broker_symbol;
- base/profit/margin currencies where available.

**Price**
- digits;
- price_scale;
- point;
- tick_size;
- tick_value;
- tick_value_profit;
- tick_value_loss.

**Contract**
- contract_size;
- calculation_mode;
- trade_mode.

**Volume**
- volume_scale;
- volume_min;
- volume_max;
- volume_step;
- volume_limit.

**Stops / execution**
- stops_level_points;
- freeze_level_points;
- order_mode bits;
- filling_mode bits;
- expiration_mode bits.

**Swap**
- swap_mode;
- swap_long;
- swap_short;
- weekday multiplier values when broker exposes them.

All execution-sensitive decimal values use canonical scaled integers or explicit fixed-scale fields.

Changing material contract fields increments `spec_revision`.

## 5. Session / Trading State

### SESSION_STATE

Logical fields:

- instrument_id;
- scheduled_open;
- terminal_connected;
- terminal_trade_allowed;
- mql_trade_allowed;
- symbol_trade_allowed;
- fresh_tick;
- session_open;
- last_tick_time_ns;
- server_time_ns;
- session/trading-state revision.

This message reports facts. It does not grant execution authority by itself.

## 6. Account Data

### ACCOUNT_DELTA

Account state is revisioned.

Logical fields:

- account_id;
- account_revision;
- presence_flags;
- balance_units;
- equity_units;
- credit_units;
- profit_units;
- margin_units;
- free_margin_units;
- leverage;
- margin_mode;
- stopout_mode/value when exposed;
- account_trade_allowed;
- account_expert_allowed.

All monetary values use the negotiated account `money_scale`.

A full account record is mandatory in bootstrap snapshots. Delta frames may use presence bits after bootstrap.

### ACCOUNT_LEDGER_EVENT — PROPOSED

Message ID 203 reserved.

Purpose: detect non-trading capital changes.

Logical event kinds:

- DEPOSIT;
- WITHDRAWAL;
- CREDIT;
- CHARGE;
- CORRECTION;
- OTHER_BALANCE_OPERATION.

Fields:

- account_id;
- broker_deal_id;
- event_kind;
- amount_units;
- event_time_ns;
- bounded broker reason code;
- optional bounded audit text outside the hot path.

Owner approval is required before this becomes mandatory V1 data.

## 7. Position Data

### POSITION_DELTA

Logical fields:

- account_id;
- position_ticket;
- position_identifier;
- instrument_id;
- spec_revision;
- magic;
- change_kind;
- side;
- volume_units;
- open_price_units;
- current_price_units;
- sl_units;
- tp_units;
- profit_units;
- swap_units;
- open_time_ns;
- update_time_ns;
- position_reason enum;
- presence_flags.

Snapshot contains complete current positions. Delta events represent changes after snapshot commit.

## 8. Pending / Broker Order Data

### ORDER_STATE_EVENT

Logical fields:

- account_id;
- broker_order_ticket;
- instrument_id;
- spec_revision;
- magic;
- order_type;
- order_state;
- order_reason;
- volume_initial_units;
- volume_current_units;
- price_open_units;
- stop_limit_units;
- sl_units;
- tp_units;
- expiration_time_ns;
- filling_mode;
- time_type;
- create_time_ns;
- update_time_ns;
- linked client order_id when Katarina owns the order.

External/manual orders are visible to risk/reconciliation even when Katarina is not authorized to mutate them.

## 9. Execution Intents

All execution messages are critical, CRC-protected, lineage-bound, and idempotent.

### Common lineage

- execution_intent_id: Id128;
- order_id/client_request_id: Id128;
- snapshot_id: Id128;
- decision_id: Id128;
- risk_decision_id: Id128;
- instrument_id;
- spec_revision;
- expiry_time_ns;
- policy/risk binding revision or hash.

### OPEN_INTENT

Logical fields:

- common lineage;
- side;
- order_type;
- volume_units;
- entry_price_units or price constraint;
- sl_units;
- tp_units;
- deviation_points;
- filling policy;
- time-in-force/expiration when applicable.

### MODIFY_PROTECTION_INTENT

- common lineage;
- position ticket + stable identifier;
- SL presence + new SL;
- TP presence + new TP.

This message cannot modify volume.

### REDUCE_INTENT

- common lineage;
- position ticket + stable identifier;
- reduce_volume_units.

### CLOSE_INTENT

- common lineage;
- position ticket + stable identifier;
- requested close volume or FULL_CLOSE flag.

### CANCEL_ORDER_INTENT

- common lineage;
- broker order ticket;
- linked order_id when present.

## 10. Execution Acknowledgement / Trade Events

### EXECUTION_ACK

Acknowledges gateway state, not necessarily a fill.

Logical states:

- RECEIVED;
- RESERVED;
- VALIDATED;
- SUBMITTING;
- SUBMITTED;
- REJECTED_PRE_BROKER;
- UNKNOWN.

Fields include order_id, execution_intent_id, state, reason code, broker retcode when already available, and local journal cursor.

### TRADE_EVENT

Authoritative execution lifecycle event.

Logical fields:

- event_cursor;
- order_id when owned by Katarina;
- execution_intent_id;
- broker order ID;
- broker deal ID;
- broker position ticket/identifier;
- event kind;
- order/deal side;
- filled_volume_units;
- fill_price_units;
- commission_units;
- swap_units;
- realized_profit_units;
- broker retcode;
- event reason;
- terminal/execution state.

Ambiguous outcomes are represented explicitly as UNKNOWN and are not mapped to REJECTED.

## 11. Snapshot Bootstrap

Snapshot is transactional:

~~~text
SNAPSHOT_BEGIN
SNAPSHOT_CHUNK × N
SNAPSHOT_COMMIT
~~~

A snapshot may contain typed record batches:

- symbol specs;
- session state;
- account state;
- open positions;
- open/pending orders;
- execution journal/reconciliation summary;
- account ledger watermark when enabled.

Partial snapshots are never installed.

## 12. Health Data

### HEARTBEAT

Low-cost liveness message.

Logical fields:

- process/EA uptime;
- transport state;
- latest produced sequence;
- latest consumed command sequence;
- critical queue depth;
- market queue depth;
- last successful broker observation time.

### HEALTH_EVENT

Logical fields:

- data health state;
- transport health state;
- execution health state;
- reconciliation state;
- journal state;
- clock health;
- queue overflow/degraded flags;
- snapshot state;
- terminal connection/trading flags;
- reason code.

## 13. What Is NOT Sent as MT5 Raw Data

KAT1 MT5 transport does not send:

- EMA/RSI/MACD/Stochastic/Bollinger calculations;
- demand/supply conclusions;
- trend labels created by an EA;
- strategy BUY/SELL opinions from MT5;
- ML features generated by an EA;
- model confidence;
- discretionary risk decisions.

Those are Katarina responsibilities so live, replay and research can share one intelligence path.

## 14. External Data

Economic/news/cross-asset information is not sourced from MT5 KAT1 unless explicitly supplied by MT5 as broker facts.

External intelligence enters Katarina through separate ports/adapters and is joined to immutable decision snapshots with its own freshness/provenance.

## 15. Shared Account and Manual-Trade Learning

Owner-approved direction:

- the account may be shared with manual user trading;
- Katarina has full account visibility for risk/reconciliation/learning;
- observation authority and mutation authority are separate;
- manual trades are read-only by default;
- manual trade facts are captured automatically from MT5;
- actual human reasoning is captured only through explicit user annotation;
- Katarina-inferred reasoning is stored separately and never presented as the user's declared reason;
- manual-trade examples remain a distinct learning population.

Canonical learning contract:

- `docs/architecture/MANUAL_TRADE_LEARNING_CONTRACT_DRAFT.md`
- `protocol/manual_trade_learning_v1_draft.json`

## 16. Remaining Owner Decisions

Four business/operating decisions remain unresolved:

- account-mode certification;
- V1 new-entry order types;
- broker-native protective-stop requirement;
- deposit/withdrawal/credit ledger.

See:

`docs/reviews/STAGE_04_OWNER_DECISIONS.md`

Engineering choices that do not change business behavior continue without requiring owner input.
