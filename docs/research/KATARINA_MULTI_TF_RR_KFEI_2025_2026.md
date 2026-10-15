> Historical report: Management/specialist code and workflows described below were removed by Owner on 2026-10-15. Current architecture is one unified research brain; this report is not an execution instruction.

# KATARINA AI — Multi-Timeframe and Risk:Reward Study, 2025–2026

**Study date:** 2026-10-11. **Research-only, live disabled.**
**Broker source:** ValetaxIntl-Live2 MT5 data. Fixed existing Risk Governor, compounding, and trading governance remain unchanged.

## Question
Can KATARINA select profitable entry regimes / chart timeframes and Stop:Target risk ratios from 1:1 to 1:10? Is the custom Flow Efficiency Index (KFEI) useful as a price-action context predictor?

## Data coverage and engine conditions
- Period: January 1, 2025 – October 9, 2026 UTC, where the broker actually has the selected symbol's quote history. Other symbols begin around April–June 2025. Do NOT claim uniform Jan-2025 full price coverage for all symbols.
- A chart API scan of all **21 standard MT5 timeframes** was run (M1 M2 M3 M4 M5 M6 M10 M12 M15 M20 M30 H1 H2 H3 H4 H6 H8 H12 D1 W1 MN1); 21 is the official enum count, not a measured optimal count.
- Main chart-entry screen used 9 timeframes: M5/M6/M10/M12/M15/M20/M30/H1/H2. H3/H4/H6/H8/H12/D1/W1/MN1 are intended as longer trend/context views rather than fast scalp entry charts. The M1/M2 native MT5 chart cache was truncated by a 100,000-bar max and contains no 2025 candle history, so it was NOT claimed to be a complete two-year M1 backtest.
- XAUUSD 2025–2026 was reconstructed from **115,566,653 cached true Bid/Ask ticks** into **627,193 M1 OHLC Bid candles**, which makes a separate M1–M4 study feasible. Tick-derived bars are NOT the same as a complete intratick SL/TP path simulator. The M1–M4 strategy research applies a shorter 60-minute maximum hold and is reported separately.
- The same 2026 historical periods have been inspected multiple times in KATARINA research. Treat 2026 as an exploratory chronological diagnostic, NOT a pristine out-of-sample holdout.
- Entry occurs at the next chart bar's open, with historical bar spread + one tick of adverse slippage assumed for each side + **hypothetical** fee of 0.03R. Actual commission/fill/swap history is not integrated; if a single bar spans SL and TP, SL is assumed hit first. Broker trade cash P&L, leverage, margin/liquidation and correlation portfolio risk are not simulated.
- A positive expectancy after many optimization trials must not be promoted without stable cross-regime, broker-realistic, independently reserved evidence.

## Experiment A — V2 baseline exits (no change to signal timestamps)
- 7 instruments × 4 ATR stops (.75,1,1.25,1.75) × 7 RR targets (1,1.5,2,3,5,7,10) × 3 maximum holds (12/24/48 M5 bars).
- A total **1,764 scenario cells** were screened (7 × 252). Candidate signals came from earlier V2 results that had already been filtered through their own position lockout; therefore this is CONDITIONAL exit research and not a fully independent replay for every candidate.
- One 2025 developmental pass: NAS100 RANGE_FADE, SL=1.25 ATR, TP:SL=10:1, hold up to 120 min. **2025:** 580 trades, +0.100355 R/trade, PF 1.1423. **2026:** 937 trades, -0.185187 R/trade, PF 0.7513. Therefore REJECT.
- All other instruments had zero 2025 configurations passing the declared positive-expectancy/development thresholds.

## Experiment B — custom KFEI + regime and timeframe
- KFEI (KATARINA Flow Efficiency Index):
  score = sign(C0 - C12) × ER(12) × clip(abs(C0-C12)/ATR(14),0,3) × clip(ATR(14)/median(previous 50 ATR),0,2),
  where ER(12) = abs(C0-C12) / sum(abs(Ck-Ck-1)) over 12 transitions.
- Broker spread-to-ATR is reported separately as friction, never conflated with a profitability forecast.
- Four closed-price action families: DRIVE_CONTINUATION, SWEEP_REVERSAL, RANGE_REJECTION and CLOSED_BREAK. The score's meaning is strength of directional price persistence, **not win-rate**.
- 7 instruments × 9 entry timeframes × 4 families × 3 ATR stops (0.8,1.2,1.6) × 7 RR targets = **5,292 tested configurations**.
- The 2025 developmental gate was >=70 simulated trades, >=5 active months, mean expectancy >=+0.08R and PF>=1.15. Only **6 configurations** passed, all from US30 H2 (intraday rather than scalping).
- The best 2025 candidate: US30 H2 CLOSED_BREAK, stop=0.8 ATR, target 5R, hold 240 min: 159 trades +0.18522R, PF1.431 (2025). Chronological 2026: 134 trades -0.18251R, PF0.674. Therefore REJECT. **No candidate** from this screen passed positive 2025 and positive 2026 together under the sample gate.
- The H2 timeframe included a 4-hour maximum hold due to a floor of two bars in the first experiment; that is longer than the nominal 180-minute scalp horizon and is explicitly flagged as NON-SCALP. New script default is corrected to avoid this floor in future runs.
- None of these results authorizes any live trading or justifies choosing a single universal RR.
- Timeframe availability and samples stored as structured JSON under artifacts/historical-brain.

