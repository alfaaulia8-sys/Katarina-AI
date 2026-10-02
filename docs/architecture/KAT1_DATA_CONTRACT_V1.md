# KAT1 DATA CONTRACT V1

**Status:** FROZEN  
**Protocol:** KAT1  
**Version:** 1.0.0  
**Stage:** 04/40

## Ownership Boundary

MT5 supplies broker/terminal facts.

Katarina/Python derives intelligence.

MT5 facts include:

- ticks and broker bars;
- account/symbol specifications;
- session/trading permissions;
- account, position and order state;
- deals/execution events;
- non-trading ledger operations;
- terminal/bridge health;
- broker-native profit/margin calculations.

Katarina derives:

- indicators/features;
- MTF structure;
- demand/supply;
- market regime;
- model output/confidence/uncertainty;
- TradeCandidate;
- RiskDecision;
- position sizing;
- learning/evaluation labels.

MT5 does not become a second discretionary trading brain.

## Market Data

### TICK_EVENT

Fixed root: 48 bytes.

Core fields:

- instrument_id;
- spec_revision;
- bid/ask;
- optional last/volume;
- tick flags;
- presence flags.

Hot ticks do not repeat symbol strings.

### BAR_EVENT

Fixed root: 80 bytes.

Core fields:

- instrument/spec revision;
- timeframe;
- bar state/sequence/open time;
- OHLC;
- tick/real volume;
- spread;
- presence flags.

Timeframe support is schema-independent from runtime subscription policy.

## SymbolSpec

SYMBOL_SPEC is the authoritative broker contract snapshot for deterministic risk/preflight.

It covers:

- canonical and broker symbol identity;
- price digits/scale/point/tick size;
- tick values;
- contract size;
- volume min/max/step/limit;
- margin-related values;
- trade/calculation modes;
- allowed order/filling/expiration modes;
- stops/freeze levels;
- swap mode/values/multipliers.

Material economic changes increment `spec_revision`.

## Account State

ACCOUNT_DELTA carries revisioned broker-native account state:

- balance/equity/credit/profit;
- margin/free margin/initial/maintenance;
- leverage;
- margin level;
- margin call/stop-out values;
- margin/account trade modes;
- currency digits;
- trade/expert/hedge/FIFO flags;
- account-unit profile revision.

A complete account state is required in bootstrap snapshot.

## Standard / Cent Compatibility

Account unit handling is native:

- standard and cent accounts share the same schemas;
- no hard-coded standard/cent multiplier;
- ACCOUNT_CURRENCY and ACCOUNT_CURRENCY_DIGITS define account display/native units;
- risk uses current broker symbol economics and broker calculation evidence where requested.

See:

- `docs/architecture/STANDARD_CENT_ACCOUNT_COMPATIBILITY.md`

## Positions

POSITION_DELTA carries:

- ticket and stable POSITION_IDENTIFIER;
- instrument/spec;
- magic;
- position revision;
- open/update times;
- volume/open/current price;
- SL/TP;
- profit/swap;
- change/side/origin/reason;
- presence/raw broker fields.

In netting mode, stable lineage is POSITION_IDENTIFIER rather than ticket alone.

## Orders

ORDER_STATE_EVENT covers current/pending and history-relevant order state:

- broker ticket;
- linked Katarina order ID when applicable;
- instrument/spec/magic;
- revision/times;
- volume;
- open/stop-limit/SL/TP prices;
- expiration;
- side/entry class/origin;
- normalized + raw broker state/reason;
- filling/time-in-force.

Manual and foreign orders are observable even when non-mutable.

## Account Ledger

ACCOUNT_LEDGER_EVENT is mandatory V1.

It records broker-native non-trading balance operations separately from trading P/L while preserving raw DEAL_TYPE and DEAL_REASON.

Normalized classes include deposit, withdrawal, credit, charge, correction, bonus, commission, interest, dividend, tax and other balance operations.

## Execution Intents

All broker-mutating intents are:

- critical;
- CRC-protected;
- idempotent;
- account/instrument/spec bound;
- snapshot/decision/risk lineage bound;
- revision/expiry bound.

V1 entry types:

- MARKET;
- LIMIT;
- STOP.

Exposure-creating entries require native SL.

Pending entries also carry setup validity and netting-state guards.

## Execution Outcomes

EXECUTION_ACK reports gateway progress and is not by itself fill truth.

TRADE_EVENT carries authoritative execution lifecycle evidence.

Ambiguous broker effect becomes UNKNOWN and is never silently reclassified as a fill/rejection.

## Broker Calculation Evidence

BROKER_CALC_REQUEST / BROKER_CALC_REPORT allow Katarina to obtain account-native OrderCalcProfit / OrderCalcMargin evidence for deterministic sizing/preflight.

This is especially useful across different symbol calculation modes and standard/cent account economics.

## Shared-Account Learning

Katarina observes manual trades as a separate origin population.

Automatic broker facts are captured from MT5; actual human reasoning requires explicit user annotation.

Declared user reason and Katarina-inferred reason remain separate.

See:

- `docs/architecture/MANUAL_TRADE_LEARNING_CONTRACT_V1.md`

## Snapshot and Reconciliation

Bootstrap includes complete relevant:

- symbol specs;
- session state;
- account state;
- positions;
- orders;
- execution journal summary;
- account ledger watermark.

Partial state is not installed.

## Exact Layouts

The exact field offsets/root sizes are canonical in:

- `protocol/kat1_message_schemas_v1.json`

Enums/flags/capabilities/reason codes are canonical in:

- `protocol/enums_v1.json`
- `protocol/flags_v1.json`
- `protocol/capabilities_v1.json`
- `protocol/reason_codes_v1.json`

The higher-level payload catalog is:

- `protocol/payload_catalog_v1.json`
