# KATARINA AI — MT5 real-tick validation sources (checked 2026-10-08)

Official MetaQuotes documentation:
- https://www.mql5.com/en/docs/runtime/testing — real tick simulation, fallback generated ticks when history incomplete, indicator calculation caveats.
- https://www.mql5.com/en/book/automation/tester/tester_ticks — real ticks vs generated ticks and data availability; history preloading for multi-symbol strategies.
- https://www.mql5.com/en/articles/2612 — tick-sequence-sensitive strategies can show materially different entry/exit behavior between Every Tick and Every Tick Based on Real Ticks.
- https://www.mql5.com/en/docs/python_metatrader5 — official Python bridge for bars, ticks, positions, margin and order checks.

Recommended implementation for KATARINA AI:
1. Record tester mode, percent of real ticks, spread/slippage, broker and date range for each run. Never compare profits without those settings.
2. Use real ticks as the acceptance gate for scalping, pending order, trailing stop and tick-sensitive EAs. Generated Every Tick is only a preliminary smoke test.
3. Require walk-forward and out-of-sample tests; segregate training and test periods to prevent leakage. This is a proposed test standard, not a tested result.
4. Preload multi-symbol history, verify bid/ask spreads, transaction costs and execution conditions. Reject setups with inadequate real-tick coverage.
5. Do not promise profitability; all strategies require independent forward testing and risk controls.

No source code copied. License and reuse: documentation linked for reference only; code examples require separate license review.
