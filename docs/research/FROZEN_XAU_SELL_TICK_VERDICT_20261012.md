# Frozen XAUUSD SELL tick verdict (final single audit)

**Decision criteria are intentionally fixed.** This is a final independent
quote-fidelity review of two **existing** V9 SELL candidates
(`TREND_EXPANSION_V9`, `SWEEP_2C_CONFIRM_V9`), not V11, not another
parameter search, and not a rewrite of production KATARINA.

- Signals, stop, target, spread/ATR restrictions and 2-hour holding
  interval come from the immutable prior V9 source at
  `0b300ca86ec8d14d5bb2a175939404cefb8f733f`.
- VPS only **reads** XAUUSD.vx M5 BID OHLC and actual broker historical
  tick BID/ASK, without writing files or disclosing account data.
- Critical limitation: broker returns **zero XAUUSD ticks** for sampled
  dates in June, July and August 2026. For example June 15/July 15/
  August 18 10:00–10:03 UTC each returned 0; September 22 returned 1002
  and October 8 returned 1091. Therefore **the V9 June-Aug SELL
  profitability cannot be tick-validated with this feed**.
- This audit explicitly covers September 15 to October 10, 2026
  (exclusive), wherever complete tick paths actually exist. This is
  retrospective and prior date ranges have already been seen, **not
  independently unseen forward/OOS**.
- SELL entry uses the first valid BID/ASK tick within 90 sec after
  closed-signal time, unfavorable one tick; stop and target use the V9
  price convention shifted by entry bar spread. Exits use actual ASK
  tick quotes, unfavorable one tick, pessimistic stop gaps, limit-capped
  TP, and fixed maximum hold 2h. Any gap greater than 180 sec or missing
  deadline quote rejects the tick path, never imputes a result.
- Report only aggregate means, profit factor, win fraction, by-month
  coverage, and reasons for excluded cases. Fee 0.03 R plus additional
  0.10 R cost stress remain assumptions; actual broker fills/commission,
  swap and slippage still unverified.
- **Promotion criteria:** NO_GO until *fresh, independent* time
  coverage, >=30 complete cases per method across multiple distinct
  months and consistently positive after-cost expectancy and PF>1.2;
  missing data or prior exposure cannot be called a pass.
- The main KATARINA Brain, risk governor, broker accounts, MT5 orders,
  services and VPS files are untouched.

## Final measured evidence


## Measured terminal result — 12 October 2026

Completed audit on authorized, trading-disabled Windows VPS. All code
was fetched from GitHub using an immutable commit and loaded into Python
memory. The system placed **0 orders** and changed **0 production files
or risk settings**. Independent GitHub Actions safety and Body CI are
[PASS](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38207767113).

Frozen methods evaluated using BID/ASK tick replay during
**2026-09-15 through 2026-10-09 inclusive**, with gaps rejected:

| Preexisting V9 SELL method | Eligible signals | Complete tick paths | Coverage | Mean after 0.03R assumed fee + 0.10R extra stress | PF | Win % |
|---|---:|---:|---:|---:|---:|---:|
| TREND_EXPANSION_V9 | 21 | 19 | 90.48% | +0.310727 R | 1.63904 | 57.89% |
| SWEEP_2C_CONFIRM_V9 | 31 | 28 | 90.32% | -0.403243 R | 0.49123 | 28.57% |

19 of 21 expansion trials had complete tick data (2 missing
time-stop quotes); 28 of 31 sweep trials had complete tick data
(2 missing time-stop quotes, 1 genuine tick gap). Missing trades were
**excluded, not reconstructed as profitable losses or wins**.

**Expansion by calendar month (actual tick paths, fee+stress):**
September 15 observations, average +0.330189 R (PF 1.71693);
October 4 observations, average +0.237745 R (PF 1.40812).
Four October outcomes are radically insufficient to infer stability.

**Sweep by calendar month (actual tick paths, fee+stress):**
September 13, average -0.330758 R (PF 0.59068);
October 15, average -0.466063 R (PF 0.40184).
Stop pursuing SWEEP_2C_CONFIRM_V9 as the leading candidate; retain
as an immutable negative control in research archives.

### Binding decision

1. **TREND_EXPANSION_V9 SELL: RETAIN FOR PROSPECTIVE PAPER-ONLY
   OBSERVATION.** An interesting previously developed signal family,
   **not demonstrated robust**: only 19 tick-complete cases across
   2 partial months, retrospective dates, and no genuine untouched OOS.
   No live activation.
2. **SWEEP_2C_CONFIRM_V9 SELL: REJECT AS LIVE CANDIDATE** based on
   clearly negative both-month tick evidence. Do not optimize it to
   mask observed loss.
3. **PROJECT PRODUCTION: WAIT / NO GO.** Do not promote either method
   based on this audit.

**Important:** tick history from the 2026-06 to 2026-08 V9 study
was **not available** from this broker interface. That older period
could not be honestly verified with actual tick BID/ASK. The Sept/Oct
window is chronologically later, but still **not independently unseen**
as these markets/dates were broadly examined in other research.

**Next validation boundary:** Freeze all entry/SL/TP/cost rules and
collect new unseen prospective paper outcomes before further model
changes, requiring at least 30 valid trades across multiple complete
months, robust after-cost expectancy and profit factor >1.20,
plus true contract/commission/slippage/margin verification.
If that fails, shut down the candidate. Do not iterate V11–V99
by continually reusing this known history.

### Machine-readable evidence

`docs/research/outputs/20261012/frozen_xau_sell_tick_verdict_aggregate.json`
contains ONLY these aggregated counts and model results. No tick
rows, brokerage credentials, account activity, or unfilled orders
are in GitHub.

