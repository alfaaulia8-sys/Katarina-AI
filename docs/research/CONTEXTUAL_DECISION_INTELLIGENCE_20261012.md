# KATARINA — Data-driven contextual decision intelligence

## What actually changed

A new pure-Python **reasoning engine**, not an LLM prompt, is at
`src/katarina/intelligence/contextual_decision_intelligence.py`.
An additive native entrypoint, `MarketDecisionBrain.evaluate_contextually(...)`
in `src/katarina/intelligence/market_decision_brain_v3.py`,
combines the **existing closed-candle multi-timeframe MarketDecisionBrain**
with three additional verified inputs:

1. **Macro-policy evidence**, each with publisher, publication timestamp,
   observed timestamp (cannot be later than decision time), the explicitly
   affected market, inferred policy direction, *transmission mechanism*
   and verified-source flag. Multiple opposing sources trigger WAIT.
   This is NOT automatic web research or LLM sentiment. News must be
   provided by an upstream authenticated, point-in-time news connector
   and assessed by `MultiSourceNewsEngine` into `NewsContext`.
   No news or stale/unknown policy implications => WAIT.
2. **Market executable context:** actual broker spread (in price terms),
   M15 ATR from genuinely closed candles, technical plan and after-spread
   RR, quote and session validity, volatility regime, risk exposure and
   realized daily losses. Market closure/volatility shock/conflict or
   broker friction exceeding 0.22 M15 ATR => WAIT.
3. **Resolved market experience:** records scoped by exact symbol,
   strategy, BUY/SELL and regime; only historical outcomes with
   **resolution before current decision** are eligible. Forward records
   count as trusted only if individually labeled `independently_forward_observed`,
   `bid_ask_replay_verified` and `cost_reconciled`. A corrupted or
   future-leaking ledger blocks selection. Historical V6–V10 results
   are **not** forwarded as independent outcomes.

## What KATARINA will decide

The result contains: market state and direction bias; reason for
selected playbook; conditional BUY/SELL or WAIT; structural stop/target
hypothesis; news-policy rationale and its economic transmission;
diagnostic after-spread RR; historical strategy outcomes for **this
exact symbol/side/regime**; confirming facts; blocking reasons;
alternative scenario; and next evidence needed to reconsider.

This addresses the user requirement to **derive a conditional plan
from multiple types of evidence**, rather than producing an LLM text
or automatically opening trades based on a green technical arrow.

**Evidence gate:** at least 45 genuinely independent, tick-verified
and cost-reconciled resolved outcomes from at least 3 distinct
positive calendar months, mean net R >+0.10, PF >=1.20,
positive recent 20-trade mean, and a descriptive 95% lower bound of
the sample mean >0. Passing produces only `PAPER_OBSERVATION_ONLY`.
None of this is a calibrated win probability, scientific guarantee or
authorization to change the production Risk Governor.

**Fail closed** for unknown/future/stale candles, inadequate R:R,
news blackout, missing verified macro thesis, opposing macro/technical
direction, high spread, exposure cap, 4% hypothetical drawdown pause
or -2R daily paper-loss pause. No realized data => no evidence-backed
entry. LLM narrative does not override these conditions.

## Non-goals and what has NOT been claimed

- No broker order, capital allocation, live EA setting, risk governor,
  VPS files or service has been changed by this integration.
- Existing `MarketDecisionBrain.evaluate` behavior is preserved;
  the new `evaluate_contextually` entrypoint is opt-in, research-only.
  This is a real callable library API, but **not wired to the live
  trading path, dashboard or an always-on broker watcher**.
- No business-quality news-feed data or independent forward outcomes
  have been fabricated. The latest retrospective XAU SELL tick
  evidence has 19 tick-complete cases and is explicitly NOT enough
  to clear this gate.
- Methodological limitations: mean lower bound is a naive descriptive
  standard-error bound; serial correlation/selection bias may make
  it optimistic. A strategy clearing the gate is still only a paper
  observation, not proven robust performance.
- Unit tests use synthetic examples for determinism only. They do not
  demonstrate live profitability or model precision.

## Where to inspect

Run `PYTHONPATH=src python -m unittest
tests.unit.intelligence.test_contextual_decision_intelligence -v`.
GitHub workflow `contextual-decision-intelligence.yml` executes the
same tests plus safety constraints. The public interface is intended
to be fed **verified** news and *resolved prospective* paper trades
by a future authorized data source; until those exist the correct
contextual output is `WAIT`.

This is the reasoning and abstention layer the project lacked, not
another parameter-optimization tournament. Preserve all core
production modules and safety boundaries.
