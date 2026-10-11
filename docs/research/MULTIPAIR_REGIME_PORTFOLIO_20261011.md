# KATARINA: multi-pair regime and risk audit — 2026-10-11

**RESEARCH ONLY. No broker orders. Do not enable Stage 36/38 execution.**

## Research question
Which previously inspected market-specific setups are useful in which **historical** market contexts, and how do their portfolio metrics change under shared exposure, risk limits and stressed costs?

## Universe and provenance
- Previously screened: 14 volatile candidates plus an earlier seven-market grid (not equivalent to fresh OOS).
- This precise portfolio replay: **six fixed tick-replay rule candidates**, across **XAUUSD.vx** and **JPN225.vx** only; it MUST NOT be described as a 14-pair portfolio backtest.
- Source: private, reused artifact `katarina_shortlist_true_tick_20261011.json`, SHA256 `2a0730a6285eceb0fd1c9d2c686696a02ee73e2d21cdad1be033be23e52ed09f`. Do not upload original private tick/trade artifacts to public GitHub.
- New portfolio research script: `scripts/research/portfolio_regime_replay_readonly.py`; run with `KATARINA_RESEARCH_INPUT_DIR` pointing to the private input folder; optional `KATARINA_RESEARCH_OUTPUT_DIR` points to a writeable output. No MetaTrader5 import, no order interface.
- Replays are prior reconstructed ticks with known limitations, not an executed broker statement. Portfolio fractional stakes are virtual; broker minimum lots, margin, true account currency and fees are NOT reconciled.
- The 2026 window has already been inspected by earlier research. Selection based on 2025 alone here does not restore a virgin 2026 holdout.
- No clean profit evidence meeting current Brain V3 evidence gates.

## Context hypotheses — NOT certified alpha

| Symbol | Hypothesis | Observed market condition | Signal definition | Stop / Target / maximum hold |
|---|---|---|---|---|
| XAUUSD.vx | VWAP_RECLAIM | ADX at least 25, session 06:00 UTC | Reclaim of rolling volume-weighted price on closed M5 | H1 ATR ×0.55 / 1.5R / 3h |
| JPN225.vx | DONCHIAN24 | ADX below 18, session 12:00 UTC | Previously frozen Donchian24 / low-ADX setup on M5 | H1 ATR ×0.80 / 2R / 3h |

**Regime router rule:** A symbol may propose a research signal only when all session/ADX/VWAP-or-Donchian filters and closed-bar causal gates match that candidate. If symbol/regime/source/quote/news/cost inputs cannot be verified: `NO_TRADE`. This document does not wire any router or change production execution.

**What NOT to infer:** ADX context is not a guarantee of forecast direction; high-volatility pairs alone have no proven edge. Tick volume is not an exchange order book footprint. A setup that generates no signals in a quiet regime must remain idle.

## Portfolio selection and diagnostic findings
- Parameter grid size: 240 combinations of pre-existing setup choices, 0.25%, 0.50%, 0.75% modeled risk/trade, one/two slot caps, daily stop 1.0/1.5%, closed DD guard 6/10%. Select using 2025 historical STRESS only. Number of configurations is **not** 240 independent hypotheses.
- Training-2025 objective chose XAU VWAP RR1.5 3h + JPN Donchian24 ADX_LOW_18 RR2 3h; 0.75% per risk, one slot, daily stop 1%, closed DD limit 6%. Training STRESS: 82 trades, +17.554% virtual, PF 1.7465, 3.132% closed DD.
- **Failure:** 2026 with cost extra 0.10R: 84 trades, +1.594% before operational fees, PF 1.0447, max **closed** DD 6.823% and DD guard triggered. The loss can pass 6% before the guard reacts; it's not a hard guaranteed loss cap.
- The above is the maximum 2025 score, **not** the most defensible risk setting.
- Practical further PAPER baseline: 0.50% virtual risk/trade, **one** position total, daily loss 1%, total closed DD guard 6%, 3 losses in a row day halt, mandatory stop; virtual initial capital USD 10,000.
- On the full **reused** January 2025–September 2026 sample, that fixed 0.50% model gives 177 trades; BASE modeled +$2,454.18, STRESS +$2,195.55 (PF 1.528, max closed DD 4.575%); EXTRA_10PCT_R +$1,163.47 (PF 1.2641, max closed DD 5.149%). These are **not broker-verifiable returns**; capital, risk and currency modeling do not respect lot rounding or broker margin.
- In per-year reset tests with EXTRA_10PCT_R, the 0.50% two-symbol candidate made +6.983% in 2025 and +4.348% in 2026; 2026 is not clean out-of-sample. With 0.75% it breached the 6% closed-DD guard in 2026.

## Required before Brain learns from this
1. Freeze strategy versions and publish parameter-selection provenance. Never report recycled 2026 as an untouched holdout.
2. Recompute on live broker native Bid/Ask quotes and contract-based real sizing/margin; assert minimum lot, actual spreads, commissions, swaps, slippage, intratrade equity drawdown, UTC/DST, and quote gaps.
3. Validate source events with native broker real-tick MT5 Strategy Tester where feasible. Reconcile fill/stop logic against actual deal history, using read-only interfaces.
4. Evaluate future **unseen** forward sessions with independently measured costs, at least 12 weeks and four months with suitable trade count, exact accepted/rejected signal journal, weekly block bootstrap, loss-tail stress, and change-point checks.
5. Add news/calendar clearance; if unknown, fail closed. Disable correlated GOLD simultaneous positions and aggregate portfolio risk rather than per-symbol risk.
6. Test JPN low-ADX strategy separately under a future regime shift; do not give it live allocation simply because it diversifies Gold in retrospect.
7. Portfolio experimental return is *not* evidence of ability to cover operating expenses. Compute monthly net after costs, with minimum lot/margin and no future leaked data.

## References
- Bailey et al., *Probability of Backtest Overfitting* (2017): https://escholarship.org/uc/item/4w1110bb
- López de Prado, *Advances in Financial Machine Learning*, Chapter 7: https://www.oreilly.com/library/view/advances-in-financial/9781119482086/c07.xhtml
- MetaQuotes, *Strategy Testing*: https://www.metatrader5.com/en/terminal/help/algotrading/testing
- MetaQuotes, *Real and Generated Ticks*: https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation
- Moskowitz, Ooi, Pedersen, *Time Series Momentum* (2012): https://doi.org/10.1016/j.jfineco.2011.11.003
- CME Group, position sizing and stop-based risk: https://www.cmegroup.com/education/courses/trade-and-risk-management/proper-position-size

**Decision: NO_TRADE live; continue read-only forward paper evidence.**
