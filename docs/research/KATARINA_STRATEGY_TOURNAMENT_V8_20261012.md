# KATARINA Strategy Tournament — public OHLC pilot (12 October 2026)

**Research-only. No VPS writes, no MT5 connection, no order execution.**

## Hypothesis search (not "every strategy")

First stage is a deliberately bounded family tournament instead of blindly
optimizing millions of technical indicator combinations:

1. TREND_PULLBACK — trend-following continuation.
2. BREAKOUT_RETEST — closed-bar confirmed breakout and retest.
3. LIQUIDITY_SWEEP_RECLAIM — market sweep and reversal.
4. RANGE_MEAN_REVERSION — range edge reversal.

BUY / SELL and H1 observed regime groups are evaluated separately, never
pooling directional performance. The hypotheses are fixed before the
initial public-data pilot; no hyperparameter optimization was performed.

## GitHub-hosted public-data test

- Workflow: .github/workflows/public-strategy-tournament.yml
- Code: scripts/research/public_market_tournament.py
- Tests: tests/unit/intelligence/test_public_market_tournament.py
- First bounded pilot: public EURUSD and XAUUSD bid/ask 1-minute candles,
  2026-09-01 through 2026-09-11 inclusive (UTC).
- Real minute prices are downloaded directly by the GitHub-hosted worker from
  the public Dukascopy datafeed with a conservative daily request cap.
- Raw public minute bar feeds are NOT committed or uploaded to the repo.
  The runner stores only short summary and modeled paper-trade event records
  as ephemeral GitHub Actions artifacts. Its token has read-only contents.
- If data are incomplete, the program fails or skips incomplete candles;
  no synthetic bars are silently substituted.
- Closed M5 and complete H1 bars only; the strategy at time T sees no later
  bars. Historical entry is the NEXT M5 bar open.
- BUY enters at ASK and exits based on BID; SELL enters at BID and exits
  based on ASK. Both stop and target touched within one M5 bar resolves
  to STOP (pessimistic ambiguity), never fictional perfect execution.
- Stops, 1-point adverse entry/exit slippage, hypothetical 0.03 R flat
  fee and extra 0.10/0.20 R cost stress are research approximations.
- Per strategy / side / regime: sample size, expectancy R, PF, win rate,
  model return, modeled drawdown. No automatic promotion to trading.
- A pilot may be statistically inconclusive; do not declare a winner
  without enough trades and further chronological validation.

## Important scientific limitations

The user broker on VPS may have different spreads, contract specifications,
commission schedule and market sessions than public Dukascopy data.
Historical bar replay cannot resolve the real intrabar order of stop/TP,
true slippage, rejected fills, swap, or real account leverage/portfolio
exposure. The pilot dates overlap with already studied periods and do NOT
constitute a new independent holdout. Where OHLC history is missing, no
profitability number is invented. Validation on actual broker's read-only
history is a separate task.

Dukascopy public data format and month index are documented at
https://www.dukascopy.com/wiki/en/development/data-export/ .
For minute candle dataset record format, see the documented .bi5
daily BID/ASK candle convention (>IIIIIf, seconds, open, close, low,
high, volume), with explicit per-symbol scaling and strict decode checks.

Next steps **conditional on a successful real-data pilot**: extend the
public feed scope gradually to other verified market identifiers and
chronological disjoint windows, run sensitivity and multiple-comparison
checks, then validate broker-specific costs using read-only evidence.
Do not promote a winning-looking historical configuration to live.
