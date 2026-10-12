# KATARINA V10 — higher-timeframe entry, exits and risk (research only)

**Status: research-only / WAIT.** Main Brain, broker universe, governor,
trading engine, execution adapter, scanner and dashboard are unchanged.

- Source: `scripts/research/broker_multitf_risk_v10.py`.
- Safe orchestration: GitHub Actions compiles/checks the isolated research
  module, and optionally VPS demo MT5 is accessed **only for read-only
  broker candle testing**. Load source into a Python process in memory
  from pinned GitHub commit; do not create or modify VPS files.
- Data input: native MT5 BID M15, H1 and H4 OHLC plus the spread points
  recorded on each historical candle. ASKs are modeled as BID + bar
  spread, NOT observed historical two-sided ticks.
- Research hypotheses: 5 independent families (trend pullback, breakout
  continuation, liquidity sweep, range fade, momentum expansion), with
  independently gated BUY and SELL logic. No future candle may be an
  entry feature; entry at next bar open and ambiguous TP/SL resolves
  stop-first.
- Fixed, *declared before run* exit grid: ATR stops 1.0 and 1.5;
  targets 1.5R and 2.2R, M15 max holding 32 bars, H1 max holding
  12 bars. Cost assumption 0.03R + stress 0.10R, one adverse broker
  tick per side of entry and exit. No unlimited optimization.
- Window: 2026-06/07 model selection and 2026-08/09 *chronologically
  later retrospective diagnostics*, not genuine independent holdout.
  May historical candles supply only lookback for H4 technical features.
- RISK simulation only for TRAIN-selected candidates using 0.1%, 0.25%
  and 0.5% equity per entry, max 1 or 2 positions, 8% drawdown
  blocking. These are **shadow mathematical models, not governor or
  account changes**.
- All matrices and notes are hypothesis generation. Any diagnostic
  positives need genuine independent evidence and real broker costs,
  commission, swap, slippage, margin rules and tick fills to support
  executable trading.
- Never upload raw broker candles, account identifiers, orders or private
  terminal files to GitHub. Only aggregated model research metrics and
  documented limitations can be committed.

## Results

Pending audited read-only VPS run. Do not invent a profitable strategy
or place orders.
