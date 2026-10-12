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

Pending exact read-only tick-run output. Do not infer any strategy edge
from unavailable June-Aug historical ticks.
