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


## Broker-read observation, 12 October 2026 — verified on VPS

The *actual* optional `MarketDecisionBrain.evaluate_contextually` interface
ran against demo broker data through the **in-memory, read-only**
`scripts/research/probe_contextual_decision_broker.py`. It received
90 completed broker candles each from M5/M15/H1 for 3 instruments.
No private candles, account information, credentials, historical
tick rows, brokerage trades or VPS files were exported or written.

Market observation clock: **2026-10-12 05:50:31 UTC**.

**Critical timestamp discovery:** broker tick *and* bar raw epochs
appear displaced **+3 hours** from system UTC right now. Three
independent contemporaneous instrument ticks confirmed the same
integer-hour offset using existing
`katarina.intelligence.broker_clock_alignment.infer_clock_shift`.
Raw tick epochs apparently ~08:50 when system UTC was ~05:50.
The research snapshot alone normalizes them by -3h. Quote stamps
remained ~12.6 seconds ahead of system UTC after integer-hour
adjustment, within the explicitly narrow skew budget. The historical
offset and DST schedule have **NOT** been verified. Do **not**
blindly apply this +3h to past 2026 tick/bar data or any production
execution. Previous V9/V10 reports using raw broker epochs as UTC
must not be interpreted as verified historical UTC session timing.

| Broker market | Market state | Technical plan | Observed quote spread | Real decision |
|---|---|---|---:|---|
| XAUUSD.vx | TRANSITION | OBSERVE | 0.33 price | WAIT |
| EURUSD.vx | SIDEWAYS | RANGE_FADE hypothesis | 0.00016 price | WAIT |
| NAS100.vx | SIDEWAYS | RANGE_FADE hypothesis | 3.6 price | WAIT |

- XAUUSD: no confirmed directional entry and transition regime,
  so a past positive SELL test does **not** override current WAIT.
- EURUSD: spread is too high relative to current M15 ATR under
  predeclared research threshold; range conditions do **not**
  justify opening a BUY or SELL by themselves.
- NAS100: cost looks acceptable relative to ATR but no directional
  entry or validated statistical advantage; WAIT.
- All three: external point-in-time policy/newscalendar connector
  not yet linked to this probe, and the verified **prospective**
  trade-outcome memory is empty. There are **no invented policy
  summaries or outcome records**. All decisions WAIT, orders=0.

This is concrete market-conditional behavior and blocking reasons,
not proof of profit. The opt-in entrypoint is callable from a research
consumer today but is deliberately **not automatically invoked by
the live trader**. Live order authorization remains false, production
risk=0. No structural main KATARINA changes.

Safety/unit workflow, Body CI, Operational Hardening, Stage baseline
on the initial native reasoning code commit **all PASS**:
`cb9a1f2a55c88fe4173230a64fb4d8f3c6717472`.
Subsequent read-only probe corrections did not modify the entry
framework.
