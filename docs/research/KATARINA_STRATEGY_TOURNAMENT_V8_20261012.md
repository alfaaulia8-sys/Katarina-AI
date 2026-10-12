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


## First runner outcome and controlled fallback

- First genuine Dukascopy daily BID/ASK import attempt reached the GitHub
  Actions runner and passed all its local tests, but the remote server TLS
  handshake timed out. **No historical BID/ASK-based strategy result was
  produced from that failed run.**
- A second, deliberately LOWER-EVIDENCE path downloads a publicly posted
  third-party **M5 OHLCV sample** from getdata-finance GitHub repositories
  (EURUSD, XAUUSD), not from the VPS. It uses one explicit static model
  spread per instrument rather than pretending to have actual bid/ask.
- This fallback is implemented by
  scripts/research/public_github_sample_tournament.py. Neither it nor its
  summaries can support live execution, profitability claims, exact broker
  transaction costs, or uninspected OOS status.
- Estimated ask is built by adding the declared model spread to reference
  OHLC. This is NOT the same quality as archived broker bid/ask ticks.
  Keep outputs labeled PUBLIC_REFERENCE_M5_MODELED_BID_ASK, separately from
  the planned BID/ASK-native higher-quality replay.


## Verified results — second GitHub-runner pilot

Workflow: https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38202938538

**Status: SUCCESS** — initial test suite: 12 standard-library BID/ASK importer
safety tests + 7 fallback public-M5 unit tests passed; runner downloaded
actual public vendor M5 sample data from GitHub, and the research-only
contract passed.

Period: 2026-08-17 to 2026-09-08, UTC source sample, public 5m reference
candles, and a **hypothetical fixed spread**, NOT historical broker
bid/ask ticks or private VPS candle data.

- EURUSD: 4,894 M5 bars, 406 complete H1 bars, 660 raw hypotheses,
  362 model trades; average net modeled R -0.215297; PF 0.6540.
- XAUUSD: 4,683 M5 bars, 388 complete H1 bars, 600 raw hypotheses,
  312 model trades; average modeled R -0.103210; PF 0.82375.
- Pooled strategy hypotheses: 674 hypothetical overlapping model trades;
  average R -0.163411, PF 0.73002. Pooled compounded return must NOT be
  treated as an investable portfolio return.

**By method and direction (NOT broker-validated):**

| Hypothesis | BUY n | BUY mean R | BUY PF | SELL n | SELL mean R | SELL PF |
|---|---:|---:|---:|---:|---:|---:|
| TREND_PULLBACK | 127 | -0.149358 | 0.74162 | 129 | -0.143591 | 0.74529 |
| BREAKOUT_RETEST | 16 | -0.165721 | 0.73315 | 8 | -0.182092 | 0.71798 |
| LIQUIDITY_SWEEP_RECLAIM | 107 | -0.167472 | 0.73257 | 75 | -0.150684 | 0.75248 |
| RANGE_MEAN_REVERSION | 118 | -0.186339 | 0.70832 | 94 | -0.184365 | 0.70462 |

**No candidate achieved positive modeled expectancy in this pilot.**
Multiple-test and overlapping-trade concerns remain. The historical
sample is short and previously researched; source ASK, broker transaction
costs, true tick fills, DST alignment and point-in-time news remain
unverified. No live promotion. 15 other instruments have not been tested
on this independent-source pipeline yet. No files were written to VPS.

The data-source-specific BID/ASK workflow failed solely on an external
TLS handshake timeout. That failed job produced **no valid BID/ASK data**;
do not conflate it with the successful lower-fidelity M5 study.
