# KATARINA — Broker-adaptive priority scanner (12 October 2026)

**Research-only / WAIT. No live-trading authorization.**

The routine technical scanner is bounded at **17 markets**, down from an
unrestricted broker catalog (55 historical liquid markets and 74 catalog
entries at the former checkpoint). Brokers can expose fewer markets: **no
missing instrument is invented and no missing optional asset blocks other
eligible markets**.

| Tier | Requested markets | Count |
| --- | --- | ---: |
| Major FX | EURUSD, GBPUSD, USDJPY, USDCHF, USDCAD, AUDUSD, NZDUSD | 7 |
| Selected cross FX | EURGBP, EURJPY, GBPJPY, AUDJPY, EURAUD | 5 |
| Optional multi-asset | XAUUSD, BTCUSD, oil, US30, US100 | 5 |

The FX crosses are a liquidity-oriented *coverage choice*, not a validated
profitability ranking. Risk exposure may be correlated and the existing
market-entry, news, cost and risk checks still apply.

## Broker mapping

All selectors use `broker_scan_universe.resolve_broker_symbols` against
`mt5.symbols_get()`:

- Prefixes/suffixes used by brokers are recognized conservatively, e.g.
  `EURUSD.vx`, `EURUSDm`, `NAS100.vx`, `XAUUSD.raw`.
- US100 may be advertised as NAS100, USTEC, NASDAQ100, NQ100 and related
  aliases. US30 may be advertised as DJ30/WS30.
- Oil prefers a WTI/USOIL instrument; **Brent/UKOIL is fallback** when no WTI
  alias is available. Actual broker symbol is preserved so different
  contracts are not mistaken for identical instruments.
- A symbol is selected only if the broker advertises it and its trade mode
  permits opening a position. A category maps to **at most one** broker
  symbol. Unavailable markets are skipped, not treated as fatal errors.
- If the broker catalog itself is inaccessible, the scanner fails closed.
  Missing broker clock or valid current quotations still blocks
  technical decisions; an absent asset is never an excuse to bypass those
  safety checks.

Updated read-only paths:
`multi_market_brain.collect` (called by `run_market_brain.py`),
`run_readonly_multi_pair_watchlist.py`,
`run_decision_brain_v3.py`,
`collect_forward_intraday_v6.py` and the **default** for fresh
`backtest_unified_intraday_brain_v6.py` runs. The V6 replay permits explicit
`--symbols` override for legacy forensic comparisons. The historical V1–V6
artifacts have **not** been recomputed or silently relabeled.

This change reduces symbols polled. It **does not establish edge, net profit,
forward validation, broker cost calibration, or live readiness**.
