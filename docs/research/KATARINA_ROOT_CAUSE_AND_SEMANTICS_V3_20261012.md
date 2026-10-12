# KATARINA — Root Cause, Semantic Playbooks, and Readiness V3
Date: 12 October 2026 | Broker research, 55 instruments | Read-only

**Outcome: No validated profitable strategy. No live trades or authorization.**

## What was actually diagnosed

Prior pipeline classified regimes and proposed four named playbooks, but the entry router admitted
false positives: TREND_PULLBACK merely accepted a favorable candle, BREAKOUT_RETEST accepted a
breakout with no actual retest, RANGE_FADE could accept a weak edge reaction, and
REVERSAL_RECLAIM lacked proof of a sweep/reclaim. This is a semantics/price-action defect
as well as an unknown trading edge; making thresholds harder alone is insufficient.

A matched counterfactual at exactly the same sample times, with the **same historical ATR,
spread, exit and fees**, tested the opposite direction. Results are *diagnostic only*:

| Pair | Original entries | Original mean R | Same-time reverse-side mean R | Original minus reverse |
|---|---:|---:|---:|---:|
| XAUUSD.vx | 616 | -0.13330 | -0.13485 | +0.00155 |
| EURUSD.vx | 297 | -0.30024 | -0.15868 | -0.14157 |
| US30.vx | 591 | -0.07169 | -0.22543 | +0.15374 |

Interpretation: XAUUSD's sampled direction showed essentially no advantage over reversal;
EURUSD's original direction was worse; US30 retained some directional information,
but no profitable exit edge is established. **Reversing all signals also loses money.**

## 55-pair semantic falsification

New independent CLOSED-candle validator:
- Trend Pullback: prior countertrend bars, actual correction, MTF trend context and directional resumption;
- Range Fade: test/breach of a previous range extreme, close back inside, meaningful rejection;
- Breakout Retest: previous closed candle breaks an earlier, strictly-prior range; the *next* candle tests and holds that old boundary;
- Reversal Reclaim: sweep beyond prior liquidity, close back through level and rejection.

Data and fills were kept unchanged from the previous baseline, and the validator was tested
against all original historical signals, not against cherry-picked profitable winners.

| Research filter | Trades | Mean net R | PF |
|---|---:|---:|---:|
| Original sampled decisions | 8,310 | -0.20509 | 0.7008 |
| Original + structural-quality V1 | 1,241 | -0.15169 | 0.7741 |
| True semantics only | 2,944 | -0.18407 | 0.7293 |
| V1 + true playbook semantics | 731 | -0.14473 | 0.7847 |

**Important flaw identified:** 1,333 historical orders labelled BREAKOUT_RETEST, but only
170 (12.8%) satisfied the causally checked true-retest semantics; just 4 also passed
the structural-quality gate. This is evidence of mislabeled setups, not proof that
the small accepted subset is profitable.

Chronological historically reviewed slices for both gates:
- 2025 available: 250 entries, **-0.27020R**, PF 0.6232.
- Jan–May 2026: 311 entries, **-0.03365R**, PF 0.9470.
- Jun–Oct 2026: 170 entries, **-0.16341R**, PF 0.7574.

### Hypotheses that did not pass readiness

- **US30.vx:** 94 entries, +0.05494R, PF 1.0908; however 2025 -0.19209R and additional
  0.10R cost stress yields **-0.04506R**. Not mature.
- **JPN225.vx:** 75 entries, +0.11548R, PF 1.2025; however Jan–May 2026 -0.01003R,
  0.10R additional stress leaves +0.01548R, and only 75 sampled events. Not mature.
- **EURUSD.vx:** 9 accepted entries and +0.34634R. Insufficient count and mixed period
  results, cannot override the 297-event directional null test.
- **XAUUSD.vx:** 118 accepted entries, -0.03528R, PF 0.9446. Remains negative.

**Evidence readiness gate:** 55/55 markets UNVALIDATED; paper candidates 0,
validated live strategies 0. Conditions include >150 entries, positive mean R,
PF >=1.20, positive mean >=0.05R after +0.10R transaction-cost stress, each
chronological period positive, and genuine independent unseen holdout, calibrated
broker tick costs, verified news, full M5 scan, and causal inputs.

These are *research acceptance criteria*, not an implication that they can
be met by continuously searching historical parameters.

## Changes and safety

- src/katarina/intelligence/semantic_setup_truth.py implements deterministic,
  explainable price-event verification using closed candles and explicit blockers.
- src/katarina/intelligence/market_decision_pipeline.py exposes semantic_setup,
  optionally sets WAIT if semantic confirmation is missing, and preserves read-only status.
- scripts/ai/run_readonly_decisions.py enables the semantic gate and publishes details.
- src/katarina/intelligence/research_readiness_gate.py prevents promotion solely because a
  historically inspected subset looks profitable. It never authorizes live trading.
- scripts/research/audit_directional_null_v3.py runs matched opposite-side controls.
- scripts/research/audit_semantic_setup_55_v3.py replays all 55, unchanged original fills.
- scripts/research/review_readiness_v3.py grades the entire population, including losers.
- tests/unit/intelligence/test_semantic_setup_truth.py and
  tests/unit/intelligence/test_research_readiness_gate.py guard causality and fail-closed promotion.
- Additional pipeline unit test verifies mislabeled trend pullbacks become WAIT.

Raw audit outputs are maintained under
C:\KatarinaDev\decision-backtest-20261012\root_cause_v3\
and C:\KatarinaDev\decision-backtest-20261012\semantic_v3_full_55\.

## Scientific limitations (mandatory)

1. This is **one in every 36 M5 candles**, not bar-by-bar. A future complete event replay
   could produce substantially different entry frequencies and results.
2. The data for 2025–2026 **have been repeatedly inspected**, so none of the above is
   truly independent out-of-sample or forward performance.
3. MT5 server-local timestamps, trading sessions, and historical DST are not independently
   reconstructed; no verified point-in-time news blackouts.
4. Broker candle spread is not executable historical tick bid/ask, and commissions, slippage,
   swap, margin and cross-asset exposure are not reconciled.
5. Summed R measures independent trade outcomes, not realizable compounded account growth.
6. This model is an explainable **rule-based research Brain**, not a statistically trained
   self-learning AI with externally calibrated winning probabilities.
7. Improving semantic correctness can reduce false labels but **cannot manufacture alpha**.
   A strategy failing out-of-sample/costs must remain WAIT.

## Decision

**Keep all live execution disabled.** Stop parameter hunting on reused data and do not
declare US30 or JPN225 winners. Freeze well-defined hypotheses, perform a full chronological
causal replay with tick-level cost calibration, then collect new, truly unseen paper/forward
observations after freeze date. Fail any hypothesis whose out-of-sample net expectancy,
drawdown or cost stress is unacceptable. A NO_TRADE verdict is acceptable.

## Research basis

- Bailey, López de Prado (2014), "The Deflated Sharpe Ratio: Correcting for Selection
  Bias, Backtest Overfitting, and Non-Normality",
  https://doi.org/10.3905/jpm.2014.40.5.094
- Bailey, Borwein, López de Prado & Zhu (2017), "The Probability of Backtest Overfitting",
  https://doi.org/10.21314/JCF.2016.322