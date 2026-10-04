# Katarina Data Validation Engine — Draft

**Stage:** 08/40  
**Status:** IMPLEMENTATION ACTIVE  
**Frozen inputs:** KAT1 v1.0.0, Stage-06 Bridge v1.0.0, Stage-07 Communication v1.0.0

## Purpose

Stage 08 validates decoded data before analytical consumers rely on it.

It answers:

> Is this data structurally and semantically safe enough to enter Katarina analysis?

It does not decide BUY/SELL, calculate lots, arm execution, submit orders, or replace the Risk Governor.

## Initial dispositions

- **ACCEPT** — active rules found no error/critical issue.
- **QUARANTINE** — data is incomplete/questionable and must not become authoritative analytical state.
- **REJECT** — a critical invariant failed; the event cannot create new live risk.

## Initial baseline

- external timestamp presence;
- stale-data rejection;
- future-clock-skew rejection;
- recursive NaN/Infinity rejection;
- tick symbol/bid/ask validation;
- crossed/non-positive market rejection;
- OHLC structural validation;
- pluggable topic rules;
- validator exceptions fail closed.

## Boundary

Stage 08 does not own:

- KAT1 framing, CRC or transport sequence — Stage 04/07;
- transport/system health policy — Stage 09;
- persistence — Stage 10;
- market interpretation — Stage 11+;
- capital-risk authority — Stage 16;
- broker execution — Stage 18.

## Next gates

1. freeze validation issue taxonomy;
2. bind validation before state-cache promotion;
3. add SymbolSpec-aware constraints;
4. add history completeness rules;
5. add data-class-specific freshness budgets;
6. expose validation state to readiness without arming execution;
7. add property/fuzz tests;
8. build evidence-bound Stage-08 final audit.
