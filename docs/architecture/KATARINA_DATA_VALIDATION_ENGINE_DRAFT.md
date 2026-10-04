# Katarina Data Validation Engine — Draft

**Stage:** 08/40  
**Status:** IMPLEMENTATION ACTIVE  
**Version:** 0.2.0  
**Frozen inputs:** KAT1 v1.0.0, Stage-06 Bridge v1.0.0, Stage-07 Communication v1.0.0

## Authority boundary

Stage 08 validates decoded data before it can be promoted into authoritative analytical state.

It may classify data as:

- `ACCEPT`
- `QUARANTINE`
- `REJECT`

It may set only the Core `DATA_FRESH` readiness signal through its readiness tracker. It cannot set `HEALTH`, `RISK`, `EXECUTION_ARMED`, create trade candidates, size positions, or submit broker orders.

## Canonical input

Market validation is now aligned to the frozen KAT1 field names:

- `symbol.spec` → SYMBOL_SPEC facts;
- `market.tick` → `instrument_id`, `spec_revision`, `bid_units`, `ask_units`, etc.;
- `market.bar` → KAT1 BAR_EVENT fields including timeframe, sequence, open time and OHLC units.

Stage 08 does not invent an alternate symbol/price schema.

## SymbolSpec binding

An accepted SymbolSpec becomes the active validation contract for its `instrument_id`.

Market data fails closed when:

- no accepted spec exists;
- its `spec_revision` differs from the active revision;
- a SymbolSpec revision rolls backward;
- required economic scaling values are invalid;
- prices are off the broker tick grid.

## Freshness

Freshness is policy-driven per data class.

Initial budgets:

- tick: 2 seconds;
- bar event delivery: 10 seconds;
- account/position/order state: 5 seconds;
- SymbolSpec: 1 hour.

These are data-ingest freshness budgets, not trading strategy timeframes.

## History completeness

A history requirement binds:

- instrument;
- SymbolSpec revision;
- timeframe;
- minimum bar count.

History is incomplete/fail-closed when bar count is short, topic/instrument/spec/timeframe differs, bar sequence has gaps, or open times do not strictly increase.

Weekend/session time gaps are not rejected solely by wall-clock spacing; authoritative `bar_sequence` continuity is used instead.

## Promotion gate

`ValidatedIngestGate` returns a promoted event only for `ACCEPT`. QUARANTINE/REJECT data cannot silently enter downstream state/cache paths.

## Readiness integration

`ValidationReadinessTracker` can set only `ReadinessSignal.DATA_FRESH`.

Even when DATA_FRESH is true, Core live execution remains false until later governed HEALTH, RISK and EXECUTION_ARMED gates are independently satisfied.

## Next gates

1. property/randomized invariant tests;
2. account/position/order semantic validation;
3. static authority audit;
4. evidence-bound Stage-08 final clearance;
5. freeze v1.0.0 only after all gates pass.
