# Multi-Symbol Execution Orchestrator V1

KATARINA can admit multiple high-quality opportunities from different broker symbols in the same decision cycle.

## Admission order

Candidates are processed by opportunity score, highest first.

For every candidate:
1. shared-account Risk Governor evaluates the latest committed risk;
2. approved risk is reserved atomically before the next symbol is considered;
3. correlation-adjusted portfolio exposure is checked;
4. volume is reduced proportionally if the Risk Governor reduces risk;
5. broker minimum/step is respected;
6. execution preflight runs;
7. an idempotent symbol-specific ExecutionIntent is created.

This makes concurrent allocation deterministic. Example with an empty account:
- first candidate requests 5% -> may reserve 5%;
- second requests 5% -> at most 3% remains under the 8% committed-risk cap;
- later candidates receive no capacity unless earlier risk is released or reduced.

## Correlation

The gross 8% cap is not the only gate. Positively correlated symbols add a correlation penalty. Highly correlated candidates can therefore be rejected even while nominal gross risk appears below 8%.

## Frozen KAT1 compatibility

KAT1 OPEN_INTENT already contains `instrument_id` and `spec_revision`. The new command encoder binds every execution to those frozen fields, so EURUSD, XAUUSD, BTCUSD, USOIL, etc. remain distinct at wire level.

## MT5 bridge boundary

The frozen Stage-06 bridge remains chart-symbol-only for realtime execution approval. This implementation does not silently weaken that invariant.

Therefore the Python multi-symbol orchestration and KAT1 command binding are complete at software level, while actual broker mutation across multiple symbols requires a governed MT5 bridge extension with explicit multi-symbol tick/spec/session sourcing and new compile/runtime proof. Until that extension is validated, live multi-symbol execution must remain fail-closed.