## Experiment C — direction propensity without simulated cash trades
- Frozen KFEI DRIVE_CONTINUATION signals tested on the NEXT candle close sign, sampled at least every 3 signals to reduce some overlap. Direction hit % is not an expected profitable trade win rate.
- XAUUSD M5: 6,361 cases / **49.458%** in 2025; 4,972 cases / **48.250%** in 2026.
- NAS100 M5: 4,074 cases / **50.025%** in 2025; 5,056 cases / **50.218%** in 2026.
- EURUSD M5: 3,829 cases / **50.431%** in 2025; 5,214 cases / **48.504%** in 2026.
- These near-50% rates provide no evidence of a reliable directional edge; KFEI should remain an optional market-condition diagnostic, not a forced execution trigger.

## Experiment D — true-tick-derived M1–M4 XAUUSD micro-scalping
- 115,566,653 broker Bid/Ask ticks from 2025–2026 were aggregated into 627,193 observed M1 OHLC records; no synthetic intermediate prices. M2, M3 and M4 require all constituent M1 bars and skip gaps.
- Separate XAU-only short-scalp research screen: M1/M2/M3/M4, the four candidate playbooks, 3 ATR SL distances (0.8/1.2/1.6), and 7 RR targets (1/1.5/2/3/5/7/10), with **60-minute max hold**. **336 tested combinations; zero passed the 2025 development gate**.
- Best available 2025 training scores by micro timeframe (none has positive expectancy): M1 SWEEP_REVERSAL SL1.6 ATR RR10, 9,041 trades -0.17467R; 2026 6,835 trades -0.08056R. M2 DRIVE_CONTINUATION SL1.6 RR7, 7,243 trades -0.12472R; 2026 5,481 trades -0.04386R. M3 RANGE_REJECTION SL1.6 RR3, 2,521 trades -0.09635R; 2026 1,973 trades -0.06076R. M4 RANGE_REJECTION SL1.6 RR2, 1,878 trades -0.08295R; 2026 1,486 trades -0.07051R.
- These are tick-derived candles, not a tick-sequenced stop/TP/fill simulation; the lack of benefits under this approximate cost model is sufficient reason not to promote.
- Combined research screens 1,764 + 5,292 + 336 = **7,392 parameter configurations**, NOT independent strategies. Broad search increases false-discovery and overfitting risk.

## Research conclusion (after reconstructed M1–M4 run)
- More timeframes and larger TP targets did not rescue low-quality triggers in this historical simulation.
- Use H1/H4/D1 for directional macro context, M5/M15 for development of scalper execution, and M1–M4 only with genuine 2025 historical tick reconstruction and measured broker transaction costs.
- Do not force one RR across all symbols or regimes. A high RR such as 1:10 is acceptable only after credible net-expectancy and repeatability evidence. No current RR is validated as globally optimal.
- KFEI might help prioritize trend/sideways/volatility regimes but must not be treated as an AI predictor by itself; next priorities are price structure, liquidity sweep, failed break, session and event-state controls.
- All changes are confined to research scripts/indicator plus reports, and DO NOT modify Risk Governor or activate live execution.

## Sources
1. Official MT5 timeframe enum: https://www.mql5.com/en/docs/constants/chartconstants/enum_timeframes
2. MetaQuotes real ticks and Bid/Ask execution: https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation
3. MetaQuotes Strategy Tester mode limitations: https://www.metatrader5.com/en/terminal/help/algotrading/testing
4. Bailey, Borwein, Lopez de Prado, Zhu, Probability of Backtest Overfitting (2015/2017): https://escholarship.org/uc/item/4w1110bb
5. Realized range and market microstructure friction (Journal of Econometrics 2007): https://www.sciencedirect.com/science/article/abs/pii/S0304407606000923

## VPS results
- artifacts/historical-brain/katarina_rr_grid_from_2025_2026.json
- artifacts/historical-brain/katarina_kfei_tf_rr_2025_2026.json
- artifacts/historical-brain/mt5_native_21_timeframes_2025_2026.json
- artifacts/historical-brain/katarina_kfei_direction_by_timeframe.json
- artifacts/historical-brain/xauusd_m1_tick_2025_2026_audit.json
- scripts/research/rr_grid_from_2025.py
- scripts/research/kfei_native_tf_2025.py
- scripts/research/kfei_direction_diagnostic_2025.py
- scripts/research/reconstruct_xau_m1_2025_2026.py
- src/katarina/intelligence/flow_efficiency_index.py
- tests/unit/intelligence/test_flow_efficiency_index.py

No parameter change on live software; stage-gated execution is unchanged.
