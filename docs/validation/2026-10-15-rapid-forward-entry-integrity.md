# 2026-10-15 — Rapid forward test integrity gate

## Decision: NO-GO for profitability or live authorization

The canonical observer remains scheduled every five minutes, reading the demo MT5 terminal with Algo Trading OFF. This is a bounded one-shot diagnostic, NOT an independent forward profitability test or another scheduled service.

- Seven preexisting prospective shadow entries were frozen on October 12–13. **Zero new shadow entries on October 15 (UTC)** as of audit.
- Original virtual book: five VIRTUAL_QUOTED (four negative, one positive), and two UNCERTAIN_GAP. None are real MT5 deal fills.
- Fresh archived MT5 tick comparison of original frozen entries: **four of seven matched, three of seven mismatched** by 6.125, 3.048 and 16.517 times their recorded spreads respectively (US30 SELL, USDCAD SELL, XAUUSD SELL). The cause is not proven. Do not rewrite or retroactively correct the immutable original receipts.
- Of the four matching entries, **two remained UNCERTAIN_GAP** and **the other two original virtual quoted outcomes were both negative**. Mean original modeled return for the two matching and quoted results = **-0.474485R**, including assumed 0.15R cost stress. It is a tiny descriptive subset, not a valid expected return estimate.
- A separate retrospective two-hour archived tick replay showed potential stop-side quote hits, including on a previously gapped XAUUSD SELL. This is diagnostic, NOT proof of contemporaneously observed exits, and may never be used to overwrite forward history.
- All seven existing hypotheses had official_news_verified=false. A read-only 30-day MT5 deal history check found 13 historical deals and **zero nonzero commission samples**. This does NOT establish actual broker commission or slippage and is not evidence that fees are zero.

## New reusable read-only audit

File: scripts/ai/audit_forward_shadow_entry_integrity.py. Opens the observer SQLite journal in mode=ro. Requires connected terminal with Algo Trading OFF. Queries only historical Bid/Ask ticks occurring at or before each frozen entry, comparing original bid/ask at bounded skew and observed broker tick size. Reports MATCHED, MISMATCHED and UNVERIFIED entry provenance separately. Does not modify old journal rows, use future quotes as entry evidence, or issue trading orders.

Run under the existing Python environment, passing --database for the existing contextual-observer/context.sqlite3 and --terminal for the current terminal64.exe. Test suite: tests/unit/intelligence/test_fast_forward_entry_integrity.py.

The scorecard's decision remains NO_GO_INSUFFICIENT_VERIFIED_FORWARD_EVIDENCE; it never auto-promotes any strategy or model. This tool is a one-shot diagnostic. No new VPS schedule or competing observer was installed.

## Short-cycle next gate

Keep the five-minute real prospective collector active. Each new signal must have original entry archived-tick consistency, full causally observed exit paths and verified broker costs before anyone assesses actual strategy expectancy. If new shadow entries remain zero, classify that explicitly as a signal-generation/gating blocker rather than pretending the forward test passed. No live orders.
