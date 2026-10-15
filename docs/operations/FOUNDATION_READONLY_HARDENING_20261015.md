# Katarina — Foundation engineering readiness, 15 October 2026

## Scope
**No trading strategy changes.** BUY/SELL, scoring, entry/exit/SL/TP, lot sizing, models and backtest code remain exactly unchanged. No new live order gateway, broker orders, observer worker or background schedule. The existing single five-minute canonical observer owns broker reads, market Brain, cognition, SQLite and paper shadow.

## Infrastructure delivered
1. broker_account_monitor.py: independent read-only MT5 terminal/account/positions/orders snapshot. Keeps account identifiers and raw balances/equity out of reports. Unknown state never means zero exposure. Detects missing protective stop loss but does not approve or calculate executable risk.
2. foundation_readiness.py: explicit checks for terminal Algo Trading OFF, account/position/pending-order read, unprotected positions, canonical broker UTC tick event time, market coverage, sensor health, Fed/ECB/BoE/calendar cache transport, cognitive checkpoint, virtual portfolio limit, and zero broker order authority.
3. Existing canonical observer now writes broker_account_monitor and foundation_readiness in latest.json, and rechecks Algo Trading OFF at end of the same cycle. This does NOT change signals or free any strategy risk gate. Real-account-risk-not-connected remains true.
4. audit_foundation_readiness.py: read-only one-shot external validation of latest.json freshness, SQLite quick_check, append-only cognitive ledger checkpoint identity, virtual shadow book and the engineering checks. Does not connect an order gateway or start a second observer.
5. Regression tests include missing account books, active Algo Trading, missing stop losses, future ticks, stale or tampered knowledge and incomplete news.

## Understanding the results
RESEARCH_FOUNDATION_PASS_PRODUCTION_BLOCKED means software/observation healthy, NOT market alpha or readiness to execute trades.
RESEARCH_FOUNDATION_DEGRADED_PRODUCTION_BLOCKED means a real component failure needing diagnosis; never override it for trading.
RESEARCH_FOUNDATION_INTEGRITY_PASS means the read-only database and snapshot consistency audit passed.

## Important limits
- MT5 broker server current UTC offset is observed metadata, not proof of historical DST.
- News cache transport health is not independently verified official macro trade context.
- Episodic/semantic virtual quote R is not a real broker fill, verified commission, or profitability evidence.
- No independently verified daily realized loss, peak drawdown, correlated multi-asset risk, fee/slippage or historical real fills yet.
- Two independent external model reviewers remain absent; governance approval and release to live remain blocked.
- Exact-strategy backtest and future strategy discovery are a separate stage; neither is altered here.
- The owner must explicitly approve any future live execution. Terminal Algo Trading remains OFF.

## Run on VPS
Invoke C:\KatarinaDev\brain-runtime\Scripts\python.exe with C:\KatarinaFreshLab\source\scripts\ai\audit_foundation_readiness.py and arguments --state-dir C:\KatarinaDev\artifacts\contextual-observer --max-age-seconds 720.
Run only as a one-shot auditor: no new scheduler or separate Brain process is required.
