# Stage 36 — GitHub Prior-Art Reference

Status: SEARCHED / REVIEW INPUT  
Stage: Paper / Demo Trading

## Selected references

1. Freqtrade dry-run wallet implementation:
   https://github.com/freqtrade/freqtrade/blob/338e264643c113642a69e44094870ccb0d84bdb8/freqtrade/util/dry_run_wallet.py

2. Freqtrade trading command/config documentation at the same pinned revision.

## Patterns adopted

- paper/dry-run capital is logically separate from live venue state;
- simulation has its own deterministic local ledger;
- duplicate local paper order identifiers are refused;
- paper fills may model positions but never mutate a broker;
- paper/demo validation must precede any later live micro-risk gate.

## KATARINA adaptation rule

- Stage 36 is simulation-only during body build.
- No credentials or live venue adapter are required.
- `broker_mutation_enabled` is hard false.
- Strategy/risk policies remain user-owned and pending.
- Windows MT5 demo proof is still required before Stage 36 can be promoted beyond local body status.

## Body-build result

`BODY_FRAMEWORK_COMPLETE / PAPER_LEDGER_READY / WINDOWS_DEMO_PENDING`
