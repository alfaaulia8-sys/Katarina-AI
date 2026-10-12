# KATARINA V10 — historical M15/H1 strategy and risk research

**Verified:** 2026-10-12 (Asia/Jakarta). **Production: RESEARCH-ONLY / WAIT.** Data sourced READ-ONLY from MT5 demo broker on VPS; no VPS files changed. Research code at pinned commit [8778c7d](https://github.com/alfaauliau-katarinaAI/Katarina-AI/commit/8778c7d2522b4e26722d162665217abfcf643a7e). GitHub Actions checks compile, causal smoke test, and absence of order path.

## Research design (fixed before results)

- 17 priority broker instruments, M15 and H1 signal clocks; last-closed H1/H4 trend context; no same-bar completed H4 lookahead. Bounded overnight breaks accepted if no data were synthesized. The next bar's open is the modeled entry.
- Five entries: TREND_PULLBACK, BREAKOUT_CONTINUATION, LIQUIDITY_SWEEP, RANGE_FADE, MOMENTUM_EXPANSION, BUY and SELL independently. Separate ATR stop 1.0/1.5, take profit 1.5R/2.2R, maximum hold 32 M15 bars or 12 H1 bars. Model rejects narrow stop distances (below 3 times the recorded entry spread) and large spread-to-ATR signals.
- **TRAIN** 2026-06 and 2026-07; shortlist only when >=20 TRAIN trades, mean R >+0.08 and PF >=1.15 after extra +0.10R assumed costs. **DIAGNOSTIC** 2026-08 and 2026-09, separately, requiring >=20 combined, mean R >+0.05, PF >=1.15; both months need >=8 and positive mean. The historical periods have **already been inspected**: this is chronological replay, NOT independent unseen OOS.
- Broker M15/H1 M5 OHLC BID values with *per-candle historical spread points*, ASK modeled as BID + candle spread; stop-first if bar contains both SL and TP, one tick adverse opening/exit. Commission/fee assumed 0.03R plus 0.10R extra stress. Historical true ASK ticks, real commissions, slip, financing and broker fill quality not verified.

## Verified results

**13,604 observed research entry signals** across 17 assets (can coexist or compete), **1,264 asset/timeframe/method/direction/exit configurations**, **9 TRAIN-only shortlisted**, **0 positive follow-up screens**. **No strategy qualifies for production**. Not independent holdout.

### Spread-to-ATR and research scope (median, read from broker history)

| Broker symbol | M15 candles | H1 candles | M15 spread / ATR | H1 spread / ATR | TRAIN-selected configurations | DIAGNOSTIC passed |
|---|---:|---:|---:|---:|---:|---:|
| EURUSD.vx | 9025 | 2257 | 0.31164 | 0.14258 | 0 | 0 |
| GBPUSD.vx | 9024 | 2257 | 0.29899 | 0.13725 | 0 | 0 |
| USDJPY.vx | 9025 | 2257 | 0.43077 | 0.19316 | 0 | 0 |
| USDCHF.vx | 9024 | 2257 | 0.32886 | 0.14888 | 0 | 0 |
| USDCAD.vx | 9025 | 2257 | 0.42697 | 0.1931 | 3 | 0 |
| AUDUSD.vx | 9025 | 2257 | 0.35379 | 0.16596 | 0 | 0 |
| NZDUSD.vx | 9025 | 2257 | 0.48188 | 0.22344 | 0 | 0 |
| EURGBP.vx | 9025 | 2257 | 0.82099 | 0.4086 | 0 | 0 |
| EURJPY.vx | 9025 | 2257 | 0.39921 | 0.18194 | 1 | 0 |
| GBPJPY.vx | 9025 | 2257 | 0.29678 | 0.14063 | 0 | 0 |
| AUDJPY.vx | 9025 | 2257 | 0.46294 | 0.21201 | 0 | 0 |
| EURAUD.vx | 9025 | 2257 | 0.32696 | 0.15552 | 0 | 0 |
| XAUUSD.vx | 8605 | 2154 | 0.03413 | 0.01661 | 0 | 0 |
| BTCUSD.vx | 12633 | 3169 | 0.17847 | 0.08238 | 0 | 0 |
| XTIUSD.vx | 8596 | 2150 | 0.37634 | 0.20854 | 0 | 0 |
| US30.vx | 8585 | 2147 | 0.05883 | 0.0342 | 1 | 0 |
| NAS100.vx | 8587 | 2149 | 0.06975 | 0.03534 | 4 | 0 |

**Observation:** EURUSD M5 spread/ATR previously measured 0.53699; on the current M15/H1 evaluation, EURUSD median ratios are 0.31164/0.14258. Relative market friction improves with slower bars, but this does **not** prove the direction signal can overcome costs. XAUUSD has low ratio and still no qualifying model; cost is not the only cause of losses.

### Fixed, training-selected configurations

These candidates were shortlisted based on June/July **only**. Every one failed August/September diagnostic evidence. Metrics below are already stressed by additional +0.10R per modeled trade.

| Instrument | Timeframe / method / direction / SL ATR / TP R | TRAIN trades | TRAIN mean R | DIAG trades | DIAG mean R | Approved |
|---|---|---:|---:|---:|---:|---|
| USDCAD.vx | H1/TREND_PULLBACK/BUY/1.0/2.2 | 21 | 0.504284 | 33 | -0.382471 | Tidak |
| USDCAD.vx | H1/TREND_PULLBACK/BUY/1.5/1.5 | 21 | 0.176983 | 27 | -0.172851 | Tidak |
| USDCAD.vx | H1/TREND_PULLBACK/BUY/1.0/1.5 | 26 | 0.139779 | 35 | -0.21904 | Tidak |
| EURJPY.vx | H1/TREND_PULLBACK/SELL/1.5/2.2 | 23 | 0.282791 | 15 | -0.166151 | Tidak |
| US30.vx | M15/LIQUIDITY_SWEEP/SELL/1.0/2.2 | 79 | 0.125718 | 65 | -0.513431 | Tidak |
| NAS100.vx | M15/LIQUIDITY_SWEEP/SELL/1.0/2.2 | 64 | 0.226962 | 44 | -0.418023 | Tidak |
| NAS100.vx | M15/LIQUIDITY_SWEEP/SELL/1.5/1.5 | 58 | 0.180475 | 41 | -0.412035 | Tidak |
| NAS100.vx | M15/LIQUIDITY_SWEEP/SELL/1.0/1.5 | 64 | 0.165966 | 44 | -0.386518 | Tidak |
| NAS100.vx | M15/LIQUIDITY_SWEEP/SELL/1.5/2.2 | 58 | 0.145131 | 41 | -0.457106 | Tidak |

### Simulated portfolio risk policies — NOT deployed

The risk experiment considers training-selected hypothetical signals in the two later calendar months, **chronologically**, enforcing max 1 or 2 concurrent positions, max 8% model drawdown for *new* entries, half risk once model DD >=4%, and conservative overlapping-symbol limits. These are *counterfactual* model accounts, NOT real broker P/L, and executed fills/commissions are not confirmed. DD can slightly exceed 8% when a position closes across the boundary.

| Risk per modeled entry | Max positions | Modeled fills | Diagnostic return | Diagnostic max drawdown | DD stop triggered |
|---|---:|---:|---:|---:|---|
| 0.10% | 1 | 103 | -4.0915% | 4.1428% | Tidak |
| 0.10% | 2 | 130 | -4.6675% | 4.6675% | Tidak |
| 0.25% | 1 | 103 | -7.1036% | 7.2260% | Tidak |
| 0.25% | 2 | 115 | -8.0446% | 8.0446% | Ya |
| 0.50% | 1 | 29 | -8.1869% | 8.1869% | Ya |
| 0.50% | 2 | 22 | -8.1991% | 8.1991% | Ya |

**Conclusion:** Raising the risk or permitting more positions does not rescue negative expectancy. Multiple risk scenarios deteriorate; even the smallest simulated risk loses money. Preserving KATARINA execution and risk governor unchanged is required.

## Reproducibility and scientific limitations

- Raw historical broker candle/tick/account/credential data were **not** committed to GitHub; complete **sanitized per-market aggregated results** are in `docs/research/outputs/20261012/broker_multitf_risk_v10_aggregate_sanitized.json`. No VPS files were written.
- Diagnostic August/September history is chronologically later than TRAIN but it is *previously reviewed*, hence **not an independent test**. The 1,264 variant comparison creates multiple-testing/overfit risk; a lucky TRAIN month is not actionable edge.
- All bars represent BID OHLC only, with per-bar spread-derived approximation of ASK. Stops, gaps, TP, slippage and commissions are **simulated**, not deal reconstructions. Exposure model does not verify contract specifications, swaps or margin.
- Equity returns shown in risk experiments reflect only this selector's hypothetical overlapping-event subset. They must not be presented as actual achievable growth or forecasts.
- No source logic, Brain, broker scan scope, production Risk Governor, live trade gateway, dashboard or VPS filesystem/service was modified.

## Evidence-based next research target

The **loss of previously selected signals on August/September** is more fundamental than lot sizing, stop-loss distance or RR tweaks. Future experiments should focus on detecting regime *breaks* and non-stationarity before committing a strategy. Preserve the currently failed strategies as negative controls, evaluate volatility-adjusted entry and timing filters on truly later untouched data when possible, and reconcile actual broker costs before advancing from WAIT.
