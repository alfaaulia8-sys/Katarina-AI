# AI Brain — internal validation handoff

Status: **research/shadow candidate implemented; external validation pending**.

The AI module can learn from labeled, completed trades and assess broker-ready market candidates under existing entry, quality, market, news, and system-health checks. All outputs remain **research-only**; no production model is automatically promoted and no live execution is authorized.

For offline regression:

```bash
PYTHONPATH=src python -m unittest tests.unit.intelligence.test_ai_brain -v
```

Inputs must be authentic, timestamped, and net of trading costs. Labels must become available **after** the feature observation; the trainer excludes late-known outcomes from the pre-holdout training window. Validation uses an untouched chronological holdout; a model candidate is rejected if it does not outperform a constant-prior baseline. Synthetic examples in the test suite are not performance evidence.

**Outstanding gates:** ingest validated broker/timeframe data; attach verified trade-outcome records; real-tick multi-symbol backtest and walk-forward runs; unbiased out-of-sample analysis; shadow/demo MT5 execution and broker reconciliation; strategy/risk policy approval and live authorization. Passing GitHub unit tests proves only implementation behavior, not profitability.
