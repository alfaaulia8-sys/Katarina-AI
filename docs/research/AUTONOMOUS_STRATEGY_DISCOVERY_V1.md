# KATARINA Autonomous Strategy Discovery — V1

This is a **new offline evolutionary strategy research engine**, not a live
autotrader and not a trained foundation model. It discovers *combinations*
of causal price-feature rules rather than only adjusting one existing EA.

## Candidate genome

- Side: BUY or SELL, independently evolved.
- 1–3 conjunctive conditions chosen and mutated from momentum (3, 8 bars),
  relative location in an eight-bar range, candle body, wick bias,
  volatility ratio and an eight-bar breakout displacement.
- Exit parameters: stop distance (ATR multiples), reward/risk multiplier,
  and bar horizon; all bounded.
- Deterministic random seed with separate mutations of rule feature,
  comparator, threshold, side, risk, target and horizon.
- Candidate is a **JSON rule specification**, never dynamically executed code.

## Validation

- Strict UTC timestamp ordering and verified OHLC geometry.
- Feature values use only current/prior *closed* bars.
- Signal at candle close; entry at next candle open (mid quote approximation).
- Configurable assumed spread and R-denominated fee. When a bar touches
  stop and target, stop takes precedence. Favorable gaps are capped, while
  unfavorable stop gaps are retained.
- One simulated candidate position at a time; no position's outcome can
  cross chronological train, validation or holdout boundaries.
- Candidate selection on earlier 60% training and next 20% validation.
  The final 20% is diagnostic holdout **never used to select/mutate rules**.
- Bounded generations/populations, penalized validation fitness, trial-count
  complexity haircut, minimum trades and distinct UTC days.
- At most three shortlist candidates. Positive validation does NOT establish
  a statistically proven forward edge (selection bias still exists).
- No commission or slippage calibration to real broker data, no tick path,
  swap, margin or verified account ledger.

## Runner

`.github/workflows/katarina-strategy-discovery.yml`: manual-only
GitHub-hosted ubuntu-latest, Python 3.12, no secrets or remote desktop/VPS.

`PYTHONPATH=src python scripts/research/run_autonomous_strategy_discovery.py
--synthetic --output build/discovery/candidates.json
--summary build/discovery/SUMMARY.md`

The built-in fixture has deliberately synthetic oscillating price conditions,
NOT a profitable strategy benchmark. The output includes each genome,
train/validation/held-out diagnostics and a SHA-256 hash of source bars.

For **user-provided CLOSED OHLC**, use `--bars /path/to/bars.csv` instead of
`--synthetic`. CSV columns must be
`close_at_utc,open,high,low,close`; `close_at_utc` must be ISO-8601 UTC
with `Z` or `+00:00` timezone. This path is currently for isolated,
trusted offline runners, **not an automatic GitHub upload**.

The output source is always identified: synthetic fixture or unverified OHLC.
Neither becomes independently verified real trades simply by loading it.

**All outputs:** `production_action=WAIT`, no orders, no auto-merge,
no live risk authority, no automatic model promotion. Promising ideas require
new prospective broker observations and independent validation before release.
