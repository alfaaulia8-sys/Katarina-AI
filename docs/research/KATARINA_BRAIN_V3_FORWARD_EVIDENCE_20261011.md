# KATARINA Brain V3 — evidence before execution

Research design, 2026-10-11. **No live execution is enabled by this change.** All broker-specific tick simulations, contract/currency conversion, margin checks and real MT5 validation are reserved for the MT5/VPS test lane.

## What makes a trading brain smarter?

More indicators do not create an edge. The decision process must be a sequence of independently tested questions:

1. **Observe closed data:** broker market open, fresh M5/H1/H4 data, actual spread, news blackout, volatility, tick-volume proxy (not exchange volume), and unambiguous symbol specifications.
2. **Pick a market-specific playbook:** currently XAUUSD intraday opening-range breakout/ADX and rolling volume-weighted reclaim/ADX are *research candidates*. XAUEUR, indices, crypto and FX have NOT passed independent multi-year tests as tradeable alpha.
3. **Demand a pre-frozen forward evidence record:** forward trades need to be genuine PAPER or BROKER_DEAL observations with known costs. Previously inspected 2025/2026 backtests MUST be excluded. A ranking score is not a proven win probability.
4. **Check live market quality:** sufficient target R after spread/commission/slippage, mandatory protective SL and suitable timeframe/session.
5. **Protect correlated positions:** XAUUSD and XAUEUR are GOLD group; no second active group entry. Supply a reconciled existing-symbol risk map. Unavailable maps must fail closed when strict mode is used.
6. **Use the Risk Governor:** risk fraction decreases as capital grows, must fit minimum broker volume (never force minimum lots upward), account currency and committed risk from positions/pending/reservations. Any forward evidence quality factor can ONLY reduce approved risk.
7. **Learn safely:** store trade lineage, setup ID, entry SL, gross and net R, costs, broker session, prediction context, rejected signals and realised slip; perform drift audits and out-of-sample monitoring. Never auto-retrain on future data or silently promote live configurations.

## Implemented in this PR

**`src/katarina/intelligence/strategy_evidence.py`**

`ForwardStrategyEvidenceGate.assess` needs a symbol, stable strategy ID, strategy freeze timestamp, as-of timestamp and cost-verified PAPER/BROKER_DEAL closed outcomes. Denies duplicates, other symbols, non-finite returns, naive timestamps, future leakage and pre-freeze events as forward performance. Minimum defaults: 40 observed closed trades, 12 independent calendar weeks, four months, five loss cases, PF >=1.20, realised drawdown <=12R and >0 lower 95% week-block bootstrap mean. Even when eligible, it returns `live_authorized=False` and caps quality risk multiplier at 0.75. This is a **screening heuristic**, not a statistical proof or an estimate of trading success.

**`src/katarina/engines/multi_symbol_execution.py`**

Optional `require_strategy_evidence=True`: proposal must provide a stable `strategy_id` and a genuine evidence decision from the new gate; otherwise reject before risk reservation. Optional `exclusive_exposure_groups={"XAUUSD":"GOLD", "XAUEUR":"GOLD"}`: candidate is rejected if another in-group symbol has positive reconciled exposure or was admitted earlier. Without explicit `existing_symbol_risks`, strict group mode refuses to assume that an account is flat. The default legacy behavior remains unchanged until a reviewed caller adopts the flags. Strict mode cannot bypass Risk Governor, spread guard, preflight or the later Stage36/38 authority.

**Tests**

`tests/unit/intelligence/test_strategy_evidence.py` plus `tests/unit/engines/test_strategy_evidence_portfolio.py`: forward PAPER evidence can enter *risk review only*; historical replays, unverified costs, duplicate IDs, future candles, flat/missing coverage, weak expectancy and invalid identity must remain blocked. Strict portfolio mode rejects uncertified strategies and second Gold exposures, and frees/does not create reservations for rejected entries.

## Current historical findings, NOT forward-qualified

- XAUUSD: 2025–2026 dual-playbook backtest showed 158 non-overlapping candidate entries and $473.08 modeled total gross P&L for $1,000 standard start over about 21 months. That is only a previously optimized simulation.
- New evidence gate **intentionally does not accept this backtest as forward verification**.
- No data support claiming that this strategy pays KATARINA monthly operating costs or will sustain any target win rate.
- Higher volatility alone does not equal expected profitability. Multi-pair strategies that failed validation stay `NO_TRADE`.

## Next changes (not in this PR)

1. Add a typed closed-M5 H1/H4 broker adapter and instrument/session clock normalization; use MT5/VPS only for bid/ask ticks and broker order_calc_profit verification.
2. Wire setup IDs from the execution-independent intraday candidate registry to the runtime broker snapshot, first in shadow mode with a period frozen before the first observation.
3. Implement *durable* forward journal, startup restoration and regular strategy-drift checks (recency, losing streaks, cost growth, slippage, calendar-month stability). On loss of edge return `NO_TRADE` without increasing risk.
4. Add portfolio gross/sector correlation caps using aligned fresh return data, alongside the exclusive underlying group guard.
5. Run strategy-by-strategy walk-forward evaluation with a sealed future window. Track per-month BUY/SELL, execution acceptance, costs, net P&L and floating drawdown by $100/$1,000/$10,000 account.
6. Keep MT5 execution disarmed until all original live authorization requirements are satisfied.

## Reproducibility

GitHub Actions `KATARINA Body CI` and `KATARINA Stage 10-40 Baseline` run on PRs and use `PYTHONPATH=src python -m unittest discover -s tests/unit -p 'test_*.py'`. CI proves code behavior only; **CI cannot prove future trading profitability or actual MT5 fills**.

Research sources: Bailey & Lopez de Prado's Deflated Sharpe Ratio (multiple testing) https://doi.org/10.3905/jpm.2014.40.5.094 and MetaQuotes' MT5 testing docs https://www.metatrader5.com/en/terminal/help/algotrading/testing .
