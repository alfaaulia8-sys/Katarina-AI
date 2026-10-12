# Native KATARINA Brain — actual BID/ASK tick reconciliation (2026-10-12)

## Implemented, without parallel brain or observer

- The existing `MarketDecisionBrain.evaluate` produces chronological M5/M15/H1 technical hypotheses.
- `causal_market_replay.py` NOW saves `all_technical_proposals` BEFORE inspecting future OHLC. This fixes possible selection bias from sampling only previously labeled opportunities.
- `causal_tick_reconciliation.py` checks that the next raw M5 broker BID OHLC exactly matches the first five minutes of tick BID prices, then simulates frozen BUY with entry ASK/exit BID and SELL with entry BID/exit ASK.
- The tick simulator fails closed for missing/out-of-order quotes, bid/ask inversion, entry spread greater than 30% of nominal stop distance, time gaps greater than 180 seconds, incomplete exit, unverified broker M5 timestamp or raw MT5 payload size above 250,000 ticks per candidate.
- The maximum horizon is 2 hours, SL outranks TP on actual quote order, favorable target is capped to the target price and an adverse stop gap gets the WORSE observed quote.
- The one-time VPS reader `scripts/research/run_native_brain_tick_reconciliation.py` selects a maximum of 10 candidates per symbol, evenly spaced by SIGNAL CLOCK before examining their future tick outcomes. A maximum of 5 symbols and 24 per-symbol paths prevents high VPS memory pressure. It does NOT schedule another task.
- `summarize_tick_reconciliation` publishes all failures, strategy/side group, monthly and monthly-symbol-method scorecards; it never turns the retrospective results into forward `ResolvedExperience` or live permissions.

## Actually checked: 5 real broker instruments, 12 October 2026

Symbols: XAUUSD.vx, EURUSD.vx, NAS100.vx, GBPUSD.vx, USDJPY.vx.

| Metric | Result |
|---|---:|
| Past-only native technical proposals BEFORE future prices | 228 |
| Earlier OHLC proxy labels in the same rerun | 193 |
| Tick-audited proposals (10/symbol, time-spread selection) | 50 |
| M5-aligned completed BID/ASK quote paths | 31 |
| Spread too wide (>30% stop distance) | 16 |
| Missing quote continuity | 2 |
| Incomplete tick exit history | 1 |
| 31 valid: average R, with extra assumed 0.15R cost | **-0.166634R** |
| 31 valid: PF based on assumed extra cost | **0.63424** |
| Winners / losers among completed samples | 13 / 18 |
| Exit reasons among completed samples: SL / TIME / TP | 10 / 19 / 2 |
| Unique month | **2026-10 only** |
| Broker orders | **0** |

One-shot tick verification found the broker current-clock displacement around +3h; raw tick prices matched their M5 BID OHLC reference on each **successful** path. This is not a full historical daylight-saving transition audit. Raw tick and M5 clock domains MUST be re-validated on other dates before making cross-month performance claims.

### Honest strategy diagnostics

| Method and side | Sampled | Tick completed | Mean modeled net R | PF modeled |
|---|---:|---:|---:|---:|
| RANGE_FADE BUY | 4 | 3 | -0.680056 | 0.11644 |
| RANGE_FADE SELL | 18 | 7 | -0.307256 | 0.54648 |
| TREND_PULLBACK BUY | 5 | 5 | -0.027667 | 0.89649 |
| TREND_PULLBACK SELL | 12 | 8 | +0.076698 | 1.22163 |
| BREAKOUT_RETEST BUY | 3 | 3 | -0.505445 | 0.0 |
| BREAKOUT_RETEST SELL | 6 | 4 | +0.304220 | 5.05566 |
| REVERSAL_RECLAIM SELL | 2 | 1 | -1.150501 | 0.0 |

RANGE_FADE requires special scrutiny: SELL had 11 of 18 unavailable/nontradable paths, many due to spread exceeding the stop-cost threshold, and 4 SL among 7 completed cases. BUY also had a negative mean but only three completed cases. The seemingly promising BREAKOUT_RETEST SELL has **only FOUR** completed tick paths and thus is NOT established alpha. No configurations were promoted from this retrospective subset.

## Validation references

- MetaQuotes MQL5 `copy_ticks_range`: use timezone-aware UTC request and `COPY_TICKS_INFO`, and recognize that the return type is a NumPy structured array. https://www.mql5.com/en/docs/python_metatrader5/mt5copyticksrange_py
- MetaQuotes MQL5 `order_calc_profit`: calculator provides hypothetical broker-currency P&L, not evidence of future actual deal commissions, fills or slippage. https://www.mql5.com/en/docs/python_metatrader5/mt5ordercalcprofit_py
- Chronological purging plus embargo protects labeled intervals against overlap. https://ppuertos.github.io/financial-ml-core/reference/model_selection/split/

GitHub Body CI SUCCESS for code source SHA `c75dd8e23ab7a2ab8c5156348124fc27f8c64ba5`: https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38274053823 . Unit tests explicitly cover future-OHLC exclusion, prior-unlabeled signal retention, real NumPy tick arrays, ASK/BID bidirectional pricing, false M5 clock alignment, incomplete tick paths, invalid spread/quote and outcome-denominator preservation.

## Privacy, risk and operational isolation

All detailed tick reconciliation results and their method/month tables remain private on the VPS at:
`C:\KatarinaDev\artifacts\contextual-observer\native-brain-tick-reconciliation-private.json`.

The existing 5-minute `Katarina-MarketBrain-Observer` was temporarily paused only for bounded read-only broker research and restored with `Start-ScheduledTask` in a `finally` block. No duplicate observer, GitHub cron, trade adapter, actual account trade, risk governor override or speculative live signal was introduced.

Read-only broker deal-history sampling found one deal record with no trade symbol in the inspected year, so no actual executed commission-per-symbol could be derived. The extra 0.15R is an ASSUMPTION, not a broker-calibrated fee. Account deposit currency alone cannot prove a full historical fee schedule. Broker commissions, fills, swaps and actual slippage remain UNVERIFIED.

## Conclusions and next controlled engineering decision

Engineering: historical native-brain signals and actual broker bid/ask quote-path reconciliation WORK. The initial tracked method set has broadly negative results after modeled friction; range fading is especially weak in this small history. Research verdict: WAIT; retain full sampled outcome diagnostics and continue independent paper-forward collection. Do not optimize and re-test on the same narrow 2026-10 interval and claim the next apparent winner is independent proof. Do not activate live trading.
