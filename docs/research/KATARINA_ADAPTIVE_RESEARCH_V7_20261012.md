# KATARINA Adaptive Brain — historical-research implementation

**Status: RESEARCH ONLY / WAIT.** No live orders or production risk changes.

## Scope

Priority universe remains **maximum 17 broker-supported symbols**. New code:

- src/katarina/intelligence/adaptive_walkforward.py
- src/katarina/intelligence/adaptive_strategy_library.py
- scripts/research/run_adaptive_walkforward.py
- tests/unit/intelligence/test_adaptive_walkforward.py
- .github/workflows/adaptive-brain-research.yml

GitHub Actions reads only repository-safe V6 selected-paper trade outcomes,
and produces ephemeral diagnostic artifacts. The workflow does not connect
to VPS, MT5, trade accounts or private broker archives. VPS unchanged.

## Chronological adaptation

1. At each opportunity timestamp, mature only paper outcomes whose
   exit_time is strictly earlier than the current selection time.
2. Update rolling strategy, asset family, BUY/SELL and context-specific
   performance. Outcomes of previously rejected archive V6 events become
   eligible for shadow memory only after their modeled exit.
3. Use progressively broader contexts only if minimum closed-sample
   requirements are met. Non-positive conservative mean R, insufficient
   profit factor, recent deterioration or insufficient observations = WAIT.
4. Independently model research paper risk: 0.25% max entry risk,
   2 maximum concurrent positions, one per asset family, half risk after
   simulated 4% DD and stop admitting beyond 8% DD. Production Risk Governor
   is completely unchanged.
5. Benchmark against the same archived selected V6 paper events; additionally
   stress 0, +0.10 R and +0.20 R extra hypothetical costs. Show modeled
   equity, expectancy, profit factor, drawdown and per-month model results.

The V6 paper R already contains hypothetical spread/slippage/commission.
These records are not independently unseen data. They include previously
selected V6 trades, NOT the entire candidate stream. Consequently this
tests a counterfactual **admission gate**, not the relative edge of
independent strategy methods. The historical broker clock / DST is still
unverified, so timestamp labels refer to the broker-coded time.

## Strategy prototypes requiring a future OHLC research dataset

Four separate closed-candle methods exist in code:

- TREND_PULLBACK
- BREAKOUT_RETEST
- LIQUIDITY_SWEEP_RECLAIM
- RANGE_MEAN_REVERSION

BUY and SELL implementations are distinct. All are research-only candidate
proposals, not executable orders. The current V6 selected-trades-only CSV
cannot evaluate the P/L of those alternative methods. Real M5/M15/H1
candidate-level OHLC together with valid point-in-time costs, fills and
news would be needed to replay them fairly. These prototypes must not
be credited with profits from V6 outcomes belonging to another entry.

## Security and evidence constraints

Do not upload private broker tick history, account identifiers, credentials,
trade history, browser files, VPS snapshots or secret values to GitHub.
Keep broker data acquisition read-only on VPS unless explicitly ordered.
Previously inspected 2025–October 2026 samples do NOT count as fresh
independent out-of-sample validation. No live order path, gateway or Risk
Governor was enabled by this research.

The GitHub runner job is bounded to 25 minutes; provider quotas may apply.
It writes only ephemeral Actions artifacts, not new tracked history files.
