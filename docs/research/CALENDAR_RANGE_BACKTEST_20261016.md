# Calendar-range backtest request, 16 October 2026

Owner requested a 2025–2026 backtest. Use the existing V6 technical baseline
without tuning score or side gates. Request 2025-01-01 inclusive through
2026-10-17 exclusive, capped at the current clock so incomplete bars are hidden.

```sh
python scripts/research/backtest_unified_intraday_brain_v6.py --start-date 2025-01-01 --end-date 2026-10-17 --output-dir PRIVATE_NEW_BACKTEST_FOLDER
```

Calendar mode fetches M5/M15/H1 per month, rather than silently limiting the
request to the most recent 90,000 M5 bars. Existing last-N mode is unchanged.
Results include actual first/last timestamps, bar counts and missing months for
each symbol/timeframe. Partial calendar months and broker sessions can still be
incomplete even if a month returns at least one bar. No DST/session completeness
claim is inferred from nonempty monthly responses.

The test uses the V6 technical research variant and modeled next-open OHLC fills,
historical bar spreads, adverse point and the existing 0.03R allowance plus
0.10R/0.20R stress scenarios. Historical macro verification is counterfactual,
not a real point-in-time news archive. Full-system AI/news behavior, broker tick
fills and historical account commissions/swaps remain unverified. No research
score optimization, BUY-only selection or live configuration changes are included.

Run as a single bounded foreground research task in the Owner MT5 session, using
an isolated approved source checkout/output directory. Preserve the active
observer/state and publish only aggregate derived evidence, not raw broker data
or account details. This is not native every-tick MT5 Strategy Tester proof and
not a pristine unseen holdout: these dates were inspected by earlier research.
