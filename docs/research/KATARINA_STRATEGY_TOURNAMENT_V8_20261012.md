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


## V8-B: 11-market / 3-calendar-month extension — 12 October 2026

On GitHub, 11 verified public 5-minute reference data repositories
were available (sample coverage according to provider README through
September 25, 2026): EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD,
EURGBP, EURJPY, XAUUSD, USOIL (WTI reference), US30, NAS100 (US100 proxy).
These are **public market samples, not VPS broker prices**.

The six priority instruments without a verified like-for-like public
M5 sample in this selected feed are USDCHF, NZDUSD, GBPJPY, AUDJPY,
EURAUD, BTCUSD. They are **NOT assumed to be unavailable in the broker**;
broker availability is separate from research data availability.
Missing instruments are explicitly reported, not filled with other
asset returns.

Default public hypothesis tournament now covers **June 1 through
August 31, 2026**, as three disjoint *calendar months*.
GitHub-hosted jobs run four independent market groups:

- major FX: EURUSD, GBPUSD, USDJPY, AUDUSD
- additional FX: USDCAD, EURGBP, EURJPY
- commodity reference: XAUUSD, USOIL
- indices: US30, NAS100

Each job performs closed-M5/H1 research with **modeled fixed spreads**
by asset. Prices use public reference OHLC; the synthetic ask side is
only an assumption. Explicit costs and +0.10R/+0.20R stress are
modeled, with conservative stop-first intrabar ambiguity.
Cross-instrument net P/L is **not a valid tradable portfolio** because
several experimental strategies may overlap.

An evidence-conservative, predeclared RESEARCH TRIAGE gate asks each
method/BUY-SELL/market to have >=20 trades EACH calendar month and
profit factor >=1.20 and average R >=+0.10 EACH month after additional
+0.10R modeled cost. Even if this exploratory screen passes, the
strategy **must remain research-only, not promoted**. Further
independently unseen data, true broker spread/commission/tick path,
exposure allocation and cost reconciliation are required.

- Aggregation: scripts/research/summarize_public_tournament.py
- Tests: tests/unit/intelligence/test_public_tournament_summary.py
- Artifacts: one research summary per group plus a consolidated
  11-market summary from a GitHub-hosted aggregation job.
- VPS file system, services, research sources, MT5 and Risk Governor
  are left **unmodified**. No MT5 connection or live orders.


## V8-B VERIFIED RESULTS — 11 markets, June–August 2026

GitHub Actions final successful run:
https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38204091035
Code commit tested: 89ab73c87c89c3d6e5f6b967ae588df01ba296a0.

- Four research matrix jobs **SUCCESS**, final 11-market aggregator
  **SUCCESS** (5/5). Body CI, Operational Hardening and Stage 10-40
  Baseline on the same commit also **SUCCESS**.
- 11 market sources were fetched. 88 prespecified asset/method/direction
  combinations screened; **0 passed** the exploratory 3-calendar-month
  criterion (>=20 paper trades EACH month and PF >=1.2 and mean R >=+0.10
  AFTER +0.10 R cost stress, all three months).
- **3,995 overlapping hypothetical trade events** were modeled.
  This is neither 3,995 executable distinct portfolio orders nor a
  reliable equity curve.
- The observations are research, not out-of-sample and not broker
  validated. 11 sources are public reference M5 OHLC with *assumed*
  spreads, not genuine bid/ask or verified broker fees.

| Priority source | M5 closed bars | Paper events | Avg modeled R | PF |
|---|---:|---:|---:|---:|
| EURUSD | 19,008 | 7 | -0.115357 | 0.80575 |
| GBPUSD | 19,008 | 8 | -0.589469 | 0.22716 |
| USDJPY | 19,003 | 32 | -0.067931 | 0.85310 |
| AUDUSD | 19,006 | 4 | +0.386014 | 2.47009 |
| USDCAD | 19,006 | 3 | +0.087005 | 1.25136 |
| EURGBP | 19,008 | 0 | n/a | n/a |
| EURJPY | 19,008 | 19 | +0.126244 | 1.32704 |
| XAUUSD | 18,123 | 1,331 | -0.172909 | 0.71840 |
| USOIL | 18,082 | 390 | -0.220409 | 0.62807 |
| US30 | 18,153 | 934 | -0.242821 | 0.61755 |
| NAS100 | 18,159 | 1,267 | -0.229829 | 0.64031 |

**No strategy can be promoted.** AUDUSD, USDCAD and EURJPY modeled
positives have 4, 3 and 19 events respectively and do not meet the
three-month evidence gate, so treating them as demonstrated alpha is
statistically indefensible. The majority of asset models remain
negative. Fixed 0.25% hypothetical risk per paper trade is NOT a
credible portfolio P/L when multiple variants overlap.

BID/ASK actual broker validation, costs/commission reconciliation,
non-overlapping portfolio sizing and genuinely new holdouts are
outstanding. Six missing public M5 sources are separate from broker
availability; do not report them as not traded by broker.

The 11-market consolidated analysis and separate monthly strategy
results remain downloadable temporarily as GitHub Actions artifacts
(retention: 7 days). **No VPS writes, live orders, broker execution
changes or Risk Governor changes** were performed.
