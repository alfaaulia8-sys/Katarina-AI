# Indicator combinations research, 2026-10-10

Status: research implementation and retrospective screening; no validated strategy.
Base: 0c0ffee (latest fetched main). Work performed on VPS in a separate git worktree.

## What was implemented

The research EA 7.132 appends four pre-entry measurements to its feature journal.
Existing entry/execution rules and frozen Constitution remain unchanged.

| Family | Exact hypothesis used by the screen |
| --- | --- |
| Supply/demand | BUY demand distance or SELL supply distance in [0, 0.5] ATR |
| Support/resistance | BUY support or SELL resistance distance in [0, 0.5] ATR |
| ADX | 20 through 35, inclusive; this is a fixed screening range, not an optimized universal threshold |
| Fibonacci | Retracement 0.382 through 0.618 |
| Candle pressure | Existing signed pressure aligned with side, magnitude at least 0.2 |
| ADR | Last completed broker D1 range / average of 20 earlier completed D1 ranges in [0.5, 1.5] |
| Relative volume | Closed signal bar tick volume / mean of preceding 20 bars in [1.2, 10] |
| Chart pattern | Closed-bar breakout of preceding 20-bar consolidation no wider than 4 ATR |
| Candle confirmation | Directionally aligned body engulfing or explicitly defined pin bar |

ADR is NOT ATR and this feature is NOT a forecast of the current day's range.
Volume is broker tick activity, not centralized traded gold volume.
The chart implementation covers one pattern family, not every named pattern.
Existing supply/demand distance does not by itself establish zone freshness.

## Experiment policy

All nonempty conjunctions of available families are enumerated, BUY/SELL separately.
Nine fully available families would permit 511 combinations per side, at fixed
thresholds. This is bounded hypothesis screening, not every possible parameterization.

Final 25% of observations are excluded before selection. Development trades whose
exit label crosses the cutoff are purged. Selection requires 30 retained trades,
at least 10 in each chronological development half, and positive R after an
additional 0.1R-per-trade cost stress in both halves. Final diagnostic pass needs
20 retained final observations and positive stressed R. These are screening
requirements, not evidence of statistical significance.

Identical development trade masks are discarded and the simplest equivalent
candidate is retained. Missing measurements never satisfy a condition. No outcome
or final-window label is a predictor. Tests change final outcomes and verify that
the chosen development candidate does not change. Individual filters can be
removed in development ablation diagnostics, without optimizing on final outcomes.

No production indicator is deleted based on these small samples. Duplicate
candidate evaluations are removed from the search; complete trial evidence is
retained for audit. Further retirement requires execution-aware out-of-sample
evidence, dependency checks and regression testing.

## Executed results

Inputs are the existing reconciled real-tick MT5 journals. They were previously
inspected; they are NOT fresh prospective holdouts. August and September are
reported separately and overlapping reruns are not pooled.

| Journal | Trades | Baseline net USD | Nominal BUY/SELL combinations | Unique BUY/SELL masks | Eligible candidates |
| --- | ---: | ---: | --- | --- | ---: |
| August 2026 | 128 | -118.80 | 31 / 31 | 12 / 10 | 0 |
| September 2026 | 136 | -46.52 | 31 / 31 | 10 / 8 | 0 |

Total: 124 nominal side/month evaluations, 40 distinct within-side/month masks,
84 duplicate evaluations removed. Neither month selects a candidate. This does
not prove all these indicators are ineffective: minimum-sample and consistency
requirements are not met.

Older journals lack the four new telemetry columns. They are explicitly marked
missing rather than imputed, so ADR, relative volume, chart pattern and explicit
candle pattern have NOT undergone market-performance validation.

Reports:
- ../validation/2026-10-10-august-combinations.json
- ../validation/2026-10-10-september-combinations.json

R metrics normalize each trade by initial cash risk. Profit factor in the new
report is R-normalized, not the MT5 cash profit factor. Drawdown is closed-trade R,
not intratrade equity drawdown. Journal net USD is separately labeled.
Fixed-journal filtering cannot reproduce changed position availability, additional
signals, execution costs, partial closures or new entry/exit paths. A newly
executed tester run of each selected strategy remains mandatory.

## Validation and remaining work

26 Python research tests passed (including 10 new combination tests).
The isolated build compiled all 18 MQL targets with zero errors and warnings;
the research EA is included. Compile success is not runtime or strategy validation.
Build evidence on VPS:
C:\KatarinaDev\artifacts\mt5\indicator-build\d41dd43b3dba435389c0e7326e0127d0\build-evidence.json

No terminal restart, running-account modification, or live promotion was performed.
The earlier instruction to leave MT5 unchanged is preserved. To complete the
remaining market tests, use an authorized isolated research terminal to produce
new journals, reconcile them with their tester reports, freeze a candidate on
development history, then run fresh execution-aware validation and forward demo.

Example (PowerShell; run from repo, supply reconciled report totals):
```powershell
$env:PYTHONPATH = "$PWD\src"
python -m katarina.research.indicator_combinations --journal JOURNAL.csv --expected-trades 136 --expected-net=-46.52 --output result.json
```

## Reviewed references and integration decisions

1. https://github.com/joshyattridge/smart-money-concepts
   Structure, order-block and liquidity reference. Swing implementation uses bars
   before AND after the pivot; pivot information cannot be available until right
   confirmation bars close. Not imported into production. Check current license
   and source revision before reusing external code.
2. https://ta-lib.org/functions/
   ADX and candlestick recognition inventory. Pattern output is a feature, not a
   calibrated profit probability. No new binary dependency installed.
3. https://www.mql5.com/en/docs/indicators/iadx
   Native indicator handles and ADX buffers.
4. https://www.mql5.com/en/docs/indicators/ivolumes
   Explicit applied-volume type; distinguish real volume and tick volume.
5. https://www.metatrader5.com/en/terminal/help/indicators/volume_indicators/volumes
   Forex volume represents price-change activity.
6. https://www.mql5.com/en/docs/runtime/testing
   MT5 tester behavior, real ticks and optimization context.
7. https://www.metatrader5.com/en/automated-trading/strategy-tester
   Forward validation and optimization separation.

These references inform definitions and research controls; none proves that a
particular indicator combination is profitable. New MQL code is an original,
small implementation with explicit closed-bar inputs.
