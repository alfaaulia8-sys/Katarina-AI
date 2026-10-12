# KATARINA AI independent operation — objective status (12 October 2026)

**Two meanings of autonomy must not be confused.** The VPS **can
autonomously observe, document and run research-only quote simulations**,
but KATARINA has **NOT independently proven a profitable strategy or
been authorized to execute broker trades**. Any claim otherwise is
unsupported.

## Five components executed as ONE non-overlapping pipeline

| User goal | Implemented now | Proof / hard boundary |
|---|---|---|
| Observe market | ONE scheduled read-only 5-minute Windows task, up to 17 broker symbols M5/M15/H1, causal closed candles, current broker-clock vote | Canonical `run_contextual_market_observer.py`; legacy Decision/Analog observers disabled |
| Understand full news | Fed/ECB/BoE official RSS with full-article body checks + 1 bounded CNBC feed with actual paragraph text and SHA256 cached in private SQLite | Policy hypothesis never derived from a headline alone; secondary media never authorizes a trade |
| Select conditional setup | Existing `MarketDecisionBrain.evaluate_contextually` using regime, observed spread, macro source, calendar blackout, and experience eligibility | Final decision remains WAIT without verified account risk and independent net outcome history |
| Evaluate experience | `ProspectiveShadowBook` stores ONE virtual research hypothesis across correlated pairs, close on observed bid/ask quotes, invalidate unobserved paths, 24-hour virtual cooling-off after five matching losses; descriptive review per pair/side/regime | No normalized broker commissions, fills, actual SL/TP path; derived R is a sampled virtual diagnostic, NEVER a resolved broker `ResolvedExperience` |
| Operate and recover | Existing single Windows task every 5min, IgnoreNew + OS worker lock + StartWhenAvailable; two automatic retries at 1-minute separation, 4-minute execution limit | No new cron or GitHub-polling process, no live order gateway, local private SQLite and atomic latest.json |

### Runner division of labor

- **GitHub Actions Body CI** is the sole routine push/PR gate. It runs
  complete unit/static/integration regression, security/readiness gates
  and an offline deterministic autonomous observer proof with a
  downloadable `autonomous-shadow-safety.json` artifact.
- **Windows VPS** is the ONE read-only MetaTrader5 data source plus one
  scheduled contextual worker. Any old Stage06/07 heavy Windows-native
  Actions remain manual-only, so routine changes do not flood Actions.
- Do NOT let GitHub Actions dispatch VPS jobs automatically or upload
  raw broker feeds to a public repository. 
- Safe local state directory:
  `C:\KatarinaDev\artifacts\contextual-observer\`.
  Files: `context.sqlite3` with news/full bodies, quote-markouts and
  virtual research; `latest.json`; `worker.lock`.

### Virtual paper limits

- Maximum one simulated position concurrently, ranked by
  preregistered model geometry across all eligible markets, not
  first symbol encountered.
- Requires a past-only closed M5 bar, technical evidence >=0.62,
  after-spread theoretical RR >=1.25, reasonable spread/stop geometry,
  fresh quotes, verified economic calendar with no blackout and no
  shock/transition market state.
- Enter BUY with observed ask/SELL with observed bid; evaluate stop/TP
  using later actual **observed** opposite-side quotes, with an extra
  conservative modeled cost of 0.15R and 2h maximum holding horizon.
  Cannot infer tick path between observer samples. If there is an
  observation gap longer than 8min, result is `UNCERTAIN_GAP`, not
  a cherry-picked profitable result.
- Media/official news missing can still label a hypothesis as
  **VIRTUAL_UNCLEARED_RESEARCH_ONLY**, for diagnosis of the filter
  itself. This does not override official WAIT or risk boundaries.
- Outcomes are grouped by exact symbol/strategy/side/regime and
  decision time. At least 30 valid cases across 10 UTC dates and 3
  calendar months are required even to *describe* virtual robustness,
  not to authorize live.
- Five successive negative virtual results within the latest 24h
  trigger a reversible **virtual-only** pause for that cohort.
- No code path routes these hypotheses into broker orders. The native
  Risk Governor, MT5 MQL5 EA and account state remain unchanged.

### Strict remaining milestones before **full trading autonomy**

1. Connect a reliable **official economic calendar / full-body news
   provenance and market-specific macro interpretation** that
   remains stable across several news-event sessions. Current
   deterministic narrative is limited and cannot be called an
   independently trained macro model.
2. Verify broker fees (commission, swaps, slippage), quote timestamp
   and DST normalization, actual lot/margin/account denomination, and
   reconciliation of real broker positions; do NOT infer them from
   a synthetic formula.
3. Run **genuine independent forward** paper observations across
   multiple calendar months, replay real tick paths, evaluate
   strategy net R and max floating/closed drawdown after costs.
   Only new, untouched data can qualify. Historical 2025–Oct 2026
   data is not pristine forward validation.
4. Review Stage35/36/38 live broker safety and request explicit owner
   authorization for any real-money experiment. None of these
   milestones can be shortened by running more GitHub jobs.

**Production decision: NO LIVE.** The correct final signal is WAIT
until those hard prerequisites are met. Our success so far is
operational independence of an evidence-collecting research loop,
not profitable autonomous execution.
