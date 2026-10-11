# KATARINA Brain V2 — Retrospective Historical Test Since 2025

**Completed:** 2026-10-11 (Asia/Jakarta)  
**Period requested:** 2025-01-01 onward; latest available closed history 2026-10-09 UTC  
**Mode:** research/shadow, absolutely no broker orders.  
**Scope:** Seven Valetax broker symbols; actual year-start depends on each symbol's available history.  
**Decision:** NO MODEL PROMOTION / NO LIVE EXECUTION.

## Source integrity

- XAUUSD.vx has historical broker tick files for **all 12 months 2025**, plus original M5. Jan-Apr 2025 M5 history was truncated by MT5 max-chart-bars, so 19,473,541 broker ticks were reconstructed into 23,044 complete 5-minute OHLC candles. Missing weekdays were 2025-01-01 and 2025-04-18 (market holidays); no artificial candle prices were inserted.
- Jan-Apr was **tick-derived M5**, not a full tick-order simulator. May 2025 to October 2026 uses MT5 M5 OHLC and archived bar spread; many other symbols lacked broker 2025 raw tick archives.
- MT5 API cannot return this entire 2025–2026 interval in a single request on this VPS; the experiment retrieves one calendar month at a time.
- All entry decisions depend on completed M5/M15/H1 data and strictly prior channel highs/lows; trades open at next M5 bar open. Same-bar SL and TP conflict conservatively resolves to SL, but intra-bar order of events is not actually known.
- Historical spread is used where present, slippage stresses 1 price tick in each direction, plus **assumed** commission cost of 0.03R per trade. Actual broker commission, swaps, slippage during news and full bid/ask path have **not** been verified, so estimates are not executable net P&L.
- Proposals were checked every third M5 bar (approximately every 15 minutes). Strategy families: TREND_PULLBACK (TP=1.5R), RANGE_FADE (TP=1.0R), BREAKOUT_RETEST (TP=1.5R), REVERSAL_RECLAIM (TP=1.3R), with predeclared ATR stops and maximum holding bars. No settings were changed to improve reported returns.

## Historical results

| Symbol | First available | 2025 trades | Mean R 2025 | PF 2025 | 2026 trades (through Oct 9) | Mean R 2026 | PF 2026 |
|---|---|---:|---:|---:|---:|---:|---:|
| XAUUSD.vx | 2025-01-02 | 4,158 | -0.13454 | 0.7715 | 3,344 | -0.07762 | 0.8611 |
| NAS100.vx | 2025-05-08 | 2,408 | -0.24678 | 0.6164 | 3,361 | -0.16773 | 0.7242 |
| US30.vx | 2025-05-14 | 2,844 | -0.18204 | 0.7036 | 3,362 | -0.18155 | 0.7036 |
| JPN225.vx | 2025-04-03 | 2,769 | -0.22590 | 0.6430 | 3,096 | -0.11432 | 0.7995 |
| EURUSD.vx | 2025-06-02 | 1,761 | -0.37892 | 0.4760 | 1,689 | -0.37035 | 0.4821 |
| GBPUSD.vx | 2025-06-06 | 1,501 | -0.38941 | 0.4594 | 1,890 | -0.38115 | 0.4705 |
| USDJPY.vx | 2025-06-06 | 1,846 | -0.35894 | 0.4914 | 1,268 | -0.37011 | 0.4778 |
| **Total** | different starts | **17,287** | **-0.24361 weighted** | — | **18,010** | **-0.20004 weighted** | — |

The 35,297 trades are a *simulation*, not execution by MT5 Strategy Tester using broker real-tick mode for every order. Summed R is not an account-balance return because position size, compounding, total overlapping portfolio exposure and real broker conditions were not simulated.

## Per-strategy diagnostics

For XAUUSD.vx, 2025 TREND_PULLBACK 2,045 trades mean -0.10569R; RANGE_FADE 1,578 trades -0.16729R; BREAKOUT_RETEST 528 trades -0.14087R. In 2026 these were respectively 1,617 trades -0.08203R, 1,304 trades -0.08427R and 420 trades -0.04415R.

Across all seven instruments, **none of the three major playbook families achieved a positive annual expectancy in both 2025 and 2026**. Some tiny reversal samples have positive averages (e.g. 3 to 7 signals) but cannot establish an edge.

## Seasonality diagnostic

Four predeclared six-hour UTC sessions (00–06, 06–12, 12–18, 18–24) were evaluated by instrument and major playbook. There are **67 cells** with >=50 trades in both 2025 and 2026. **0/67 were profitable in both years**. These are fixed UTC buckets and have not yet been adjusted for exchange daylight savings; no seasonal filter was promoted.

## Decision and next experimental priority

- The flexible-entry research code does find plenty of setups but at present has negative cost-adjusted *assumed* expectancy; **do not deploy as a live trading model**.
- Analyze separately whether market direction, trade trigger, and exit geometry is responsible; improve specialist pair-specific logic on *2025 only*, and hold 2026 constant for chronological checks. Because the 2026 results have now been inspected, future claims of clean independent holdout must use a new reserved dataset.
- Before real trading, perform independent MT5 Strategy Tester runs with broker **Every tick based on real ticks**, actual commission/swap fees, and ensure Stage 36/38 evidence. Existing Risk Governor **unchanged**, no enforced extra forward-demo research phase.

## Files on VPS

- Detailed per-trade results: C:\KatarinaDev\artifacts\historical-brain\backtest_adaptive_brain_v2_from_2025.json
- Compact scorecards: C:\KatarinaDev\artifacts\historical-brain\backtest_adaptive_brain_v2_from_2025_summary.json
- Integrity: C:\KatarinaDev\artifacts\historical-brain\backtest_2025_2026_integrity_audit.json
- Seasonal diagnostics: C:\KatarinaDev\artifacts\historical-brain\backtest_2025_2026_sessionality_audit.json
- Tick reconstruction audit: C:\KatarinaDev\artifacts\historical-brain\xau_reconstruction_2025_audit.json
- Detailed results SHA-256: 51be34fcef530b307dc56ed08be187637f05f0514eabb0a406a34610ca080863

## Official methods

- MetaQuotes Python copy_rates_range and its Max bars in chart limitation: https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesrange_py
- MetaQuotes real ticks and Bid/Ask testing behavior: https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation
- Real-tick Strategy Tester and risk of OHLC proxies: https://www.metatrader5.com/en/terminal/help/algotrading/testing
