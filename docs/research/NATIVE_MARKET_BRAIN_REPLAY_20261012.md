# KATARINA native Market Brain replay — 12 October 2026

## Actual implementation and evidence

Reuses the EXISTING MarketDecisionBrain.evaluate with strictly closed historical M5/M15/H1 candles. The historical outcome-delayed adaptive memory comes from EXISTING adaptive_walkforward.replay_walk_forward. No new live strategy selector or parallel VPS observer was created.

Code:
- src/katarina/intelligence/causal_market_replay.py
- src/katarina/intelligence/replay_cost_diagnostics.py
- scripts/research/run_native_brain_causal_broker_replay.py
- tests/unit/intelligence/test_causal_market_replay.py
- tests/unit/intelligence/test_replay_cost_diagnostics.py

GitHub Body CI PASS: https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38265389941

## Read-only broker replay, 5 symbols, 12 October 2026

Broker symbols: XAUUSD.vx, EURUSD.vx, NAS100.vx, GBPUSD.vx and USDJPY.vx. Historical M5 bars: approximately Oct 5–12, 2026 (period previously inspected; NOT fresh independent OOS).

| Metric | Verified replay result |
|---|---:|
| Past-only native Brain decisions evaluated | 2,926 |
| Hypothetical technical candidates with OHLC proxy labels | 194 |
| RANGE_FADE | 96 |
| TREND_PULLBACK | 65 |
| BREAKOUT_RETEST | 29 |
| REVERSAL_RECLAIM | 4 |
| Chronological purged train / validation / test | 109 / 40 / 39 |
| Excluded by purging / embargo | 6 |
| Adaptive research selected | 1 |
| Adaptive research WAIT | 193 |
| Selected virtual result | -0.371R assumed model |
| Real MT5 orders | 0 |

Cost-stress diagnostics for all 194 candidates use predeclared extra 0.05R / 0.15R / 0.30R and include losses and purged cases, not post-hoc winning cherry-picks. Actual broker historical bid/ask spread, true tick path, historical news availability, DST alignment, commission, fills and slippage remain unverified. The conclusions describe engineering behavior and synthetic price-path assumptions, NOT actual market P&L.

Full broker aggregate and cost-grid result remains private on VPS:
C:\KatarinaDev\artifacts\contextual-observer\native-market-brain-replay-private.json

## Reference-based research safeguards

1. Lopez de Prado, Advances in Financial Machine Learning, Chapter 7: use purging and an embargo to reduce cross-window overlapping-label leakage. https://random-docs.readthedocs.io/en/latest/implementations/cross_validation.html
2. Bailey, Borwein, Lopez de Prado & Zhu, Probability of Backtest Overfitting: repeated historical optimization can select apparent but unstable alpha. https://escholarship.org/uc/item/4w1110bb
3. VectorBT PRO documentation, Fees, Slippage and Leverage: report cost sensitivity rather than pre-cost model gains. https://vectorbt.pro/features/backtesting/fees-slippage-and-leverage/

## Protected VPS cleanup

Closed ONLY dedicated headless QA Chrome named katarina-web-qa-chrome. Removed its unused 69.17 MB temporary profile and 33 repository Python __pycache__ folders totaling 2.2 MB. Measured available physical RAM improved from approximately 441 MB to approximately 505 MB; free C: space was 9.38 GB. Did not terminate interactive Chrome, Desktop Commander, either MT5 terminal, app bridge or KATARINA services.

Existing 5-minute Katarina-MarketBrain-Observer task was temporarily disabled for the one-shot read-only broker replay and then explicitly re-enabled and started. Legacy Decision/Analog observers remain disabled. GitHub workflow queue is not to be expanded with a duplicate cron.

## Remaining hard limitations

Trading autonomy and profitability are NOT achieved. Genuine cost-reconciled forward paper outcomes, broker historical tick clock/DST, verified policy/event context and separate production-safety approvals are missing. Historical replay can accelerate engineering and eliminate bad ideas, but cannot be relabeled as fresh market experience or used to enable live trading.
